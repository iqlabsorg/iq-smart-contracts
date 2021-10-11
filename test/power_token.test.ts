import {ethers, waffle} from 'hardhat';
import {expect} from 'chai';
import {BigNumberish, Wallet} from 'ethers';
import {
  BorrowToken,
  BorrowToken__factory,
  Enterprise,
  ERC20Mock,
  PowerToken,
} from '../typechain';
import {
  addLiquidity,
  baseRate,
  borrow,
  deployEnterprise,
  getBorrowTokenId,
  ONE_DAY,
  registerService,
} from './utils';
import {Errors} from './types';

type EnegryTestCase = [BigNumberish, number, BigNumberish];

const ONE_ETHER = 10n ** 18n;
const ONE_TOKEN = 10n ** 18n;

describe('PowerToken', function () {
  let token: ERC20Mock;
  let user: Wallet;
  let user2: Wallet;
  let enterprise: Enterprise;
  let powerToken: PowerToken;
  let borrowToken: BorrowToken;

  const GAP_HALVING_PERIOD = 100;

  beforeEach(async () => {
    [user, user2] = await waffle.provider.getWallets();
    token = (await ethers.getContract('ERC20Mock')) as ERC20Mock;
    enterprise = await deployEnterprise('Testing', token.address);

    powerToken = await registerService(
      enterprise,
      GAP_HALVING_PERIOD,
      baseRate(100n, 86400n, 3n),
      token.address,
      300,
      0,
      ONE_DAY * 365,
      ONE_TOKEN,
      true
    );

    await addLiquidity(enterprise, ONE_TOKEN * 1000n, user);

    borrowToken = BorrowToken__factory.connect(
      await enterprise.getBorrowToken(),
      user
    );
  });

  describe('energy', () => {
    (
      [
        [ONE_ETHER * 1000n, GAP_HALVING_PERIOD, ONE_ETHER * 500n],
        [
          ONE_ETHER * 9999n,
          GAP_HALVING_PERIOD,
          ethers.utils.parseEther('4999.5'),
        ],
      ] as EnegryTestCase[]
    ).forEach(([amount, period, expected], idx) => {
      it(`should calculate energy: ${idx}`, async () => {
        await token.approve(powerToken.address, amount);
        const tx = await powerToken.wrap(amount);

        const block = await ethers.provider.getBlock(
          (
            await tx.wait()
          ).blockNumber
        );

        const result = await powerToken.energyAt(
          user.address,
          block.timestamp + period
        );

        expect(result).to.equal(expected);
      });
    });
  });

  describe('Basic', () => {
    it('should be possible to set base rate', async () => {
      await powerToken.setBaseRate(5, token.address, ONE_TOKEN);

      expect(await powerToken.getBaseRate()).to.eq(5);
      expect(await powerToken.getMinGCFee()).to.eq(ONE_TOKEN);
    });

    it('should be possible to set service fee percent', async () => {
      await powerToken.setServiceFeePercent(500);

      expect(await powerToken.getServiceFeePercent()).to.eq(500);
    });

    it('should be possible to set loan duration limits', async () => {
      await powerToken.setLoanDurationLimits(1, 200);

      expect(await powerToken.getMinLoanDuration()).to.eq(1);
      expect(await powerToken.getMaxLoanDuration()).to.eq(200);
    });
  });

  describe('when transfers are disabled', () => {
    it('should not be possible to transfer wrapped tokens', async () => {
      await token.approve(powerToken.address, ONE_TOKEN * 100n);
      await powerToken.wrap(ONE_TOKEN * 100n);

      await expect(
        powerToken.transfer(user2.address, ONE_TOKEN * 100n)
      ).to.be.revertedWith(Errors.PT_TRANSFER_NOT_ALLOWED);
    });

    it('should not be possible to transfer borrowed tokens', async () => {
      const tx = await borrow(
        enterprise,
        powerToken,
        token,
        ONE_TOKEN * 100n,
        ONE_DAY * 30,
        ONE_TOKEN * 100n
      );
      const borrowId = await getBorrowTokenId(enterprise, tx);

      await expect(
        borrowToken.transferFrom(user.address, user2.address, borrowId)
      ).to.be.revertedWith(Errors.PT_TRANSFER_NOT_ALLOWED);
    });
  });

  describe('when transfers are enabled', () => {
    beforeEach(async () => {
      await powerToken.enableTransfersForever();
    });

    it('should be possible to transfer wrapped tokens', async () => {
      await token.approve(powerToken.address, ONE_TOKEN * 100n);
      await powerToken.wrap(ONE_TOKEN * 100n);

      await powerToken.transfer(user2.address, ONE_TOKEN * 100n);

      expect(await powerToken.balanceOf(user2.address)).to.eq(ONE_TOKEN * 100n);
    });

    it('should be possible to transfer borrowed tokens', async () => {
      const tx = await borrow(
        enterprise,
        powerToken,
        token,
        ONE_TOKEN * 100n,
        ONE_DAY * 30,
        ONE_TOKEN * 100n
      );
      const borrowId = await getBorrowTokenId(enterprise, tx);

      await borrowToken.transferFrom(user.address, user2.address, borrowId);

      expect(await powerToken.balanceOf(user2.address)).to.eq(ONE_TOKEN * 100n);
    });
  });
});
