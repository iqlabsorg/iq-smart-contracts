import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';
import {
  ERC20,
  ParsiqPancakeConverter,
  ParsiqPancakeConverter__factory,
  ERC20__factory,
  IUniswapV2Router02__factory,
  IUniswapV2Router02,
  IUniswapV2Pair,
  IUniswapV2Pair__factory,
} from '../../typechain';
import { resetFork } from '../utils';

const ONE_TOKEN = 10n ** 18n;

const PRQ_BUSD_PAIR = '0xCfaE4b92AAF0F56fAE420087833D7a8954f6fE16';
const PRQ_TOKEN = '0xd21d29b38374528675c34936bf7d5dd693d2a577';
const BUSD_TOKEN = '0xe9e7cea3dedca5984780bafc599bd69add087d56';
const PANCAKE_ROUTER = '0x10ED43C718714eb63d5aA57B78B54704E256024E';
const priceOfServiceInBusd = ONE_TOKEN * 10n; // 10 BUSD

// NOTE https://ethereum.stackexchange.com/a/103869
const performConversion = (source: bigint, amount: bigint, target: bigint) => (target * amount) / (source + amount);

/// Supposed to be run as a fork of BSC chain.
describe('ParsiqPancakeConverter', function () {
  let busd: ERC20;
  let prq: ERC20;
  let swapPair: IUniswapV2Pair;
  let router: IUniswapV2Router02;
  let converter: ParsiqPancakeConverter;
  let user: SignerWithAddress;

  /**
   * NOTE: This information is manually validated!
   * BlockNumber: 9346625
   * Date: Jul-21-2021 09:01:34 AM +UTC
   * Rate: 1 PRQ  per 0.334917 BUSD
   * Rate: 1 BUSD per 2.985814 PRQ
   */
  beforeEach(async () => {
    await resetFork(hre, 9346625);

    [user] = await ethers.getSigners();
    busd = ERC20__factory.connect(BUSD_TOKEN, user);
    prq = ERC20__factory.connect(PRQ_TOKEN, user);
    router = IUniswapV2Router02__factory.connect(PANCAKE_ROUTER, user);
    swapPair = IUniswapV2Pair__factory.connect(PRQ_BUSD_PAIR, user);

    // Deploy the converter
    converter = await new ParsiqPancakeConverter__factory(user).deploy(router.address, busd.address, prq.address);
  });

  describe('Basic', () => {
    it('should find the correct `Pair` token', async () => {
      const extractedPairAddress = await converter.swapPair();
      expect(extractedPairAddress).to.equal(swapPair.address, 'The expected PRQ/BUSD pair was not found!');
    });
  });
  describe('Estimate convert', () => {
    it('should correctly estimate the required PRQ tokens', async () => {
      const estimatedPriceInPRQ = BigInt(
        (await converter.estimateConvert(busd.address, priceOfServiceInBusd, prq.address)).toString()
      );

      const data = await swapPair.getReserves();
      const fetchedTargetReserve = BigInt(data.reserve0.toString());
      const fetchedSourceReserve = BigInt(data.reserve1.toString());

      const expectedPriceInPRQ = performConversion(fetchedSourceReserve, priceOfServiceInBusd, fetchedTargetReserve);

      expect(estimatedPriceInPRQ).to.equal(expectedPriceInPRQ, 'The prices do not match!');

      // Sanity check (mostly just for "visual" confirmation)
      // NOTE: Ignore rounding.
      const whole = estimatedPriceInPRQ / ONE_TOKEN;
      const residual = (estimatedPriceInPRQ % ONE_TOKEN).toString().slice(0, 3);
      expect(`${whole}.${residual}`).to.equal('29.778', `The prices do not match the expected one at block 9346625!`);
    });
    it('should correctly estimate the required BUSD tokens', async () => {
      const estimatedPriceInPRQ = BigInt(
        (await converter.estimateConvert(prq.address, priceOfServiceInBusd, busd.address)).toString()
      );

      const data = await swapPair.getReserves();
      const fetchedTargetReserve = BigInt(data.reserve1.toString());
      const fetchedSourceReserve = BigInt(data.reserve0.toString());

      const expectedPriceInPRQ = performConversion(fetchedSourceReserve, priceOfServiceInBusd, fetchedTargetReserve);

      expect(estimatedPriceInPRQ).to.equal(expectedPriceInPRQ, 'The prices do not match!');

      // Sanity check (mostly just for "visual" confirmation)
      // NOTE: Ignore rounding.
      const whole = estimatedPriceInPRQ / ONE_TOKEN;
      const residual = (estimatedPriceInPRQ % ONE_TOKEN).toString().slice(0, 3);
      expect(`${whole}.${residual}`).to.equal('3.357', `The prices do not match the expected one at block 9346625!`);
    });
    it('should not allow estimation between a registered and an unregistered token', async () => {
      const WETH = await router.WETH();
      // WETH is not registered
      await expect(converter.estimateConvert(WETH, priceOfServiceInBusd, busd.address)).to.be.revertedWith('36');
      await expect(converter.estimateConvert(prq.address, priceOfServiceInBusd, WETH)).to.be.revertedWith('36');
    });
    it('should allow estimation when source and target are the same, even when unregistered', async () => {
      const WETH = await router.WETH();
      // WETH is not registered in the constructor!
      const estimatedPrice = await converter.estimateConvert(WETH, priceOfServiceInBusd, WETH);
      expect(estimatedPrice).to.equal(priceOfServiceInBusd.toString());
    });
    it('should allow to use the same registered token for `target` and `source` fields', async () => {
      const estimatedPrice = await converter.estimateConvert(busd.address, priceOfServiceInBusd, busd.address);
      expect(estimatedPrice).to.equal(priceOfServiceInBusd.toString());
    });
  });
  describe('Convert', () => {
    it('should revert on conversion when both tokens are not equal', async () => {
      await expect(converter.convert(busd.address, ONE_TOKEN, prq.address)).to.be.revertedWith('36');
    });
    it('should not revert on conversion using equal tokens', async () => {
      const conversionResult = await converter.convert(prq.address, ONE_TOKEN, prq.address);
      expect(conversionResult).to.equal(ONE_TOKEN);
    });
  });
});
