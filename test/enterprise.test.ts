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
  MockConverter__factory,
  PowerToken,
} from '../typechain';
import {
  basePrice,
  baseRate,
  deployEnterprise,
  estimateLoan,
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
  const BASE_RATE = baseRate(100n, 86400n, 3n);

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

        await enterprise.connect(user).wrap(powerToken.address, ONE_TOKEN);
      });
      it('should be possible to wrap liquidty tokens', async () => {
        expect(await powerToken.balanceOf(user.address)).to.eq(ONE_TOKEN);
        expect(await token.balanceOf(powerToken.address)).to.eq(ONE_TOKEN);
        expect(await token.balanceOf(user.address)).to.eq(0);
      });

      it('should be possible to unwrap liquidty tokens', async () => {
        await enterprise.connect(user).unwrap(powerToken.address, ONE_TOKEN);

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

        await enterprise
          .connect(stranger)
          .unwrap(powerToken.address, ONE_TOKEN);

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
        await token.connect(lender).approve(enterprise.address, LIQIDITY);
        await enterprise.connect(lender).addLiquidity(LIQIDITY);
        await token
          .connect(borrower)
          .approve(enterprise.address, ONE_TOKEN * 5n);
        const borrowTx = await enterprise
          .connect(borrower)
          .borrow(
            powerToken.address,
            token.address,
            BORROW_AMOUNT,
            ONE_TOKEN * 5n,
            ONE_DAY
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
          .reborrow(tokenId, token.address, ONE_TOKEN * 5n, ONE_DAY);

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
    beforeEach(async () => {
      usdc = await new ERC20Mock__factory(deployer).deploy(
        'USDC',
        'USDC',
        USDC_DECIMALS,
        ONE_TOKEN * 1_000_000n
      );
      const converter = await new MockConverter__factory(deployer).deploy();
      enterprise = await deployEnterprise(
        'Test',
        token.address,
        converter.address
      );
      await enterprise.enablePaymentToken(usdc.address);

      await token.transfer(converter.address, ONE_TOKEN * 10000n);
      await usdc.transfer(converter.address, ONE_USDC * 10000n);

      await token.approve(enterprise.address, ONE_TOKEN * 100000n);
      await enterprise.addLiquidity(ONE_TOKEN * 100000n);

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
        await usdc.connect(user).approve(enterprise.address, usdcBalance);

        await enterprise
          .connect(user)
          .borrow(
            powerToken.address,
            usdc.address,
            ONE_TOKEN * 10000n,
            usdcBalance,
            ONE_DAY
          );

        const loan = estimateLoan(
          basePrice(100, ONE_DAY, 3),
          100000,
          0,
          10000,
          ONE_DAY
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
          baseRate(100n * ONE_TOKEN, BigInt(ONE_DAY), (ONE_USDC * 3n) / 2n), // 1.5 USDC for 100 tokens per day
          usdc.address,
          300, // 3%
          ONE_HOUR * 12,
          ONE_DAY * 60,
          0,
          true
        );
      });
      it.skip('should be possible to borrow paying with USDC', async () => {
        const usdcBalance = ONE_USDC * 1000n;
        await usdc.transfer(user.address, usdcBalance);
        await usdc.connect(user).approve(enterprise.address, usdcBalance);

        await enterprise
          .connect(user)
          .borrow(
            powerToken.address,
            usdc.address,
            ONE_TOKEN * 10000n,
            usdcBalance,
            ONE_DAY
          );

        const loan = estimateLoan(
          basePrice(100, ONE_DAY, 1.5),
          100000,
          0,
          10000,
          ONE_DAY
        );

        expect(await powerToken.balanceOf(user.address)).to.eq(
          ONE_TOKEN * 10000n
        );
        const balanceAfter = await usdc.balanceOf(user.address);
        expect(
          toTokens(usdcBalance - balanceAfter.toBigInt(), 3, USDC_DECIMALS)
        ).to.closeTo(loan, 0.1);
      });
    });
  });
});
