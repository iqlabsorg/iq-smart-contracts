import {ethers, waffle} from 'hardhat';
import chai from 'chai';
import {
  BorrowToken,
  Enterprise,
  ERC20Mock,
  ERC20Mock__factory,
  IERC20Metadata,
  InterestToken,
  IPowerToken,
  MockConverter,
  MockConverter__factory,
  PowerToken,
} from '../typechain';
import {
  addLiquidity,
  basePrice,
  baseRate,
  borrow,
  deployEnterprise,
  estimateLoan,
  fromTokens,
  getBorrowToken,
  getBorrowTokenId,
  getInterestTokenId,
  getProxyImplementation,
  increaseTime,
  nextBlock,
  ONE_DAY,
  ONE_HOUR,
  reborrow,
  registerService,
  setNextBlockTimestamp,
  toTokens,
} from './utils';
import {Wallet} from '@ethersproject/wallet';
import {BigNumber} from 'ethers';
import {Errors} from './types';

chai.use(waffle.solidity);
const {expect} = chai;

describe('Enterprise', () => {
  let deployer: Wallet;
  let lender: Wallet;
  let borrower: Wallet;
  let user: Wallet;
  let stranger: Wallet;
  let enterprise: Enterprise;
  let token: IERC20Metadata;
  const ONE_TOKEN = 10n ** 18n;
  const GAP_HALVING_PERIOD = ONE_DAY;
  const BASE_RATE = baseRate(
    100n * ONE_TOKEN,
    BigInt(ONE_DAY),
    3n * ONE_TOKEN,
    18n,
    18n
  );

  beforeEach(async () => {
    [deployer, lender, borrower, user, stranger] =
      await waffle.provider.getWallets();

    token = await new ERC20Mock__factory(deployer).deploy(
      'TST',
      'TST',
      18,
      ONE_TOKEN * 1_000_000n
    );
  });

  describe('simple payment token', () => {
    let powerToken: PowerToken;
    let interestToken: InterestToken;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);

      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        token.address,
        300, // 3%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        ONE_TOKEN,
        true
      );
      const InterestToken = await ethers.getContractFactory('InterestToken');

      interestToken = InterestToken.attach(
        await enterprise.getInterestToken()
      ) as InterestToken;
    });

    describe('wrap / unwrap', () => {
      beforeEach(async () => {
        await token.transfer(user.address, ONE_TOKEN);
        await token.connect(user).approve(powerToken.address, ONE_TOKEN);

        await powerToken.connect(user).wrap(ONE_TOKEN);
      });
      it('should be possible to wrap liquidty tokens', async () => {
        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN);
        expect(await token.balanceOf(powerToken.address)).to.eq(ONE_TOKEN);
        expect(await token.balanceOf(user.address)).to.eq(0);
      });

      it('should be possible to unwrap liquidty tokens', async () => {
        await powerToken.connect(user).unwrap(ONE_TOKEN);

        expect(await powerToken.balanceOf(user.address)).to.eq(0);
        expect(await token.balanceOf(powerToken.address)).to.eq(0);
        expect(await token.balanceOf(user.address)).to.eq(ONE_TOKEN);
      });

      it('should be possible to transfer wraped power tokens', async () => {
        await powerToken.connect(user).transfer(stranger.address, ONE_TOKEN);

        expect(await powerToken.balanceOf(stranger.address)).to.eq(ONE_TOKEN);
        expect(await powerToken.balanceOf(user.address)).to.eq(0);
      });

      it('should be possible to unwrap transferred power tokens', async () => {
        await powerToken.connect(user).transfer(stranger.address, ONE_TOKEN);

        await powerToken.connect(stranger).unwrap(ONE_TOKEN);

        expect(await token.balanceOf(stranger.address)).to.eq(ONE_TOKEN);
        expect(await powerToken.balanceOf(stranger.address)).to.eq(0);
      });
    });
    describe('add liquidity / remove liquidity', () => {
      beforeEach(async () => {
        await token.transfer(lender.address, ONE_TOKEN);
        await token.connect(lender).approve(enterprise.address, ONE_TOKEN);
      });
      it('should be possible to add liquidity', async () => {
        await enterprise.connect(lender).addLiquidity(ONE_TOKEN);

        expect(await token.balanceOf(enterprise.address)).to.eq(ONE_TOKEN);
        expect(await token.balanceOf(lender.address)).to.eq(0);
        expect(await interestToken.balanceOf(lender.address)).to.eq(1);
      });

      it('should be possible to remove liquidity', async () => {
        const tokenId = await addLiquidity(enterprise, ONE_TOKEN, lender);

        await enterprise.connect(lender).removeLiquidity(tokenId);

        expect(await token.balanceOf(lender.address)).to.eq(ONE_TOKEN);
        expect(await interestToken.balanceOf(lender.address)).to.eq(0);
      });

      it('should be possible to transfer interest token', async () => {
        const tokenId = await addLiquidity(enterprise, ONE_TOKEN, lender);

        await interestToken
          .connect(lender)
          .transferFrom(lender.address, stranger.address, tokenId);

        expect(await interestToken.balanceOf(lender.address)).to.eq(0);
        expect(await interestToken.balanceOf(stranger.address)).to.eq(1);
      });

      it('should be possible to remove liquidity on transfered interest token', async () => {
        const tokenId = await addLiquidity(enterprise, ONE_TOKEN, lender);

        await interestToken
          .connect(lender)
          .transferFrom(lender.address, stranger.address, tokenId);

        await enterprise.connect(stranger).removeLiquidity(tokenId);

        expect(await token.balanceOf(stranger.address)).to.eq(ONE_TOKEN);
        expect(await interestToken.balanceOf(stranger.address)).to.eq(0);
      });
    });
    describe('borrow / reborrow / return', () => {
      const LIQUIDITY = ONE_TOKEN * 1000n;
      const BORROW_AMOUNT = ONE_TOKEN * 100n;
      let tokenId: BigNumber;

      beforeEach(async () => {
        await token.transfer(borrower.address, ONE_TOKEN * 5n);
        await token.transfer(lender.address, LIQUIDITY);

        await addLiquidity(enterprise, LIQUIDITY, lender);

        const borrowTx = await borrow(
          enterprise,
          powerToken,
          token,
          BORROW_AMOUNT,
          ONE_DAY,
          ONE_TOKEN * 5n,
          borrower
        );

        tokenId = await getBorrowTokenId(enterprise, borrowTx);
      });

      it('should be possible to borrow tokens', async () => {
        expect(await powerToken.balanceOf(borrower.address)).to.eq(
          BORROW_AMOUNT
        );
        expect(await token.balanceOf(borrower.address)).to.be.below(
          ONE_TOKEN * 5n
        );
        expect(await token.balanceOf(enterprise.address)).to.be.above(
          LIQUIDITY
        );
      });

      it('should be possible to reborrow tokens', async () => {
        await token.transfer(borrower.address, ONE_TOKEN * 5n);
        await token
          .connect(borrower)
          .approve(enterprise.address, ONE_TOKEN * 5n);
        const loanInfoBefore = await enterprise.getLoanInfo(tokenId);
        await increaseTime(ONE_DAY);

        await reborrow(
          enterprise,
          tokenId,
          token,
          ONE_DAY,
          ONE_TOKEN * 5n,
          borrower
        );

        expect(await token.balanceOf(borrower.address)).to.be.below(
          ONE_TOKEN * 5n
        );
        const loanInfo = await enterprise.getLoanInfo(tokenId);
        expect(loanInfo.maturityTime).to.be.above(loanInfoBefore.maturityTime);
        expect(loanInfo.amount).to.be.eq(loanInfoBefore.amount);
      });

      it('should be possible to return borrowed tokens', async () => {
        const balanceBefore = await token.balanceOf(borrower.address);
        await increaseTime(ONE_DAY);

        await enterprise.connect(borrower).returnLoan(tokenId);

        expect(await powerToken.balanceOf(borrower.address)).to.eq(0);
        expect(await token.balanceOf(borrower.address)).to.be.above(
          balanceBefore
        );
        expect(await token.balanceOf(enterprise.address)).to.be.above(
          LIQUIDITY
        );
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
      usdc = await new ERC20Mock__factory(deployer).deploy(
        'USDC',
        'USDC',
        USDC_DECIMALS,
        ONE_USDC * 1_000_000n
      );
      converter = await new MockConverter__factory(deployer).deploy();
      enterprise = await deployEnterprise(
        'Test',
        token.address,
        converter.address
      );
      await enterprise.enablePaymentToken(usdc.address);

      await token.transfer(converter.address, ONE_TOKEN * 10000n);
      await usdc.transfer(converter.address, ONE_USDC * 10000n);

      await addLiquidity(enterprise, ONE_TOKEN * 100000n);

      await converter.setRate(usdc.address, token.address, 350_000n); // 0.35 cents
    });

    describe('service base price in liquidity tokens', () => {
      beforeEach(async () => {
        powerToken = await registerService(
          enterprise,
          GAP_HALVING_PERIOD,
          BASE_RATE,
          token.address,
          300, // 3%
          ONE_HOUR * 12,
          ONE_DAY * 60,
          0,
          true
        );
      });
      it('should be possible to borrow paying with USDC', async () => {
        const enterpriseBalance = await token.balanceOf(enterprise.address);
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);

        const loan = estimateLoan(
          basePrice(100, ONE_DAY, 3),
          100000,
          0,
          10000,
          ONE_DAY
        );

        await borrow(
          enterprise,
          powerToken,
          usdc,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          usdcBalance,
          user
        );

        expect(await powerToken.balanceOf(user.address)).to.eq(
          ONE_TOKEN * 10000n
        );
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(
          toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)
        ).to.closeTo(loan * 0.35, 0.1);
        expect(await token.balanceOf(enterprise.address)).to.be.above(
          enterpriseBalance
        );
      });

      it('should be possible to reborrow paying with USDC', async () => {
        const enterpriseBalance = await token.balanceOf(enterprise.address);
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        await token.transfer(user.address, ONE_TOKEN * 1000n);
        const tokenBalance = await token.balanceOf(user.address);
        const loan = estimateLoan(
          basePrice(100, ONE_DAY, 3),
          100000,
          0,
          10000,
          ONE_DAY
        );
        const borrowTx = await borrow(
          enterprise,
          powerToken,
          token,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          tokenBalance,
          user
        );
        const borrowTokenId = await getBorrowTokenId(enterprise, borrowTx);
        await increaseTime(ONE_DAY);
        const enterpriseBalance2 = await token.balanceOf(enterprise.address);

        await reborrow(
          enterprise,
          borrowTokenId,
          usdc,
          ONE_DAY,
          usdcBalance,
          user
        );

        expect(await powerToken.balanceOf(user.address)).to.eq(
          ONE_TOKEN * 10000n
        );
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(
          toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)
        ).to.closeTo(loan * 0.35, 0.1);
        const enterpriseBalanceAfter = await token.balanceOf(
          enterprise.address
        );
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
          baseRate(
            100n * ONE_TOKEN,
            BigInt(ONE_DAY),
            (ONE_USDC * 3n) / 2n,
            18n,
            BigInt(USDC_DECIMALS)
          ), // 1.5 USDC for 100 tokens per day
          usdc.address,
          300, // 3%
          ONE_HOUR * 12,
          ONE_DAY * 60,
          0,
          true
        );
      });
      it('should be possible to borrow paying with USDC', async () => {
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        const enterpriseBalance = await token.balanceOf(enterprise.address);

        const loan = estimateLoan(
          basePrice(100, ONE_DAY, 1.5),
          100000,
          0,
          10000,
          ONE_DAY
        );

        await borrow(
          enterprise,
          powerToken,
          usdc,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          usdcBalance,
          user
        );

        expect(await powerToken.balanceOf(user.address)).to.eq(
          ONE_TOKEN * 10000n
        );
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(
          toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)
        ).to.closeTo(loan, 0.001);
        expect(await token.balanceOf(enterprise.address)).to.be.above(
          enterpriseBalance
        );
      });

      it('should be possible to reborrow paying with USDC', async () => {
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        await token.transfer(user.address, ONE_TOKEN * 1000n);
        const tokenBalance = await token.balanceOf(user.address);
        const enterpriseBalance = await token.balanceOf(enterprise.address);
        const loan = estimateLoan(
          basePrice(100.0, ONE_DAY, 1.5),
          100000.0,
          0,
          10000.0,
          ONE_DAY
        );
        const borrowTx = await borrow(
          enterprise,
          powerToken,
          token,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          tokenBalance,
          user
        );
        const borrowTokenId = await getBorrowTokenId(enterprise, borrowTx);
        await increaseTime(ONE_DAY);

        const enterpriseBalance2 = await token.balanceOf(enterprise.address);
        await reborrow(
          enterprise,
          borrowTokenId,
          usdc,
          ONE_DAY,
          usdcBalance,
          user
        );

        expect(await powerToken.balanceOf(user.address)).to.eq(
          ONE_TOKEN * 10000n
        );
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(
          toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)
        ).to.closeTo(loan, 0.01);
        const enterpriseBalanceAfter = await token.balanceOf(
          enterprise.address
        );
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance2);
        expect(enterpriseBalance2).to.be.above(enterpriseBalance);
      });

      it('should be possible to borrow paying with liquidity tokens', async () => {
        const enterpriseBalance = await token.balanceOf(enterprise.address);
        const tokenBalance = ONE_TOKEN * 1000n;
        await token.transfer(user.address, tokenBalance);
        const loan = estimateLoan(
          basePrice(100, ONE_DAY, 1.5),
          100000,
          0,
          10000,
          ONE_DAY
        );
        const convertedLoan = await converter.estimateConvert(
          usdc.address,
          fromTokens(loan, 6, USDC_DECIMALS),
          token.address
        );

        await borrow(
          enterprise,
          powerToken,
          token,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          tokenBalance,
          user
        );

        expect(await powerToken.balanceOf(user.address)).to.eq(
          ONE_TOKEN * 10000n
        );
        const balanceAfter = await token.balanceOf(user.address);
        expect(
          toTokens(tokenBalance - balanceAfter.toBigInt(), 3, 18)
        ).to.closeTo(toTokens(convertedLoan, 3), 0.001);
        expect(await token.balanceOf(enterprise.address)).to.be.above(
          enterpriseBalance
        );
      });

      it('should be possible to reborrow paying with liquidity tokens', async () => {
        const enterpriseBalance = await token.balanceOf(enterprise.address);
        const tokenBalance = ONE_TOKEN * 1000n;
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        await token.transfer(user.address, tokenBalance);
        const loan = estimateLoan(
          basePrice(100, ONE_DAY, 1.5),
          100000,
          0,
          10000,
          ONE_DAY
        );
        const convertedLoan = await converter.estimateConvert(
          usdc.address,
          fromTokens(loan, 6, USDC_DECIMALS),
          token.address
        );
        const borrowTx = await borrow(
          enterprise,
          powerToken,
          usdc,
          ONE_TOKEN * 10000n,
          ONE_DAY,
          usdcBalance,
          user
        );
        const borrowTokenId = await getBorrowTokenId(enterprise, borrowTx);
        await increaseTime(ONE_DAY);
        const enterpriseBalance2 = await token.balanceOf(enterprise.address);

        await reborrow(
          enterprise,
          borrowTokenId,
          token,
          ONE_DAY,
          tokenBalance,
          user
        );

        expect(await powerToken.balanceOf(user.address)).to.eq(
          ONE_TOKEN * 10000n
        );
        const balanceAfter = await token.balanceOf(user.address);
        expect(
          toTokens(tokenBalance - balanceAfter.toBigInt(), 3, 18)
        ).to.closeTo(toTokens(convertedLoan, 3), 0.01);
        const enterpriseBalanceAfter = await token.balanceOf(
          enterprise.address
        );
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance);
        expect(enterpriseBalanceAfter).to.be.above(enterpriseBalance2);
        expect(enterpriseBalance2).to.be.above(enterpriseBalance);
      });
    });
  });

  describe('withdraw interest', () => {
    let powerToken: PowerToken;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);
      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        baseRate(100n * ONE_TOKEN, BigInt(ONE_DAY), ONE_TOKEN * 3n),
        token.address,
        0, // 0%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        0,
        true
      );
      await token.transfer(lender.address, ONE_TOKEN * 10_000n);
      await token.transfer(borrower.address, ONE_TOKEN * 1_000n);
    });

    it('should be possible to withdraw interest', async () => {
      const tokenId = await addLiquidity(
        enterprise,
        ONE_TOKEN * 10_000n,
        lender
      );
      const loanCost = await enterprise.estimateLoan(
        powerToken.address,
        token.address,
        ONE_TOKEN * 1_000n,
        ONE_DAY * 15
      );
      await borrow(
        enterprise,
        powerToken,
        token,
        ONE_TOKEN * 1_000n,
        ONE_DAY * 15,
        ONE_TOKEN * 1_000n,
        borrower
      );
      await increaseTime(ONE_DAY * 365);
      const [, , totalSharesBefore] = await enterprise.getInfo();
      const liquidityInfoBefore = await enterprise.getLiquidityInfo(tokenId);
      const balanceBefore = await token.balanceOf(lender.address);
      const reservesBefore = await enterprise.getReserve();

      await enterprise.connect(lender).withdrawInterest(tokenId);

      const liquidityInfoAfter = await enterprise.getLiquidityInfo(tokenId);
      const balanceAfter = await token.balanceOf(lender.address);

      expect(toTokens(loanCost, 5)).to.approximately(
        toTokens(balanceAfter.sub(balanceBefore).toBigInt(), 5),
        0.00001
      );
      const shares = totalSharesBefore
        .mul(liquidityInfoBefore.amount)
        .div(reservesBefore);
      expect(liquidityInfoAfter.shares).to.eq(shares);
    });
  });

  describe('multi borrow scenario', () => {
    let powerToken: PowerToken;
    let interestRateGapHalvingPeriod: number;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);
      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        baseRate(1000n * ONE_TOKEN, BigInt(ONE_DAY), ONE_TOKEN * 3n),
        token.address,
        0, // 0%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        0,
        true
      );
      await token.transfer(borrower.address, ONE_TOKEN * 1000n);

      interestRateGapHalvingPeriod =
        await enterprise.getInterestGapHalvingPeriod();
    });

    it('scenario', async () => {
      const tokenId1 = await addLiquidity(enterprise, ONE_TOKEN * 10_000n);

      expect(await enterprise.getAccruedInterest(tokenId1)).to.eq(0);

      await increaseTime(ONE_DAY / 2);

      expect(await enterprise.getAccruedInterest(tokenId1)).to.eq(0);

      const borrowerBalance1 = await token.balanceOf(borrower.address);
      await expect(
        borrow(
          enterprise,
          powerToken,
          token,
          ONE_TOKEN * 1_000n,
          ONE_DAY * 30,
          ONE_TOKEN * 50n,
          borrower
        )
      ).to.be.revertedWith(Errors.E_LOAN_COST_SLIPPAGE); // 50 tokens is not enough

      const borrowTx1 = await borrow(
        enterprise,
        powerToken,
        token,
        ONE_TOKEN * 1_000n,
        ONE_DAY * 30,
        ONE_TOKEN * 800n,
        borrower
      );
      await expect(borrowTx1).to.emit(enterprise, 'Borrowed');
      const borrowReceipt = await borrowTx1.wait();

      const borrowBlock = await ethers.provider.getBlock(
        borrowReceipt.blockNumber
      );
      const borrowTimestamp = borrowBlock.timestamp;

      const borrower1Paid = borrowerBalance1.sub(
        await token.balanceOf(borrower.address)
      );

      const borrowTokenId1 = await getBorrowTokenId(enterprise, borrowTx1);

      await nextBlock(borrowTimestamp + interestRateGapHalvingPeriod);

      expect(
        toTokens(await enterprise.getAccruedInterest(tokenId1), 3)
      ).to.approximately(toTokens(borrower1Paid.div(2), 3), 0.001);

      await token.approve(enterprise.address, ONE_TOKEN * 2_000n);
      await expect(enterprise.removeLiquidity(tokenId1)).to.be.revertedWith(
        Errors.E_INSUFFICIENT_LIQUIDITY
      );

      await setNextBlockTimestamp(
        borrowTimestamp + interestRateGapHalvingPeriod * 2
      );
      const liquidityTx = await enterprise.addLiquidity(ONE_TOKEN * 2_000n);
      const tokenId2 = await getInterestTokenId(enterprise, liquidityTx);

      expect(
        toTokens(await enterprise.getAccruedInterest(tokenId1), 3)
      ).to.approximately(toTokens(borrower1Paid.mul(3).div(4), 3), 0.001);

      expect(await enterprise.getAccruedInterest(tokenId2)).to.eq(0);

      await nextBlock(borrowTimestamp + interestRateGapHalvingPeriod * 3);

      const [L1, L2] = await Promise.all([
        enterprise.getLiquidityInfo(tokenId1),
        enterprise.getLiquidityInfo(tokenId2),
      ]);

      const LP2interest = borrower1Paid
        .mul(L2.shares)
        .div(L1.shares.add(L2.shares).mul(8));

      expect(
        toTokens(await enterprise.getAccruedInterest(tokenId2), 3)
      ).to.approximately(toTokens(LP2interest, 3), 0.001);

      await increaseTime(ONE_DAY * 5);

      await expect(enterprise.removeLiquidity(tokenId1)).to.emit(
        enterprise,
        'LiquidityChanged'
      );
      await expect(enterprise.removeLiquidity(tokenId2)).to.be.revertedWith(
        Errors.E_INSUFFICIENT_LIQUIDITY
      );
      await expect(
        enterprise.decreaseLiquidity(tokenId2, ONE_TOKEN * 10n)
      ).to.emit(enterprise, 'LiquidityChanged');

      const loanInfo2 = await enterprise.getLiquidityInfo(tokenId2);
      expect(loanInfo2.amount).to.eq(ONE_TOKEN * 1_990n);

      await expect(
        enterprise.connect(stranger).returnLoan(borrowTokenId1)
      ).to.be.revertedWith(
        Errors.E_INVALID_CALLER_WITHIN_BORROWER_GRACE_PERIOD
      );

      await increaseTime(ONE_DAY * 4.5); // because of 12 hours of borrower and enterprise grace period

      await expect(enterprise.removeLiquidity(tokenId2)).to.be.revertedWith(
        Errors.E_INSUFFICIENT_LIQUIDITY
      );
      await expect(
        enterprise.connect(stranger).returnLoan(borrowTokenId1)
      ).to.be.revertedWith(
        Errors.E_INVALID_CALLER_WITHIN_ENTERPRISE_GRACE_PERIOD
      ); // still cannot return loan

      await increaseTime(ONE_DAY);

      await expect(
        enterprise.connect(stranger).returnLoan(borrowTokenId1)
      ).to.emit(enterprise, 'LoanReturned');

      await expect(
        enterprise.connect(borrower).returnLoan(borrowTokenId1)
      ).to.be.revertedWith(Errors.E_INVALID_LOAN_TOKEN_ID);

      await enterprise.decreaseLiquidity(tokenId2, ONE_TOKEN * 1_990n);

      expect(await enterprise.getAccruedInterest(tokenId2))
        .to.eq(await enterprise.getAvailableReserve())
        .to.eq(await enterprise.getReserve());

      await token.approve(enterprise.address, ONE_TOKEN * 2_000n);
      await expect(
        enterprise.increaseLiquidity(tokenId2, ONE_TOKEN * 2_000n)
      ).to.emit(enterprise, 'LiquidityChanged');

      const loanInfo3 = await enterprise.getLiquidityInfo(tokenId2);
      expect(loanInfo3.amount).to.eq(ONE_TOKEN * 2_000n);

      const interest = await enterprise.getAccruedInterest(tokenId2);

      expect(await enterprise.getReserve()).to.eq(
        interest.add(ONE_TOKEN * 2000n)
      );
    });
  });

  describe('Enterprise upgradability', () => {
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);
    });

    it('should be possible upgrade Enterprise', async () => {
      const Enterprise = await ethers.getContractFactory('Enterprise');
      const enterpriseImpl = await Enterprise.deploy();

      await enterprise.upgrade(
        enterpriseImpl.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        []
      );

      expect(await getProxyImplementation(enterprise, enterprise)).eq(
        enterpriseImpl.address
      );
    });

    it('should be possible upgrade PowerToken', async () => {
      const powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        token.address,
        0,
        0,
        0,
        0,
        true
      );

      const PowerToken = await ethers.getContractFactory('PowerToken');
      const powerTokenImpl = await PowerToken.deploy();

      await enterprise.upgrade(
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        powerTokenImpl.address,
        [powerToken.address]
      );

      expect(await getProxyImplementation(enterprise, powerToken)).eq(
        powerTokenImpl.address
      );
    });

    it('should be possible to upgrade BorrowToken', async () => {
      const BorrowToken = await ethers.getContractFactory('BorrowToken');
      const borrowToken = BorrowToken.attach(await enterprise.getBorrowToken());
      const borrowTokenImpl = await BorrowToken.deploy();

      await enterprise.upgrade(
        ethers.constants.AddressZero,
        borrowTokenImpl.address,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        []
      );

      expect(await getProxyImplementation(enterprise, borrowToken)).eq(
        borrowTokenImpl.address
      );
    });

    it('should be possible to upgrade InterestToken', async () => {
      const InterestToken = await ethers.getContractFactory('InterestToken');
      const interestToken = InterestToken.attach(
        await enterprise.getInterestToken()
      );
      const interestTokenImpl = await InterestToken.deploy();

      await enterprise.upgrade(
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        interestTokenImpl.address,
        ethers.constants.AddressZero,
        []
      );

      expect(await getProxyImplementation(enterprise, interestToken)).eq(
        interestTokenImpl.address
      );
    });
  });

  describe('After enterprise shutdown', () => {
    let powerToken: PowerToken;
    let tokenId: BigNumber;
    let borrowId: BigNumber;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);
      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        token.address,
        0,
        0,
        ONE_DAY * 365,
        0,
        true
      );
      tokenId = await addLiquidity(enterprise, ONE_TOKEN * 10_000n);
      await token.transfer(borrower.address, ONE_TOKEN * 1000n);
      const borrowTx = await borrow(
        enterprise,
        powerToken,
        token,
        ONE_TOKEN * 500n,
        ONE_DAY,
        ONE_TOKEN * 1000n,
        borrower
      );

      borrowId = await getBorrowTokenId(enterprise, borrowTx);

      await enterprise.shutdownEnterpriseForever();
    });

    it('should not be possible to add liquidity', async () => {
      await expect(addLiquidity(enterprise, ONE_TOKEN)).to.be.reverted;
    });

    it('should not be possible to increase liquidity', async () => {
      await expect(enterprise.increaseLiquidity(tokenId, ONE_TOKEN)).to.be
        .reverted;
    });

    it('should not be possible to borrow', async () => {
      await expect(
        borrow(
          enterprise,
          powerToken,
          token,
          ONE_TOKEN * 500n,
          ONE_DAY,
          ONE_TOKEN * 1000n,
          borrower
        )
      ).to.be.reverted;
    });

    it('should to be possible to reborrow', async () => {
      await expect(
        enterprise.reborrow(
          borrowId,
          token.address,
          ONE_DAY,
          ONE_TOKEN * 1_000n
        )
      ).to.be.reverted;
    });

    it('should be possible to remove liquidity without returning loan', async () => {
      await enterprise.removeLiquidity(tokenId);
    });

    it('should be possible to return loan', async () => {
      await enterprise.connect(borrower).returnLoan(borrowId);
    });

    it('should be possible to decrease liquidity', async () => {
      await enterprise.decreaseLiquidity(tokenId, ONE_TOKEN);
    });

    it('should be possible to withdraw interest', async () => {
      await enterprise.withdrawInterest(tokenId);
    });
  });

  describe('PowerToken transfer', () => {
    let powerToken: PowerToken;
    let borrowToken: BorrowToken;
    let borrowId: BigNumber;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);

      borrowToken = await getBorrowToken(enterprise);

      powerToken = await registerService(
        enterprise,
        GAP_HALVING_PERIOD,
        BASE_RATE,
        token.address,
        300, // 3%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        ONE_TOKEN,
        true
      );

      await token.transfer(borrower.address, ONE_TOKEN * 1_000n);

      await addLiquidity(enterprise, ONE_TOKEN * 10_000n);
      const borrowTx = await borrow(
        enterprise,
        powerToken,
        token,
        ONE_TOKEN * 100n,
        ONE_DAY,
        ONE_TOKEN * 100n,
        borrower
      );
      borrowId = await getBorrowTokenId(enterprise, borrowTx);
    });

    it('should not be possible to move borrow tokens by default', async () => {
      await expect(
        borrowToken
          .connect(borrower)
          .transferFrom(borrower.address, stranger.address, borrowId)
      ).to.be.revertedWith(Errors.BT_TRANSFER_NOT_ALLOWED);
    });

    it('should not be possible to move borrowed PowerToken directly', async () => {
      expect(await powerToken.balanceOf(borrower.address)).to.eq(
        ONE_TOKEN * 100n
      );
      await expect(
        powerToken
          .connect(borrower)
          .transfer(stranger.address, ONE_TOKEN * 100n)
      ).to.be.revertedWith(Errors.PT_INSUFFICIENT_AVAILABLE_BALANCE);
    });

    it('should be possible to move borrowed PowerToken by moving BorrowToken', async () => {
      await borrowToken.enableTransfersForever();

      await borrowToken
        .connect(borrower)
        .transferFrom(borrower.address, stranger.address, borrowId);

      expect(await powerToken.balanceOf(borrower.address)).to.eq(0);
      expect(await powerToken.balanceOf(stranger.address)).to.eq(
        ONE_TOKEN * 100n
      );
    });

    it('should not be possible to move expired borrowed PowerToken', async () => {
      await borrowToken.enableTransfersForever();

      await increaseTime(ONE_DAY * 2);

      await expect(
        borrowToken
          .connect(borrower)
          .transferFrom(borrower.address, stranger.address, borrowId)
      ).to.be.revertedWith(Errors.E_LOAN_TRANSFER_NOT_ALLOWED);
    });
  });
});
