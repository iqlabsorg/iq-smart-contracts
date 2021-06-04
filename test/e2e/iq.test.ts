import {ethers, waffle} from 'hardhat';
import chai from 'chai';
chai.use(waffle.solidity);
const {expect} = chai;

import {
  basePrice,
  baseRate,
  deployEnterprise,
  estimateLoan,
  getInterestTokenId,
  getPowerToken,
  getTokenId,
  increaseTime,
  toTokens,
} from '../utils';
import {
  Enterprise,
  IERC20Metadata,
  InterestToken,
  PowerToken,
} from '../../typechain';
import {BigNumber, Wallet} from 'ethers';

describe('IQ Protocol E2E', () => {
  let user: Wallet;
  let token: IERC20Metadata;
  let enterprise: Enterprise;

  const ONE_TOKEN = 10n ** 18n;

  beforeEach(async () => {
    [, user] = await waffle.provider.getWallets();
    token = (await ethers.getContract('ERC20Mock')) as IERC20Metadata;
    enterprise = await deployEnterprise('Testing', token.address);
  });

  describe('Basic', () => {
    it('should set liquidity token', async () => {
      expect(await enterprise.getLiquidityToken()).to.equal(token.address);
    });
    it('should deploy interest token', async () => {
      expect(await enterprise.getInterestToken()).not.to.equal(
        ethers.constants.AddressZero
      );
    });

    describe('InterestToken', async () => {
      let interestToken: InterestToken;
      before(async () => {
        const token = await enterprise.getInterestToken();
        const InterestToken = await ethers.getContractFactory('InterestToken');
        interestToken = InterestToken.attach(token) as InterestToken;
      });

      it('should set InterestToken name', async () => {
        const symbol = await token.symbol();
        expect(await interestToken.name()).to.equal(
          `Interest Bearing ${symbol}`
        );
      });

      it('should set InterestToken symbol', async () => {
        const symbol = await token.symbol();
        expect(await interestToken.symbol()).to.equal(`i${symbol}`);
      });
    });
  });

  const HALF_LIFE = 86400;
  const BASE_RATE = baseRate(100n, 86400n, 3n);
  describe('Service', () => {
    it('should register service', async () => {
      const txPromise = enterprise.registerService(
        'IQ Power Test',
        'IQPT',
        HALF_LIFE,
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
      expect(await enterprise.getServiceHalfLife(powerToken.address)).to.equal(
        HALF_LIFE
      );
    });
  });

  describe('Lend-Borrow-Return-Withdraw', () => {
    const LEND_AMOUNT = ONE_TOKEN * 1000000n;
    const BORROW_AMOUNT = ONE_TOKEN * 50n;
    const MAX_PAYMENT_AMOUNT = ONE_TOKEN * 5000000n;
    let powerToken: PowerToken;
    let liquidityTokenId: BigNumber;

    beforeEach(async () => {
      // 2.Create service
      const tx = await enterprise.registerService(
        'IQ Power Test',
        'IQPT',
        HALF_LIFE,
        BASE_RATE,
        token.address,
        300, // 3%
        43200, // 12 hours
        86400 * 60, // 2 months
        0,
        true
      );
      powerToken = await getPowerToken(enterprise, tx);

      // 2.1 Approve
      await token.approve(enterprise.address, LEND_AMOUNT);
      // 3. Lend
      const liquidityTx = await enterprise.addLiquidity(LEND_AMOUNT);
      liquidityTokenId = await getInterestTokenId(enterprise, liquidityTx);
      await token.transfer(user.address, MAX_PAYMENT_AMOUNT);
    });

    it('should borrow-return-remove liquidity', async () => {
      await token.connect(user).approve(enterprise.address, MAX_PAYMENT_AMOUNT);

      // 4. Borrow
      const borrowTx = await enterprise
        .connect(user)
        .borrow(
          powerToken.address,
          token.address,
          BORROW_AMOUNT,
          MAX_PAYMENT_AMOUNT,
          86400
        );

      await increaseTime(86400);

      // 5. Burn
      const tokenId = await getTokenId(enterprise, borrowTx);
      await enterprise.connect(user).returnLoan(tokenId);

      await enterprise.removeLiquidity(liquidityTokenId);
    });

    it('2 sequential borrow approximately costs the same as 1 for accumulated amount for the same period (additivity)', async () => {
      const ONE_SHOT_BORROW_COST = estimateLoan(
        basePrice(100.0, 86400.0, 3.0),
        1000000.0,
        0.0,
        500000.0,
        86400.0
      );
      const BORROW1 = ONE_TOKEN * 300000n;
      const BORROW2 = ONE_TOKEN * 200000n;

      await token.connect(user).approve(enterprise.address, MAX_PAYMENT_AMOUNT);

      const balanceBefore = await token.balanceOf(user.address);
      await enterprise
        .connect(user)
        .borrow(
          powerToken.address,
          token.address,
          BORROW1,
          MAX_PAYMENT_AMOUNT,
          86400
        );
      await enterprise
        .connect(user)
        .borrow(
          powerToken.address,
          token.address,
          BORROW2,
          MAX_PAYMENT_AMOUNT,
          86400
        );
      const balanceAfter = await token.balanceOf(user.address);

      const diff = balanceBefore.toBigInt() - balanceAfter.toBigInt();

      expect(toTokens(diff, 8)).to.be.approximately(ONE_SHOT_BORROW_COST, 0.1);
    });
  });
});
