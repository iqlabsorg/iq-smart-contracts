import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import chai from 'chai';
import { BigNumber } from 'ethers';
import { ethers, waffle } from 'hardhat';
import {
  RentalToken,
  Enterprise,
  EnterpriseFactory,
  ERC20Mock,
  ERC20Mock__factory,
  IERC20Metadata,
  StakeToken,
  MockConverter,
  MockConverter__factory,
  PowerToken,
} from '../../typechain';
import { Errors } from '../types';
import {
  stake,
  basePrice,
  baseRate,
  rent,
  currentTime,
  deployEnterprise,
  estimateRentalFee,
  fromTokens,
  getRentalToken,
  getRentalTokenId,
  getStakeTokenId,
  getProxyImplementation,
  increaseTime,
  nextBlock,
  ONE_DAY,
  ONE_HOUR,
  extendRentalPeriod,
  registerService,
  setNextBlockTimestamp,
  toTokens,
} from '../utils';

chai.use(waffle.solidity);
const { expect } = chai;

describe('Enterprise', () => {
  let deployer: SignerWithAddress;
  let staker: SignerWithAddress;
  let renter: SignerWithAddress;
  let user: SignerWithAddress;
  let stranger: SignerWithAddress;
  let enterprise: Enterprise;
  let enterpriseToken: IERC20Metadata;
  const ONE_TOKEN = 10n ** 18n;
  const GAP_HALVING_PERIOD = ONE_DAY;
  const BASE_RATE = baseRate(100n * ONE_TOKEN, BigInt(ONE_DAY), 3n * ONE_TOKEN, 18n, 18n);

  beforeEach(async () => {
    [deployer, staker, renter, user, stranger] = await ethers.getSigners();

    enterpriseToken = await new ERC20Mock__factory(deployer).deploy('TST', 'TST', 18, ONE_TOKEN * 100_000_000_000n);
  });

  describe('deployment', () => {
    it('should not be possible to deploy Enterprise with empty name', async () => {
      await expect(deployEnterprise('', enterpriseToken.address)).to.be.revertedWith(Errors.E_INVALID_ENTERPRISE_NAME);
    });

    it('should not be possible to deploy Enterprise with zero token address', async () => {
      await expect(deployEnterprise('Test', ethers.constants.AddressZero)).to.be.reverted;
    });
  });

  describe('simple payment token', () => {
    let powerToken: PowerToken;
    let stakeToken: StakeToken;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', enterpriseToken.address);

      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        enterpriseToken.address,
        300, // 3%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        ONE_TOKEN,
        true
      );
      const StakeToken = await ethers.getContractFactory('StakeToken');

      stakeToken = StakeToken.attach(await enterprise.getStakeToken()) as StakeToken;
    });

    describe('swap in / swap out', () => {
      beforeEach(async () => {
        await enterpriseToken.transfer(user.address, ONE_TOKEN);
        await enterpriseToken.connect(user).approve(powerToken.address, ONE_TOKEN);

        await powerToken.connect(user).swapIn(ONE_TOKEN);
      });

      it('should be possible to swap in enterprise tokens', async () => {
        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN);
        expect(await enterpriseToken.balanceOf(powerToken.address)).to.eq(ONE_TOKEN);
        expect(await enterpriseToken.balanceOf(user.address)).to.eq(0);
      });

      it('should be possible to swap out enterprise tokens', async () => {
        await powerToken.connect(user).swapOut(ONE_TOKEN);

        expect(await powerToken.balanceOf(user.address)).to.eq(0);
        expect(await enterpriseToken.balanceOf(powerToken.address)).to.eq(0);
        expect(await enterpriseToken.balanceOf(user.address)).to.eq(ONE_TOKEN);
      });

      describe('when power token transfer enabled', () => {
        beforeEach(async () => {
          await powerToken.enableTransferForever();
        });

        it('should be possible to transfer swapped power tokens', async () => {
          await powerToken.connect(user).transfer(stranger.address, ONE_TOKEN);

          expect(await powerToken.balanceOf(stranger.address)).to.eq(ONE_TOKEN);
          expect(await powerToken.balanceOf(user.address)).to.eq(0);
        });

        it('should be possible to swap out transferred power tokens', async () => {
          await powerToken.connect(user).transfer(stranger.address, ONE_TOKEN);

          await powerToken.connect(stranger).swapOut(ONE_TOKEN);

          expect(await enterpriseToken.balanceOf(stranger.address)).to.eq(ONE_TOKEN);
          expect(await powerToken.balanceOf(stranger.address)).to.eq(0);
        });
      });
    });
    describe('stake / unstake', () => {
      beforeEach(async () => {
        await enterpriseToken.transfer(staker.address, ONE_TOKEN);
        await enterpriseToken.connect(staker).approve(enterprise.address, ONE_TOKEN);
      });
      it('should be possible to stake', async () => {
        await enterprise.connect(staker).stake(ONE_TOKEN);

        expect(await enterpriseToken.balanceOf(enterprise.address)).to.eq(ONE_TOKEN);
        expect(await enterpriseToken.balanceOf(staker.address)).to.eq(0);
        expect(await stakeToken.balanceOf(staker.address)).to.eq(1);
      });

      it('should be possible to unstake', async () => {
        const tokenId = await stake(enterprise, ONE_TOKEN, staker);

        await enterprise.connect(staker).unstake(tokenId);

        expect(await enterpriseToken.balanceOf(staker.address)).to.eq(ONE_TOKEN);
        expect(await stakeToken.balanceOf(staker.address)).to.eq(0);
      });

      it('should be possible to transfer stake token', async () => {
        const tokenId = await stake(enterprise, ONE_TOKEN, staker);

        await stakeToken.connect(staker).transferFrom(staker.address, stranger.address, tokenId);

        expect(await stakeToken.balanceOf(staker.address)).to.eq(0);
        expect(await stakeToken.balanceOf(stranger.address)).to.eq(1);
      });

      it('should be possible to unstake on transferred stake token', async () => {
        const tokenId = await stake(enterprise, ONE_TOKEN, staker);

        await stakeToken.connect(staker).transferFrom(staker.address, stranger.address, tokenId);

        await enterprise.connect(stranger).unstake(tokenId);

        expect(await enterpriseToken.balanceOf(stranger.address)).to.eq(ONE_TOKEN);
        expect(await stakeToken.balanceOf(stranger.address)).to.eq(0);
      });
    });

    describe('decrease stake', () => {
      const stakerTokens = ONE_TOKEN * 10000n;
      let tokenId: BigNumber;
      beforeEach(async () => {
        await enterpriseToken.transfer(staker.address, stakerTokens);
        await enterpriseToken.transfer(user.address, ONE_TOKEN * 1000n);
        tokenId = await stake(enterprise, stakerTokens, staker);
      });

      it('should be possible to decrease stake to 0', async () => {
        await enterprise.connect(staker).decreaseStake(tokenId, stakerTokens);

        const stakeInfo = await enterprise.getStake(tokenId);
        expect(stakeInfo.amount).to.eq(0n);
        expect(stakeInfo.shares).to.eq(0n);
      });

      describe('when renting', () => {
        beforeEach(async () => {
          const rentingTx = await rent(
            enterprise,
            powerToken,
            enterpriseToken,
            ONE_TOKEN * 1000n,
            ONE_DAY * 30,
            ONE_TOKEN * 1000n,
            user
          );
          const rentalTokenId = await getRentalTokenId(enterprise, rentingTx);
          const now = await currentTime();
          await setNextBlockTimestamp(now + ONE_DAY * 15);
          await enterprise.connect(user).returnRental(rentalTokenId);
        });

        it('should not withdraw reward when decreasing stake to 0', async () => {
          await enterprise.connect(staker).decreaseStake(tokenId, stakerTokens);

          const stakeInfo = await enterprise.getStake(tokenId);
          expect(stakeInfo.amount).to.eq(0n);
          expect(stakeInfo.shares).not.to.eq(0n);
          expect(await enterprise.getStakingReward(tokenId))
            .to.eq(await enterprise.getAvailableReserve())
            .to.eq(await enterprise.getReserve());
        });

        it('should set shares to 0 when withdrawing stake and reward', async () => {
          await enterprise.connect(staker).decreaseStake(tokenId, stakerTokens);

          await enterprise.connect(staker).claimStakingReward(tokenId);

          const stakeInfo = await enterprise.getStake(tokenId);
          expect(stakeInfo.amount).to.eq(0n);
          expect(stakeInfo.shares).to.eq(0n);
          expect(await enterprise.getReserve()).to.eq(0n);
          expect(await enterprise.getAvailableReserve()).to.eq(0n);
        });
      });
    });

    describe('rent / extend rental period / return', () => {
      const STAKE_AMOUNT = ONE_TOKEN * 1000n;
      const RENTAL_AMOUNT = ONE_TOKEN * 100n;
      let tokenId: BigNumber;

      beforeEach(async () => {
        await enterpriseToken.transfer(renter.address, ONE_TOKEN * 5n);
        await enterpriseToken.transfer(staker.address, STAKE_AMOUNT);

        await stake(enterprise, STAKE_AMOUNT, staker);

        const rentingTx = await rent(
          enterprise,
          powerToken,
          enterpriseToken,
          RENTAL_AMOUNT,
          ONE_DAY,
          ONE_TOKEN * 5n,
          renter
        );

        tokenId = await getRentalTokenId(enterprise, rentingTx);
      });

      it('should be possible to rent tokens', async () => {
        expect(await powerToken.balanceOf(renter.address)).to.eq(RENTAL_AMOUNT);
        expect(await enterpriseToken.balanceOf(renter.address)).to.be.below(ONE_TOKEN * 5n);
        expect(await enterpriseToken.balanceOf(enterprise.address)).to.be.above(STAKE_AMOUNT);
      });

      it('should be possible to extendRentalPeriod tokens', async () => {
        await enterpriseToken.transfer(renter.address, ONE_TOKEN * 5n);
        await enterpriseToken.connect(renter).approve(enterprise.address, ONE_TOKEN * 5n);
        const rentalAgreementBefore = await enterprise.getRentalAgreement(tokenId);
        await increaseTime(ONE_DAY);

        await extendRentalPeriod(enterprise, tokenId, enterpriseToken, ONE_DAY, ONE_TOKEN * 5n, renter);

        expect(await enterpriseToken.balanceOf(renter.address)).to.be.below(ONE_TOKEN * 5n);
        const rentalAgreement = await enterprise.getRentalAgreement(tokenId);
        expect(rentalAgreement.endTime).to.be.above(rentalAgreementBefore.endTime);
        expect(rentalAgreement.rentalAmount).to.be.eq(rentalAgreementBefore.rentalAmount);
      });

      it('should be possible to return rented tokens', async () => {
        const balanceBefore = await enterpriseToken.balanceOf(renter.address);
        await increaseTime(ONE_DAY);

        await enterprise.connect(renter).returnRental(tokenId);

        expect(await powerToken.balanceOf(renter.address)).to.eq(0);
        expect(await enterpriseToken.balanceOf(renter.address)).to.be.above(balanceBefore);
        expect(await enterpriseToken.balanceOf(enterprise.address)).to.be.above(STAKE_AMOUNT);
      });
    });
  });

  describe('multiple payment token', () => {
    const USDC_DECIMALS = 6;
    const ONE_USDC = 10n ** BigInt(USDC_DECIMALS);
    let usdc: ERC20Mock;
    let powerToken: PowerToken;
    let converter: MockConverter;
    beforeEach(async () => {
      usdc = await new ERC20Mock__factory(deployer).deploy('USDC', 'USDC', USDC_DECIMALS, ONE_USDC * 1_000_000n);
      converter = await new MockConverter__factory(deployer).deploy();
      enterprise = await deployEnterprise('Test', enterpriseToken.address, converter.address);
      await enterprise.enablePaymentToken(usdc.address);

      await enterpriseToken.transfer(converter.address, ONE_TOKEN * 10000n);
      await usdc.transfer(converter.address, ONE_USDC * 10000n);

      await stake(enterprise, ONE_TOKEN * 100000n);

      await converter.setRate(usdc.address, enterpriseToken.address, 350_000n); // 0.35 cents
    });

    describe('service base price in enterprise tokens', () => {
      beforeEach(async () => {
        powerToken = await registerService(
          enterprise,
          GAP_HALVING_PERIOD,
          BASE_RATE,
          enterpriseToken.address,
          300, // 3%
          ONE_HOUR * 12,
          ONE_DAY * 60,
          0,
          true
        );
      });
      it('should be possible to rent paying with USDC', async () => {
        const enterpriseBalance = await enterpriseToken.balanceOf(enterprise.address);
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);

        const rentalFee = estimateRentalFee(basePrice(100, ONE_DAY, 3), 100000, 0, 10000, ONE_DAY);

        await rent(enterprise, powerToken, usdc, ONE_TOKEN * 10000n, ONE_DAY, usdcBalance, user);

        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN * 10000n);
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)).to.closeTo(rentalFee * 0.35, 0.1);
        expect(await enterpriseToken.balanceOf(enterprise.address)).to.be.above(enterpriseBalance);
      });

      it('should be possible to extendRentalPeriod paying with USDC', async () => {
        const enterpriseBalance = await enterpriseToken.balanceOf(enterprise.address);
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        await enterpriseToken.transfer(user.address, ONE_TOKEN * 1000n);
        const tokenBalance = await enterpriseToken.balanceOf(user.address);
        const rentalFee = estimateRentalFee(basePrice(100, ONE_DAY, 3), 100000, 0, 10000, ONE_DAY);
        const rentingTx = await rent(
          enterprise,
          powerToken,
          enterpriseToken,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          tokenBalance,
          user
        );
        const rentalTokenId = await getRentalTokenId(enterprise, rentingTx);
        await increaseTime(ONE_DAY);
        const enterpriseBalance2 = await enterpriseToken.balanceOf(enterprise.address);

        await extendRentalPeriod(enterprise, rentalTokenId, usdc, ONE_DAY, usdcBalance, user);

        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN * 10000n);
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)).to.closeTo(rentalFee * 0.35, 0.1);
        const enterpriseBalanceAfter = await enterpriseToken.balanceOf(enterprise.address);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance2);
        expect(enterpriseBalance2).to.be.above(enterpriseBalance);
      });
    });

    describe('service base price in USDC', () => {
      beforeEach(async () => {
        powerToken = await registerService(
          enterprise,
          GAP_HALVING_PERIOD,
          baseRate(100n * ONE_TOKEN, BigInt(ONE_DAY), (ONE_USDC * 3n) / 2n, 18n, BigInt(USDC_DECIMALS)), // 1.5 USDC for 100 tokens per day
          usdc.address,
          300, // 3%
          ONE_HOUR * 12,
          ONE_DAY * 60,
          0,
          true
        );
      });
      it('should be possible to rent paying with USDC', async () => {
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        const enterpriseBalance = await enterpriseToken.balanceOf(enterprise.address);

        const rentalFee = estimateRentalFee(basePrice(100, ONE_DAY, 1.5), 100000, 0, 10000, ONE_DAY);

        await rent(enterprise, powerToken, usdc, ONE_TOKEN * 10000n, ONE_DAY, usdcBalance, user);

        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN * 10000n);
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)).to.closeTo(rentalFee, 0.001);
        expect(await enterpriseToken.balanceOf(enterprise.address)).to.be.above(enterpriseBalance);
      });

      it('should be possible to extend rental period paying with USDC', async () => {
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        await enterpriseToken.transfer(user.address, ONE_TOKEN * 1000n);
        const tokenBalance = await enterpriseToken.balanceOf(user.address);
        const enterpriseBalance = await enterpriseToken.balanceOf(enterprise.address);
        const rentalFee = estimateRentalFee(basePrice(100.0, ONE_DAY, 1.5), 100000.0, 0, 10000.0, ONE_DAY);
        const rentingTx = await rent(
          enterprise,
          powerToken,
          enterpriseToken,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          tokenBalance,
          user
        );
        const rentalTokenId = await getRentalTokenId(enterprise, rentingTx);
        await increaseTime(ONE_DAY);

        const enterpriseBalance2 = await enterpriseToken.balanceOf(enterprise.address);
        await extendRentalPeriod(enterprise, rentalTokenId, usdc, ONE_DAY, usdcBalance, user);

        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN * 10000n);
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)).to.closeTo(rentalFee, 0.01);
        const enterpriseBalanceAfter = await enterpriseToken.balanceOf(enterprise.address);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance2);
        expect(enterpriseBalance2).to.be.above(enterpriseBalance);
      });

      it('should be possible to rent paying with enterprise tokens', async () => {
        const enterpriseBalance = await enterpriseToken.balanceOf(enterprise.address);
        const tokenBalance = ONE_TOKEN * 1000n;
        await enterpriseToken.transfer(user.address, tokenBalance);
        const rentalFee = estimateRentalFee(basePrice(100, ONE_DAY, 1.5), 100000, 0, 10000, ONE_DAY);
        const convertedRentalFee = await converter.estimateConvert(
          usdc.address,
          fromTokens(rentalFee, 6, USDC_DECIMALS),
          enterpriseToken.address
        );

        await rent(enterprise, powerToken, enterpriseToken, ONE_TOKEN * 10000n, ONE_DAY, tokenBalance, user);

        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN * 10000n);
        const balanceAfter = await enterpriseToken.balanceOf(user.address);
        expect(toTokens(tokenBalance - balanceAfter.toBigInt(), 3, 18)).to.closeTo(
          toTokens(convertedRentalFee, 3),
          0.001
        );
        expect(await enterpriseToken.balanceOf(enterprise.address)).to.be.above(enterpriseBalance);
      });

      it('should be possible to extendRentalPeriod paying with enterprise tokens', async () => {
        const enterpriseBalance = await enterpriseToken.balanceOf(enterprise.address);
        const tokenBalance = ONE_TOKEN * 1000n;
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        await enterpriseToken.transfer(user.address, tokenBalance);
        const rentalFee = estimateRentalFee(basePrice(100, ONE_DAY, 1.5), 100000, 0, 10000, ONE_DAY);
        const convertedRentalFee = await converter.estimateConvert(
          usdc.address,
          fromTokens(rentalFee, 6, USDC_DECIMALS),
          enterpriseToken.address
        );
        const rentingTx = await rent(enterprise, powerToken, usdc, ONE_TOKEN * 10000n, ONE_DAY, usdcBalance, user);
        const rentalTokenId = await getRentalTokenId(enterprise, rentingTx);
        await increaseTime(ONE_DAY);
        const enterpriseBalance2 = await enterpriseToken.balanceOf(enterprise.address);

        await extendRentalPeriod(enterprise, rentalTokenId, enterpriseToken, ONE_DAY, tokenBalance, user);

        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN * 10000n);
        const balanceAfter = await enterpriseToken.balanceOf(user.address);
        expect(toTokens(tokenBalance - balanceAfter.toBigInt(), 3, 18)).to.closeTo(
          toTokens(convertedRentalFee, 3),
          0.01
        );
        const enterpriseBalanceAfter = await enterpriseToken.balanceOf(enterprise.address);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance2);
        expect(enterpriseBalance2).to.be.above(enterpriseBalance);
      });
    });
  });

  describe('claim reward', () => {
    let powerToken: PowerToken;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', enterpriseToken.address);
      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        baseRate(100n * ONE_TOKEN, BigInt(ONE_DAY), ONE_TOKEN * 3n),
        enterpriseToken.address,
        0, // 0%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        0,
        true
      );
      await enterpriseToken.transfer(staker.address, ONE_TOKEN * 10_000n);
      await enterpriseToken.transfer(renter.address, ONE_TOKEN * 1_000n);
    });

    it('should be possible to claim staking reward', async () => {
      const tokenId = await stake(enterprise, ONE_TOKEN * 10_000n, staker);
      const rentalFee = await enterprise.estimateRentalFee(
        powerToken.address,
        enterpriseToken.address,
        ONE_TOKEN * 1_000n,
        ONE_DAY * 15
      );
      await rent(enterprise, powerToken, enterpriseToken, ONE_TOKEN * 1_000n, ONE_DAY * 15, ONE_TOKEN * 1_000n, renter);
      await increaseTime(ONE_DAY * 365);
      const { totalShares: totalSharesBefore } = await enterprise.getInfo();
      const stakeInfoBefore = await enterprise.getStake(tokenId);
      const balanceBefore = await enterpriseToken.balanceOf(staker.address);
      const reservesBefore = await enterprise.getReserve();

      await enterprise.connect(staker).claimStakingReward(tokenId);

      const stakeInfoAfter = await enterprise.getStake(tokenId);
      const balanceAfter = await enterpriseToken.balanceOf(staker.address);

      expect(toTokens(rentalFee, 5)).to.approximately(toTokens(balanceAfter.sub(balanceBefore).toBigInt(), 5), 0.00001);
      const shares = totalSharesBefore.mul(stakeInfoBefore.amount).div(reservesBefore);
      expect(stakeInfoAfter.shares).to.eq(shares);
    });
  });

  describe('multi renting scenario', () => {
    let powerToken: PowerToken;
    let streamingReserveHalvingPeriod: number;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', enterpriseToken.address);
      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        baseRate(1000n * ONE_TOKEN, BigInt(ONE_DAY), ONE_TOKEN * 3n),
        enterpriseToken.address,
        0, // 0%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        0,
        true
      );
      await enterpriseToken.transfer(renter.address, ONE_TOKEN * 1000n);

      streamingReserveHalvingPeriod = await enterprise.getStreamingReserveHalvingPeriod();
    });

    it('scenario', async () => {
      const tokenId1 = await stake(enterprise, ONE_TOKEN * 10_000n);

      expect(await enterprise.getStakingReward(tokenId1)).to.eq(0);

      await increaseTime(ONE_DAY / 2);

      expect(await enterprise.getStakingReward(tokenId1)).to.eq(0);

      const renterBalance1 = await enterpriseToken.balanceOf(renter.address);
      await expect(
        rent(enterprise, powerToken, enterpriseToken, ONE_TOKEN * 1_000n, ONE_DAY * 30, ONE_TOKEN * 50n, renter)
      ).to.be.revertedWith(Errors.E_RENTAL_PAYMENT_SLIPPAGE); // 50 tokens is not enough

      const rentingTx1 = await rent(
        enterprise,
        powerToken,
        enterpriseToken,
        ONE_TOKEN * 1_000n,
        ONE_DAY * 30,
        ONE_TOKEN * 800n,
        renter
      );
      await expect(rentingTx1).to.emit(enterprise, 'Rented');
      const rentingReceipt = await rentingTx1.wait();

      const rentBlock = await ethers.provider.getBlock(rentingReceipt.blockNumber);
      const rentTimestamp = rentBlock.timestamp;

      const renter1Paid = renterBalance1.sub(await enterpriseToken.balanceOf(renter.address));

      const rentalTokenId1 = await getRentalTokenId(enterprise, rentingTx1);

      await nextBlock(rentTimestamp + streamingReserveHalvingPeriod);

      expect(toTokens(await enterprise.getStakingReward(tokenId1), 3)).to.approximately(
        toTokens(renter1Paid.div(2), 3),
        0.001
      );

      await enterpriseToken.approve(enterprise.address, ONE_TOKEN * 2_000n);
      await expect(enterprise.unstake(tokenId1)).to.be.revertedWith(Errors.E_INSUFFICIENT_LIQUIDITY);

      await setNextBlockTimestamp(rentTimestamp + streamingReserveHalvingPeriod * 2);
      const stakeTx = await enterprise.stake(ONE_TOKEN * 2_000n);
      const tokenId2 = await getStakeTokenId(enterprise, stakeTx);

      expect(toTokens(await enterprise.getStakingReward(tokenId1), 3)).to.approximately(
        toTokens(renter1Paid.mul(3).div(4), 3),
        0.001
      );

      expect(await enterprise.getStakingReward(tokenId2)).to.eq(0);

      await nextBlock(rentTimestamp + streamingReserveHalvingPeriod * 3);

      const [stake1, stake2] = await Promise.all([enterprise.getStake(tokenId1), enterprise.getStake(tokenId2)]);

      const staker2Reward = renter1Paid.mul(stake2.shares).div(stake1.shares.add(stake2.shares).mul(8));

      expect(toTokens(await enterprise.getStakingReward(tokenId2), 3)).to.approximately(
        toTokens(staker2Reward, 3),
        0.001
      );

      await increaseTime(ONE_DAY * 5);

      await expect(enterprise.unstake(tokenId1)).to.emit(enterprise, 'StakeChanged');
      await expect(enterprise.unstake(tokenId2)).to.be.revertedWith(Errors.E_INSUFFICIENT_LIQUIDITY);
      await expect(enterprise.decreaseStake(tokenId2, ONE_TOKEN * 10n)).to.emit(enterprise, 'StakeChanged');

      const rentalAgreement2 = await enterprise.getStake(tokenId2);
      expect(rentalAgreement2.amount).to.eq(ONE_TOKEN * 1_990n);

      await expect(enterprise.connect(stranger).returnRental(rentalTokenId1)).to.be.revertedWith(
        Errors.E_INVALID_CALLER_WITHIN_RENTER_ONLY_RETURN_PERIOD
      );

      await increaseTime(ONE_DAY * 4.5); // because of 12 hours of renter and enterprise grace period

      await expect(enterprise.unstake(tokenId2)).to.be.revertedWith(Errors.E_INSUFFICIENT_LIQUIDITY);
      await expect(enterprise.connect(stranger).returnRental(rentalTokenId1)).to.be.revertedWith(
        Errors.E_INVALID_CALLER_WITHIN_ENTERPRISE_ONLY_COLLECTION_PERIOD
      ); // still cannot return rental

      await increaseTime(ONE_DAY);

      await expect(enterprise.connect(stranger).returnRental(rentalTokenId1)).to.emit(enterprise, 'RentalReturned');

      await expect(enterprise.connect(renter).returnRental(rentalTokenId1)).to.be.revertedWith(
        Errors.E_INVALID_RENTAL_TOKEN_ID
      );

      await enterprise.decreaseStake(tokenId2, ONE_TOKEN * 1_990n);

      expect(await enterprise.getStakingReward(tokenId2))
        .to.eq(await enterprise.getAvailableReserve())
        .to.eq(await enterprise.getReserve());

      await enterpriseToken.approve(enterprise.address, ONE_TOKEN * 2_000n);
      await expect(enterprise.increaseStake(tokenId2, ONE_TOKEN * 2_000n)).to.emit(enterprise, 'StakeChanged');

      const rentalAgreement3 = await enterprise.getStake(tokenId2);
      expect(rentalAgreement3.amount).to.eq(ONE_TOKEN * 2_000n);

      const reward = await enterprise.getStakingReward(tokenId2);

      expect(await enterprise.getReserve()).to.eq(reward.add(ONE_TOKEN * 2000n));
    });
  });

  describe('Enterprise upgradability', () => {
    let enterpriseFactory: EnterpriseFactory;
    beforeEach(async () => {
      enterpriseFactory = (await ethers.getContract('EnterpriseFactory')) as EnterpriseFactory;
      enterprise = await deployEnterprise('Test', enterpriseToken.address);
    });

    it('should not be possible to upgrade without specifying EnterpriseFactory address', async () => {
      await expect(
        enterprise.upgrade(
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          []
        )
      ).to.be.revertedWith(Errors.E_INVALID_ENTERPRISE_FACTORY_ADDRESS);
    });

    it('should be possible to upgrade EnterpriseFactory address', async () => {
      const factory = '0x0000000000000000000000000000000000000001';
      await enterprise.upgrade(
        factory,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        []
      );

      expect(await enterprise.getFactory()).to.equal(factory);
    });

    it('should be possible to upgrade Enterprise', async () => {
      const Enterprise = await ethers.getContractFactory('Enterprise');
      const enterpriseImpl = await Enterprise.deploy();

      await enterprise.upgrade(
        enterpriseFactory.address,
        enterpriseImpl.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        []
      );

      expect(await getProxyImplementation(enterprise, enterprise)).eq(enterpriseImpl.address);
    });

    it('should be possible to upgrade PowerToken', async () => {
      const powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        enterpriseToken.address,
        0,
        0, // min rental period
        10, // max rental period
        0,
        true
      );

      const PowerToken = await ethers.getContractFactory('PowerToken');
      const powerTokenImpl = await PowerToken.deploy();

      await enterprise.upgrade(
        enterpriseFactory.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        powerTokenImpl.address,
        [powerToken.address]
      );

      expect(await getProxyImplementation(enterprise, powerToken)).eq(powerTokenImpl.address);
    });

    it('should be possible to upgrade RentalToken', async () => {
      const RentalToken = await ethers.getContractFactory('RentalToken');
      const rentalToken = RentalToken.attach(await enterprise.getRentalToken());
      const rentalTokenImpl = await RentalToken.deploy();

      await enterprise.upgrade(
        enterpriseFactory.address,
        ethers.constants.AddressZero,
        rentalTokenImpl.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        []
      );

      expect(await getProxyImplementation(enterprise, rentalToken)).eq(rentalTokenImpl.address);
    });

    it('should be possible to upgrade StakeToken', async () => {
      const StakeToken = await ethers.getContractFactory('StakeToken');
      const stakeToken = StakeToken.attach(await enterprise.getStakeToken());
      const stakeTokenImpl = await StakeToken.deploy();

      await enterprise.upgrade(
        enterpriseFactory.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        stakeTokenImpl.address,
        ethers.constants.AddressZero,
        []
      );

      expect(await getProxyImplementation(enterprise, stakeToken)).eq(stakeTokenImpl.address);
    });
  });

  describe('After enterprise shutdown', () => {
    let powerToken: PowerToken;
    let tokenId: BigNumber;
    let rentalTokenId: BigNumber;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', enterpriseToken.address);
      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        enterpriseToken.address,
        0,
        0,
        ONE_DAY * 365,
        0,
        true
      );
      tokenId = await stake(enterprise, ONE_TOKEN * 10_000n);
      await enterpriseToken.transfer(renter.address, ONE_TOKEN * 1000n);
      const rentingTx = await rent(
        enterprise,
        powerToken,
        enterpriseToken,
        ONE_TOKEN * 500n,
        ONE_DAY,
        ONE_TOKEN * 1000n,
        renter
      );

      rentalTokenId = await getRentalTokenId(enterprise, rentingTx);

      await enterprise.shutdownEnterpriseForever();
    });

    it('should not be possible to stake', async () => {
      await expect(stake(enterprise, ONE_TOKEN)).to.be.reverted;
    });

    it('should not be possible to increase stake', async () => {
      await expect(enterprise.increaseStake(tokenId, ONE_TOKEN)).to.be.reverted;
    });

    it('should not be possible to rent', async () => {
      await expect(rent(enterprise, powerToken, enterpriseToken, ONE_TOKEN * 500n, ONE_DAY, ONE_TOKEN * 1000n, renter))
        .to.be.reverted;
    });

    it('should to be possible to extendRentalPeriod', async () => {
      await expect(enterprise.extendRentalPeriod(rentalTokenId, enterpriseToken.address, ONE_DAY, ONE_TOKEN * 1_000n))
        .to.be.reverted;
    });

    it('should be possible to unstake without returning rental', async () => {
      await enterprise.unstake(tokenId);
    });

    it('should be possible to return rental', async () => {
      await enterprise.connect(renter).returnRental(rentalTokenId);
    });

    it('should be possible to decrease stake', async () => {
      await enterprise.decreaseStake(tokenId, ONE_TOKEN);
    });

    it('should be possible to claim staking reward', async () => {
      await enterprise.claimStakingReward(tokenId);
    });
  });

  describe('PowerToken transfer', () => {
    let powerToken: PowerToken;
    let rentalToken: RentalToken;
    let rentalTokenId: BigNumber;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', enterpriseToken.address);

      rentalToken = await getRentalToken(enterprise);

      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        enterpriseToken.address,
        300, // 3%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        ONE_TOKEN,
        true
      );

      await enterpriseToken.transfer(renter.address, ONE_TOKEN * 1_000n);

      await stake(enterprise, ONE_TOKEN * 10_000n);
      const rentingTx = await rent(
        enterprise,
        powerToken,
        enterpriseToken,
        ONE_TOKEN * 100n,
        ONE_DAY,
        ONE_TOKEN * 100n,
        renter
      );
      rentalTokenId = await getRentalTokenId(enterprise, rentingTx);
    });

    it('should not be possible to move rented tokens by default', async () => {
      await expect(
        rentalToken.connect(renter).transferFrom(renter.address, stranger.address, rentalTokenId)
      ).to.be.revertedWith(Errors.PT_TRANSFER_DISABLED);
    });

    describe('when PowerToken transfer is enabled', () => {
      beforeEach(async () => {
        await powerToken.enableTransferForever();
      });

      it('should not be possible to move rented PowerToken directly', async () => {
        expect(await powerToken.balanceOf(renter.address)).to.eq(ONE_TOKEN * 100n);
        await expect(powerToken.connect(renter).transfer(stranger.address, ONE_TOKEN * 100n)).to.be.revertedWith(
          Errors.PT_INSUFFICIENT_AVAILABLE_BALANCE
        );
      });

      it('should be possible to move rented PowerToken by moving RentalToken', async () => {
        await rentalToken.connect(renter).transferFrom(renter.address, stranger.address, rentalTokenId);

        expect(await powerToken.balanceOf(renter.address)).to.eq(0);
        expect(await powerToken.balanceOf(stranger.address)).to.eq(ONE_TOKEN * 100n);
      });

      it('should not be possible to move expired rented PowerToken', async () => {
        await increaseTime(ONE_DAY * 2);

        await expect(
          rentalToken.connect(renter).transferFrom(renter.address, stranger.address, rentalTokenId)
        ).to.be.revertedWith(Errors.E_RENTAL_TRANSFER_NOT_ALLOWED);
      });
    });
  });
});
