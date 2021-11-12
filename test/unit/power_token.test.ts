import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import { expect } from 'chai';
import { BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
import { RentalToken, RentalToken__factory, Enterprise, ERC20Mock, PowerToken } from '../../typechain';
import { Errors } from '../types';
import { stake, baseRate, rent, deployEnterprise, getRentalTokenId, ONE_DAY, registerService } from '../utils';

type EnegryTestCase = [BigNumberish, number, BigNumberish];

const ONE_ETHER = 10n ** 18n;
const ONE_TOKEN = 10n ** 18n;

describe('PowerToken', function () {
  let token: ERC20Mock;
  let user: SignerWithAddress;
  let user2: SignerWithAddress;
  let enterprise: Enterprise;
  let powerToken: PowerToken;
  let rentalToken: RentalToken;

  const GAP_HALVING_PERIOD = 100;

  beforeEach(async () => {
    [user, user2] = await ethers.getSigners();
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

    await stake(enterprise, ONE_TOKEN * 1000n, user);

    rentalToken = RentalToken__factory.connect(await enterprise.getRentalToken(), user);
  });

  describe('energy', () => {
    (
      [
        [ONE_ETHER * 1000n, GAP_HALVING_PERIOD, ONE_ETHER * 500n],
        [ONE_ETHER * 9999n, GAP_HALVING_PERIOD, ethers.utils.parseEther('4999.5')],
      ] as EnegryTestCase[]
    ).forEach(([amount, period, expected], idx) => {
      it(`should calculate energy: ${idx}`, async () => {
        await token.approve(powerToken.address, amount);
        const tx = await powerToken.swapIn(amount);

        const block = await ethers.provider.getBlock((await tx.wait()).blockNumber);

        const result = await powerToken.energyAt(user.address, block.timestamp + period);

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

    it('should be possible to set rental period limits', async () => {
      await powerToken.setRentalPeriodLimits(1, 200);

      expect(await powerToken.getMinRentalPeriod()).to.eq(1);
      expect(await powerToken.getMaxRentalPeriod()).to.eq(200);
    });
  });

  describe('when transfer is disabled', () => {
    it('should not be possible to transfer swapped tokens', async () => {
      await token.approve(powerToken.address, ONE_TOKEN * 100n);
      await powerToken.swapIn(ONE_TOKEN * 100n);

      await expect(powerToken.transfer(user2.address, ONE_TOKEN * 100n)).to.be.revertedWith(
        Errors.PT_TRANSFER_DISABLED
      );
    });

    it('should not be possible to transfer rented tokens', async () => {
      const tx = await rent(enterprise, powerToken, token, ONE_TOKEN * 100n, ONE_DAY * 30, ONE_TOKEN * 100n);
      const rentalTokenId = await getRentalTokenId(enterprise, tx);

      await expect(rentalToken.transferFrom(user.address, user2.address, rentalTokenId)).to.be.revertedWith(
        Errors.PT_TRANSFER_DISABLED
      );
    });
  });

  describe('when transfer is enabled', () => {
    beforeEach(async () => {
      await powerToken.enableTransferForever();
    });

    it('should be possible to transfer swapped tokens', async () => {
      await token.approve(powerToken.address, ONE_TOKEN * 100n);
      await powerToken.swapIn(ONE_TOKEN * 100n);

      await powerToken.transfer(user2.address, ONE_TOKEN * 100n);

      expect(await powerToken.balanceOf(user2.address)).to.eq(ONE_TOKEN * 100n);
    });

    it('should be possible to transfer rented tokens', async () => {
      const tx = await rent(enterprise, powerToken, token, ONE_TOKEN * 100n, ONE_DAY * 30, ONE_TOKEN * 100n);
      const rentalTokenId = await getRentalTokenId(enterprise, tx);

      await rentalToken.transferFrom(user.address, user2.address, rentalTokenId);

      expect(await powerToken.balanceOf(user2.address)).to.eq(ONE_TOKEN * 100n);
    });
  });
});
