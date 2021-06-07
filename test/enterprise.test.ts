import {ethers, waffle} from 'hardhat';
import chai from 'chai';
chai.use(waffle.solidity);
const {expect} = chai;

import {
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
  getInterestTokenId,
  getTokenId,
  increaseTime,
  ONE_DAY,
  ONE_HOUR,
  registerService,
  toTokens,
} from './utils';
import {Wallet} from '@ethersproject/wallet';
import {BigNumber} from 'ethers';

describe('Enterprise', () => {
  let deployer: Wallet;
  let lender: Wallet;
  let borrower: Wallet;
  let user: Wallet;
  let stranger: Wallet;
  let enterprise: Enterprise;
  let token: IERC20Metadata;
  const ONE_TOKEN = 10n ** 18n;
  const HALF_LIFE = ONE_DAY;
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
        HALF_LIFE,
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
        const liquidityTx = await enterprise
          .connect(lender)
          .addLiquidity(ONE_TOKEN);
        const tokenId = await getInterestTokenId(enterprise, liquidityTx);

        await enterprise.connect(lender).removeLiquidity(tokenId);

        expect(await token.balanceOf(lender.address)).to.eq(ONE_TOKEN);
        expect(await interestToken.balanceOf(lender.address)).to.eq(0);
      });

      it('should be possible to transfer interest token', async () => {
        const liquidityTx = await enterprise
          .connect(lender)
          .addLiquidity(ONE_TOKEN);
        const tokenId = await getInterestTokenId(enterprise, liquidityTx);

        await interestToken
          .connect(lender)
          .transferFrom(lender.address, stranger.address, tokenId);

        expect(await interestToken.balanceOf(lender.address)).to.eq(0);
        expect(await interestToken.balanceOf(stranger.address)).to.eq(1);
      });

      it('should be possible to remove liquidity on transfered interest token', async () => {
        const liquidityTx = await enterprise
          .connect(lender)
          .addLiquidity(ONE_TOKEN);
        const tokenId = await getInterestTokenId(enterprise, liquidityTx);
        await interestToken
          .connect(lender)
          .transferFrom(lender.address, stranger.address, tokenId);

        await enterprise.connect(stranger).removeLiquidity(tokenId);

        expect(await token.balanceOf(stranger.address)).to.eq(ONE_TOKEN);
        expect(await interestToken.balanceOf(stranger.address)).to.eq(0);
      });
    });
    describe('borrow / reborrow / return', () => {
      const LIQIDITY = ONE_TOKEN * 1000n;
      const BORROW_AMOUNT = ONE_TOKEN * 100n;
      let tokenId: BigNumber;

      beforeEach(async () => {
        await token.transfer(borrower.address, ONE_TOKEN * 5n);
        await token.transfer(lender.address, LIQIDITY);

        await addLiquidity(enterprise, LIQIDITY, lender);

        const borrowTx = await borrow(
          enterprise,
          powerToken,
          token,
          BORROW_AMOUNT,
          ONE_DAY,
          ONE_TOKEN * 5n,
          borrower
        );

        tokenId = await getTokenId(enterprise, borrowTx);
      });

      it('should be possible to borrow tokens', async () => {
        expect(await powerToken.balanceOf(borrower.address)).to.eq(
          BORROW_AMOUNT
        );
        expect(await token.balanceOf(borrower.address)).to.be.below(
          ONE_TOKEN * 5n
        );
        expect(await token.balanceOf(enterprise.address)).to.be.above(LIQIDITY);
      });

      it('should be possible to reborrow tokens', async () => {
        await token.transfer(borrower.address, ONE_TOKEN * 5n);
        await token
          .connect(borrower)
          .approve(enterprise.address, ONE_TOKEN * 5n);
        const loanInfoBefore = await enterprise.getLoanInfo(tokenId);
        await increaseTime(ONE_DAY);

        await enterprise
          .connect(borrower)
          .reborrow(tokenId, token.address, ONE_DAY, ONE_TOKEN * 5n);

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
        expect(await token.balanceOf(enterprise.address)).to.be.above(LIQIDITY);
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
          HALF_LIFE,
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
      });
    });

    describe('service base price in USDC', () => {
      beforeEach(async () => {
        powerToken = await registerService(
          enterprise,
          HALF_LIFE,
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
      });

      it('should be possible to borrow paying with liquidity tokens', async () => {
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
      });
    });
  });

  describe('multi borrow scenario', () => {
    let powerToken: IPowerToken;
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);
      powerToken = await registerService(
        enterprise,
        HALF_LIFE,
        baseRate(100n * ONE_TOKEN, BigInt(ONE_DAY), ONE_TOKEN * 3n),
        token.address,
        0, // 0%
        ONE_HOUR * 12,
        ONE_DAY * 60,
        0,
        true
      );
      await token.transfer(borrower.address, ONE_TOKEN * 1000n);
    });

    it('add-borrow-add-borrow-return-return-remove', async () => {
      const liquidityTx1 = await addLiquidity(enterprise, ONE_TOKEN * 10_000n);
      const tokenId1 = await getInterestTokenId(enterprise, liquidityTx1);

      expect(await enterprise.getOwedInterest(tokenId1)).to.eq(0);

      await increaseTime(ONE_DAY / 2);

      expect(await enterprise.getOwedInterest(tokenId1)).to.eq(0);

      const borrowerBalance1 = await token.balanceOf(borrower.address);
      await expect(
        borrow(
          enterprise,
          powerToken,
          token,
          ONE_TOKEN * 1_000n,
          ONE_DAY * 10,
          ONE_TOKEN * 300n,
          borrower
        )
      ).to.be.revertedWith('47'); // 300 tokens is not enough

      const borrowTx1 = await borrow(
        enterprise,
        powerToken,
        token,
        ONE_TOKEN * 1_000n,
        ONE_DAY * 10,
        ONE_TOKEN * 400n,
        borrower
      );

      const borrower1Paid = borrowerBalance1.sub(
        await token.balanceOf(borrower.address)
      );

      const borrowTokenId1 = await getTokenId(enterprise, borrowTx1);

      await increaseTime(ONE_HOUR * 4);

      expect(
        toTokens(await enterprise.getOwedInterest(tokenId1), 3)
      ).to.approximately(toTokens(borrower1Paid.div(2), 3), 0.001);

      await increaseTime(ONE_HOUR * 4);

      expect(
        toTokens(await enterprise.getOwedInterest(tokenId1), 3)
      ).to.approximately(toTokens(borrower1Paid.mul(3).div(4), 3), 0.001);

      await expect(enterprise.removeLiquidity(tokenId1)).to.be.revertedWith(
        '46'
      );

      const liquidityTx2 = await addLiquidity(enterprise, ONE_TOKEN * 1_000n);

      const tokenId2 = await getInterestTokenId(enterprise, liquidityTx2);

      expect(await enterprise.getOwedInterest(tokenId2)).to.eq(0);

      await increaseTime(ONE_HOUR * 4);

      const [L1, L2] = await Promise.all([
        enterprise.getLiquidityInfo(tokenId1),
        enterprise.getLiquidityInfo(tokenId2),
      ]);

      const LP2interest = borrower1Paid
        .div(8)
        .mul(L2.shares)
        .div(L1.shares.add(L2.shares));

      expect(
        toTokens(await enterprise.getOwedInterest(tokenId2), 3)
      ).to.approximately(toTokens(LP2interest, 3), 0.001);

      await enterprise.removeLiquidity(tokenId1);
    });
  });

  describe('Enterprise upgradabilitiy', () => {
    beforeEach(async () => {
      enterprise = await deployEnterprise('Test', token.address);
    });
  });
});
