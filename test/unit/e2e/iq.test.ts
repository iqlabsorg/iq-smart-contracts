import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import chai from 'chai';
import { BigNumber } from 'ethers';
import { ethers, waffle } from 'hardhat';
import { Enterprise, IERC20Metadata, StakeToken, PowerToken } from '../../../typechain';
import {
  stake,
  basePrice,
  baseRate,
  rent,
  deployEnterprise,
  estimateRentalFee,
  getRentalTokenId,
  getPowerToken,
  increaseTime,
  ONE_DAY,
  toTokens,
} from '../../utils';
chai.use(waffle.solidity);
const { expect } = chai;

describe('IQ Protocol E2E', () => {
  let user: SignerWithAddress;
  let token: IERC20Metadata;
  let enterprise: Enterprise;

  const ONE_TOKEN = 10n ** 18n;

  beforeEach(async () => {
    [, user] = await ethers.getSigners();
    token = (await ethers.getContract('ERC20Mock')) as IERC20Metadata;
    enterprise = await deployEnterprise('Testing', token.address);
  });

  describe('Basic', () => {
    it('should set enterprise token', async () => {
      expect(await enterprise.getEnterpriseToken()).to.equal(token.address);
    });
    it('should deploy stake token', async () => {
      expect(await enterprise.getStakeToken()).not.to.equal(ethers.constants.AddressZero);
    });

    describe('StakeToken', async () => {
      let stakeToken: StakeToken;
      beforeEach(async () => {
        const token = await enterprise.getStakeToken();
        const StakeToken = await ethers.getContractFactory('StakeToken');
        stakeToken = StakeToken.attach(token) as StakeToken;
      });

      it('should set StakeToken name', async () => {
        const symbol = await token.symbol();
        expect(await stakeToken.name()).to.equal(`Staking ${symbol}`);
      });

      it('should set StakeToken symbol', async () => {
        const symbol = await token.symbol();
        expect(await stakeToken.symbol()).to.equal(`s${symbol}`);
      });
    });
  });

  const GAP_HALVING_PERIOD = 86400;
  const BASE_RATE = baseRate(100n, 86400n, 3n);
  describe('Service', () => {
    it('should register service', async () => {
      const txPromise = enterprise.registerService(
        'IQ Power Test',
        'IQPT',
        GAP_HALVING_PERIOD,
        BASE_RATE,
        token.address,
        300, // 3%
        43200, // 12 hours
        86400 * 60, // 2 months
        ONE_TOKEN,
        true
      );

      await expect(txPromise).to.emit(enterprise, 'ServiceRegistered');
      const powerToken = await getPowerToken(enterprise, await txPromise);
      expect(await powerToken.getEnergyGapHalvingPeriod()).to.equal(GAP_HALVING_PERIOD);
    });
  });

  describe('Stake-Rent-Return-Unstake', () => {
    const STAKE_AMOUNT = ONE_TOKEN * 1_000_000n;
    const RENTAL_AMOUNT = ONE_TOKEN * 50n;
    const MAX_PAYMENT_AMOUNT = ONE_TOKEN * 5_000_000n;
    let powerToken: PowerToken;
    let enterpriseTokenId: BigNumber;

    beforeEach(async () => {
      // 2.Create service
      const tx = await enterprise.registerService(
        'IQ Power Test',
        'IQPT',
        GAP_HALVING_PERIOD,
        BASE_RATE,
        token.address,
        300, // 3%
        43200, // 12 hours
        86400 * 60, // 2 months
        0,
        true
      );
      powerToken = await getPowerToken(enterprise, tx);

      // 3. Stake
      enterpriseTokenId = await stake(enterprise, STAKE_AMOUNT);

      await token.transfer(user.address, MAX_PAYMENT_AMOUNT);
    });

    it('should rent-return-unstake', async () => {
      console.log(
        'Estimate:',
        (await enterprise.estimateRentalFee(powerToken.address, token.address, RENTAL_AMOUNT, ONE_DAY)).toString()
      );

      // 4. Rent
      const rentingTx = await rent(enterprise, powerToken, token, RENTAL_AMOUNT, ONE_DAY, MAX_PAYMENT_AMOUNT, user);
      await expect(rentingTx).to.emit(enterprise, 'Rented');
      await increaseTime(86400);

      // 5. Burn
      const tokenId = await getRentalTokenId(enterprise, rentingTx);
      await enterprise.connect(user).returnRental(tokenId);

      await enterprise.unstake(enterpriseTokenId);
    });

    it('2 sequential rentals approximately costs the same as 1 for accumulated amount for the same period (additivity)', async () => {
      const SINGLE_RENTAL_FEE = estimateRentalFee(basePrice(100.0, 86400.0, 3.0), 1000000.0, 0.0, 500000.0, 86400.0);

      const balanceBefore = await token.balanceOf(user.address);

      await rent(enterprise, powerToken, token, ONE_TOKEN * 300000n, ONE_DAY, MAX_PAYMENT_AMOUNT, user);
      await rent(enterprise, powerToken, token, ONE_TOKEN * 200000n, ONE_DAY, MAX_PAYMENT_AMOUNT, user);

      const balanceAfter = await token.balanceOf(user.address);
      const diff = balanceBefore.toBigInt() - balanceAfter.toBigInt();
      expect(toTokens(diff, 8)).to.be.approximately(SINGLE_RENTAL_FEE, 0.1);
    });
  });
});
