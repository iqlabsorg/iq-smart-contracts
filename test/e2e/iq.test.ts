import {expect} from '../chai-setup';

import {ethers, getNamedAccounts} from 'hardhat';

import {getEnterprise, getPowerToken, getTokenId, increaseTime} from '../utils';
import {Address} from 'hardhat-deploy/types';
import {Contract} from '@ethersproject/contracts';
import {Enterprise} from '../../typechain';

describe('IQ Protocol E2E', () => {
  let deployer: Address;
  let user: Address;
  let token: Contract;
  let enterprise: Enterprise;

  const ONE_TOKEN = ethers.utils.parseEther('1');

  beforeEach(async () => {
    ({deployer, user} = await getNamedAccounts());

    token = await ethers.getContract('ERC20Mock');

    const factory = await ethers.getContract('EnterpriseFactory');
    const tx = await factory.deploy(
      'Testing',
      token.address,
      'https://test.iq.io'
    );

    enterprise = await getEnterprise(factory, tx);
  });

  describe('Basic', () => {
    it('should set liquidity token', async () => {
      expect(await enterprise.liquidityToken()).to.equal(token.address);
    });
    it('should deploy interest token', async () => {
      expect(await enterprise.iToken()).not.to.equal(
        ethers.constants.AddressZero
      );
    });

    describe('iToken', async () => {
      let iToken: Contract;
      before(async () => {
        const token = await enterprise.iToken();
        const InterestToken = await ethers.getContractFactory('InterestToken');
        iToken = InterestToken.attach(token);
      });

      it('shoud set iToken name', async () => {
        const symbol = await token.symbol();
        expect(await iToken.name()).to.equal(`Interest Bearing ${symbol}`);
      });

      it('shoud set iToken symbol', async () => {
        const symbol = await token.symbol();
        expect(await iToken.symbol()).to.equal(`i${symbol}`);
      });
    });
  });

  const HALF_LIFE = 86400;
  const FACTOR = ethers.utils.parseUnits('1', 18);
  const INTEREST_RATE_HALVING_PERIOD = 20000;
  const ALLOWED_LOAN_DURATIONS = [86400, 2 * 86400, 7 * 86400];
  const ALLOWED_REFUND_CURVATURES = [1, 2, 4];
  describe('Service', () => {
    it('should register service', async () => {
      const txPromise = enterprise.registerService(
        'IQ Power Test',
        'IQPT',
        HALF_LIFE,
        FACTOR,
        INTEREST_RATE_HALVING_PERIOD,
        ALLOWED_LOAN_DURATIONS
      );

      await expect(txPromise).to.emit(enterprise, 'ServiceRegistered');
      const powerToken = await getPowerToken(enterprise, await txPromise);
      expect(await powerToken.halfLife()).to.equal(HALF_LIFE);
    });
  });

  describe('Lend-Borrow-Withdraw', () => {
    it('should perform actions', async () => {
      const LEND_AMOUNT = ONE_TOKEN.mul(100);
      const BORROW_AMOUNT = ONE_TOKEN.mul(50);
      const LEND_HALF_WITHDRAW_PERIOD = 200;

      await token.transfer(user, ONE_TOKEN.mul(100));

      // 2.Create service
      const tx = await enterprise.registerService(
        'IQ Power Test',
        'IQPT',
        HALF_LIFE,
        FACTOR,
        INTEREST_RATE_HALVING_PERIOD,
        ALLOWED_LOAN_DURATIONS
      );

      const powerToken = await getPowerToken(enterprise, tx);

      // 2.1 Approve
      await token.approve(enterprise.address, LEND_AMOUNT);
      // 3. Lend
      await enterprise.lend(LEND_AMOUNT, LEND_HALF_WITHDRAW_PERIOD);

      const userToken = await ethers.getContract('ERC20Mock', user);
      await userToken.approve(enterprise.address, ONE_TOKEN);

      const userEnterprise = await ethers.getContractAt(
        'Enterprise',
        enterprise.address,
        user
      );
      // 4. Borrow
      const borrowTx = await userEnterprise.borrow(
        powerToken.address,
        token.address,
        BORROW_AMOUNT,
        ONE_TOKEN,
        86400
      );

      await increaseTime(86400);

      // 5. Burn
      const tokenId = await getTokenId(userEnterprise, borrowTx);
      await userEnterprise.burn(powerToken.address, tokenId, BORROW_AMOUNT);

      // 6. withdraw
      console.log(
        'Balance Before withdraw: ',
        (await token.balanceOf(deployer)).toString()
      );
      await enterprise.withdrawLiquidity(
        LEND_AMOUNT,
        LEND_HALF_WITHDRAW_PERIOD,
        token.address
      );

      console.log('Balance: ', (await token.balanceOf(deployer)).toString());
    });
  });
});
