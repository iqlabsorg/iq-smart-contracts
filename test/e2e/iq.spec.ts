import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '../../scripts/deployment';
import { getInterestToken, getPowerToken, getTokenId, increaseTime } from '../utils';

describe('IQ Protocol E2E', () => {
  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  let otherUser: SignerWithAddress;
  let token: Contract;
  let pool: Contract;

  const ONE_TOKEN = ethers.utils.parseEther('1');

  beforeEach(async () => {
    const accounts = await ethers.getSigners();
    [admin, user, otherUser] = accounts;
    const ERC20 = await ethers.getContractFactory('ERC20Mock', admin);
    token = await ERC20.deploy('IQ Test', 'IQT', ONE_TOKEN.mul(100000));
    pool = await deploy(admin, token.address, 'https://test.iq.io');
  });

  describe('Basic', () => {
    it('should set liquidity token', async () => {
      expect(await pool.liquidityToken()).to.equal(token.address);
    });
    it('should deploy interest token', async () => {
      expect(await pool.iToken()).not.to.equal(ethers.constants.AddressZero);
    });

    describe('iToken', async () => {
      let iToken: Contract;
      before(async () => {
        const token = await pool.iToken();
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
      const tx = await pool.registerService(
        'IQ Power Test',
        'IQPT',
        HALF_LIFE,
        FACTOR,
        INTEREST_RATE_HALVING_PERIOD,
        ALLOWED_LOAN_DURATIONS,
        ALLOWED_REFUND_CURVATURES
      );

      await expect(tx).to.emit(pool, 'ServiceRegistered');
      const powerToken = await getPowerToken(pool, tx);
      expect(await powerToken.halfLife()).to.equal(HALF_LIFE);
    });
  });

  describe('Lend-Borrow-Withdraw', () => {
    it('should perform actions', async () => {
      const LEND_AMOUNT = ONE_TOKEN.mul(100);
      const BORROW_AMOUNT = ONE_TOKEN.mul(50);
      const LEND_HALF_WITHDRAW_PERIOD = 200;

      // 2.Create service
      const tx = await pool.registerService(
        'IQ Power Test',
        'IQPT',
        HALF_LIFE,
        FACTOR,
        INTEREST_RATE_HALVING_PERIOD,
        ALLOWED_LOAN_DURATIONS,
        ALLOWED_REFUND_CURVATURES
      );

      const powerToken = await getPowerToken(pool, tx);

      // 2.1 Approve
      await token.approve(pool.address, LEND_AMOUNT);
      // 3. Lend
      await pool.lend(LEND_AMOUNT, LEND_HALF_WITHDRAW_PERIOD);

      await token.connect(otherUser);
      await token.approve(pool.address, ONE_TOKEN);

      await pool.connect(otherUser);
      // 4. Borrow
      const borrowTx = await pool.borrow(powerToken.address, token.address, BORROW_AMOUNT, ONE_TOKEN, 86400, 1);
      const tokenId = await getTokenId(pool, borrowTx);

      await increaseTime(86400);

      // 5. Burn
      await pool.burn(powerToken.address, tokenId, BORROW_AMOUNT);

      await pool.connect(admin);

      const iToken = await getInterestToken(pool);
      const balance = iToken.balanceOf(admin.address, tokenId);
      // 6. withdraw
      await pool.withdrawLiquidity(balance, LEND_HALF_WITHDRAW_PERIOD, token.address);

      console.log('Balance: ', await token.balanceOf(admin.address));
    });
  });
});
