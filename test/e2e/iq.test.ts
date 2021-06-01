import {expect} from '../chai-setup';

import {config, ethers, getNamedAccounts} from 'hardhat';

import {
  getEnterprise,
  getPowerToken,
  getTokenId,
  increaseTime,
  toTokens,
} from '../utils';
import {Address} from 'hardhat-deploy/types';
import {
  Enterprise,
  IConverter,
  IERC20Metadata,
  ILoanCostEstimator,
  InterestToken,
  PowerToken,
} from '../../typechain';
import {
  EnterpriseConfigurator,
  EnterpriseConfiguratorInterface,
} from '../../typechain/EnterpriseConfigurator';

describe.only('IQ Protocol E2E', () => {
  let deployer: Address;
  let user: Address;
  let token: IERC20Metadata;
  let enterprise: Enterprise;
  let configurator: EnterpriseConfigurator;

  const ONE_TOKEN = ethers.utils.parseEther('1');
  const BORROWER_LOAN_RETURN_GRACE_PERIOD = 3600; // 1 hour
  const ENTERPRISE_LOAN_RETURN_GRACE_PERIOD = 7200; // 2 hours

  beforeEach(async () => {
    ({deployer, user} = await getNamedAccounts());

    token = (await ethers.getContract('ERC20Mock')) as IERC20Metadata;
    const estimator = (await ethers.getContract(
      'DefaultLoanCostEstimator'
    )) as ILoanCostEstimator;
    const converter = (await ethers.getContract(
      'DefaultConverter'
    )) as IConverter;

    const factory = await ethers.getContract('EnterpriseFactory');
    const tx = await factory.deploy(
      'Testing',
      token.address,
      'https://test.iq.io',
      estimator.address,
      converter.address
    );

    enterprise = await getEnterprise(factory, tx);
    configurator = (await ethers.getContractAt(
      'EnterpriseConfigurator',
      await enterprise.getConfigurator()
    )) as EnterpriseConfigurator;
  });

  describe('Basic', () => {
    it('should set liquidity token', async () => {
      expect(await configurator.getLiquidityToken()).to.equal(token.address);
    });
    it('should deploy interest token', async () => {
      expect(await configurator.getInterestToken()).not.to.equal(
        ethers.constants.AddressZero
      );
    });

    describe('InterestToken', async () => {
      let interestToken: InterestToken;
      before(async () => {
        const token = await configurator.getInterestToken();
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
  const BASE_RATE = (3n << 64n) / (100n * 86400n); // 100 tokens per day costs 3 tokens
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
        ethers.utils.parseUnits('1', 18) // 1 token
      );

      await expect(txPromise).to.emit(enterprise, 'ServiceRegistered');
      const powerToken = await getPowerToken(enterprise, await txPromise);
      expect(await configurator.getHalfLife(powerToken.address)).to.equal(
        HALF_LIFE
      );
    });
  });

  describe('Lend-Borrow-Return-Withdraw', () => {
    const LEND_AMOUNT = ONE_TOKEN.mul(1000000);
    const BORROW_AMOUNT = ONE_TOKEN.mul(50);
    const MAX_PAYMENT_AMOUNT = ONE_TOKEN.mul(5000000);
    let powerToken: PowerToken;

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
        0
      );
      powerToken = await getPowerToken(enterprise, tx);

      // 2.1 Approve
      await token.approve(enterprise.address, LEND_AMOUNT);
      // 3. Lend
      await enterprise.addLiquidity(LEND_AMOUNT);
      await token.transfer(user, MAX_PAYMENT_AMOUNT);
    });

    afterEach(async () => {
      // 6. withdraw
      console.log(
        'Balance Before withdraw: ',
        (await token.balanceOf(deployer)).toString()
      );
      await enterprise.removeLiquidity(LEND_AMOUNT);

      console.log('Balance: ', (await token.balanceOf(deployer)).toString());
    });

    it('should perform actions', async () => {
      const userToken = await ethers.getContract('ERC20Mock', user);
      await userToken.approve(enterprise.address, MAX_PAYMENT_AMOUNT);

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
    });

    it.only('should be possible to take 2 loans', async () => {
      const BORROW1 = ONE_TOKEN.mul(300000);
      const BORROW2 = ONE_TOKEN.mul(200000);

      const userToken = await ethers.getContract('ERC20Mock', user);
      await userToken.approve(enterprise.address, MAX_PAYMENT_AMOUNT);

      const userEnterprise = (await ethers.getContractAt(
        'Enterprise',
        enterprise.address,
        user
      )) as Enterprise;

      const balanceBefore = await token.balanceOf(user);

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
      const balanceAfter1 = await token.balanceOf(user);
      const borrow2Tx = await userEnterprise.borrow(
        powerToken.address,
        token.address,
        BORROW2,
        MAX_PAYMENT_AMOUNT,
        86400
      );
      const balanceAfter2 = await token.balanceOf(user);

      console.log(
        toTokens(balanceBefore.sub(balanceAfter1), 15),
        toTokens(balanceAfter1.sub(balanceAfter2), 15),
        'Total',
        toTokens(balanceBefore.sub(balanceAfter2), 15)
      );
    });
  });
});
