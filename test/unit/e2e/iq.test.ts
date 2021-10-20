import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/dist/src/signers';
import chai from 'chai';
import {BigNumber} from 'ethers';
import {ethers, waffle} from 'hardhat';
import {
  Enterprise,
  IERC20Metadata,
  InterestToken,
  PowerToken,
} from '../../../typechain';
import {
  addLiquidity,
  basePrice,
  baseRate,
  borrow,
  deployEnterprise,
  estimateLoan,
  getBorrowTokenId,
  getPowerToken,
  increaseTime,
  ONE_DAY,
  toTokens,
} from '../../utils';
chai.use(waffle.solidity);
const {expect} = chai;

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
      beforeEach(async () => {
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
      expect(await powerToken.getGapHalvingPeriod()).to.equal(
        GAP_HALVING_PERIOD
      );
    });
  });

  describe('Lend-Borrow-Return-Withdraw', () => {
    const LEND_AMOUNT = ONE_TOKEN * 1_000_000n;
    const BORROW_AMOUNT = ONE_TOKEN * 50n;
    const MAX_PAYMENT_AMOUNT = ONE_TOKEN * 5_000_000n;
    let powerToken: PowerToken;
    let liquidityTokenId: BigNumber;

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

      // 3. Lend
      liquidityTokenId = await addLiquidity(enterprise, LEND_AMOUNT);

      await token.transfer(user.address, MAX_PAYMENT_AMOUNT);
    });

    it('should borrow-return-remove liquidity', async () => {
      console.log(
        'Estimate:',
        (
          await enterprise.estimateLoan(
            powerToken.address,
            token.address,
            BORROW_AMOUNT,
            ONE_DAY
          )
        ).toString()
      );

      // 4. Borrow
      const borrowTx = await borrow(
        enterprise,
        powerToken,
        token,
        BORROW_AMOUNT,
        ONE_DAY,
        MAX_PAYMENT_AMOUNT,
        user
      );
      await expect(borrowTx).to.emit(enterprise, 'Borrowed');
      await increaseTime(86400);

      // 5. Burn
      const tokenId = await getBorrowTokenId(enterprise, borrowTx);
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

      const balanceBefore = await token.balanceOf(user.address);

      await borrow(
        enterprise,
        powerToken,
        token,
        BORROW1,
        ONE_DAY,
        MAX_PAYMENT_AMOUNT,
        user
      );
      await borrow(
        enterprise,
        powerToken,
        token,
        BORROW2,
        ONE_DAY,
        MAX_PAYMENT_AMOUNT,
        user
      );

      const balanceAfter = await token.balanceOf(user.address);
      const diff = balanceBefore.toBigInt() - balanceAfter.toBigInt();
      expect(toTokens(diff, 8)).to.be.approximately(ONE_SHOT_BORROW_COST, 0.1);
    });
  });
});
