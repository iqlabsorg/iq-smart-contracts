import {ethers, waffle} from 'hardhat';
import {expect} from 'chai';
import {BigNumberish, Wallet} from 'ethers';
import {Enterprise, ERC20Mock, PowerToken} from '../typechain';
import {baseRate, deployEnterprise, ONE_DAY, registerService} from './utils';

type EnegryTestCase = [BigNumberish, number, BigNumberish];

const ONE_ETHER = 10n ** 18n;
const ONE_TOKEN = 10n ** 18n;

describe('PowerToken', function () {
  let token: ERC20Mock;
  let user: Wallet;
  let enterprise: Enterprise;
  let powerToken: PowerToken;

  const GAP_HALVING_PERIOD = 100;

  beforeEach(async () => {
    [user] = await waffle.provider.getWallets();
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
      true,
      false
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

  //TODO: write PowerToken transfer tests
});
