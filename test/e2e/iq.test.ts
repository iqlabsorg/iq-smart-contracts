import {ethers, waffle} from 'hardhat';
import chai from 'chai';
chai.use(waffle.solidity);
const {expect} = chai;

import {
  baseRate,
  deployEnterprise,
  getEnterprise,
  getInterestTokenId,
  getPowerToken,
  getTokenId,
  increaseTime,
  toTokens,
} from '../utils';
import {Address} from 'hardhat-deploy/types';
import {
  Enterprise,
  EnterpriseFactory,
  IConverter,
  IERC20Metadata,
  IEstimator,
  InterestToken,
  PowerToken,
} from '../../typechain';
import {BigNumber, Wallet} from 'ethers';

describe('IQ Protocol E2E', () => {
  let deployer: Wallet;
  let user: Wallet;
  let token: IERC20Metadata;
  let enterprise: Enterprise;

  const ONE_TOKEN = 10n ** 18n;

  beforeEach(async () => {
    [deployer, user] = await waffle.provider.getWallets();
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
        ethers.utils.parseUnits('1', 18), // 1 token
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

    it('should perform actions', async () => {
      await token.connect(user).approve(enterprise.address, MAX_PAYMENT_AMOUNT);

      const userEnterprise = (await ethers.getContractAt(
        'Enterprise',
        enterprise.address,
        user
      )) as Enterprise;

      const loanCost = await userEnterprise.estimateLoan(
        powerToken.address,
        token.address,
        BORROW_AMOUNT,
        86400
      );
      console.log('Estimated', toTokens(loanCost));

      // 4. Borrow
      const borrowTx = await userEnterprise.borrow(
        powerToken.address,
        token.address,
        BORROW_AMOUNT,
        MAX_PAYMENT_AMOUNT,
        86400
      );

      await increaseTime(86400);

      // 5. Burn
      const tokenId = await getTokenId(userEnterprise, borrowTx);
      await userEnterprise.returnLoan(tokenId);

      await enterprise.removeLiquidity(liquidityTokenId);
    });

    it('should be possible to take 2 loans', async () => {
      const BORROW1 = ONE_TOKEN * 300000n;
      const BORROW2 = ONE_TOKEN * 200000n;

      const userToken = await ethers.getContract('ERC20Mock', user);
      await userToken.approve(enterprise.address, MAX_PAYMENT_AMOUNT);

      const userEnterprise = (await ethers.getContractAt(
        'Enterprise',
        enterprise.address,
        user
      )) as Enterprise;

      const balanceBefore = await token.balanceOf(user.address);
      console.log(
        'Available Reserve --> ',
        toTokens(await userEnterprise.getAvailableReserve(), 4)
      );

      console.log(
        'Loan --> ',
        toTokens(
          await userEnterprise.estimateLoan(
            powerToken.address,
            token.address,
            BORROW1,
            86400
          ),
          4
        )
      );

      const borrow1Tx = await userEnterprise.borrow(
        powerToken.address,
        token.address,
        BORROW1,
        MAX_PAYMENT_AMOUNT,
        86400
      );
      const balanceAfter1 = await token.balanceOf(user.address);
      await increaseTime(3600 * 4);
      console.log(
        'Available Reserve --> ',
        toTokens(await userEnterprise.getAvailableReserve(), 4)
      );

      console.log(
        'Loan 2 --> ',
        toTokens(
          await userEnterprise.estimateLoan(
            powerToken.address,
            token.address,
            BORROW2,
            86400
          ),
          4
        )
      );
      const borrow2Tx = await userEnterprise.borrow(
        powerToken.address,
        token.address,
        BORROW2,
        MAX_PAYMENT_AMOUNT,
        86400
      );
      const balanceAfter2 = await token.balanceOf(user.address);

      console.log(
        toTokens(balanceBefore.sub(balanceAfter1), 15),
        toTokens(balanceAfter1.sub(balanceAfter2), 15),
        'Total',
        toTokens(balanceBefore.sub(balanceAfter2), 15)
      );
    });
  });
});
