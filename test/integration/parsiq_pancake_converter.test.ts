import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import { expect } from 'chai';
import { BigNumber, BigNumberish } from 'ethers';
import { ethers } from 'hardhat';
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

const ONE_ETHER = 10n ** 18n;
const ONE_TOKEN = 10n ** 18n;

const PRQ_BUSD_PAIR = '0xCfaE4b92AAF0F56fAE420087833D7a8954f6fE16';
const PRQ_TOKEN = '0xd21d29b38374528675c34936bf7d5dd693d2a577';
const BUSD_TOKEN = '0xe9e7cea3dedca5984780bafc599bd69add087d56';
const PANCAKE_ROUTER = '0x10ED43C718714eb63d5aA57B78B54704E256024E';
const priceOfServiceInBusd = BigNumber.from(ONE_TOKEN).mul(10); // 10 BUSD

/// Supposed to be run as a fork of BSC chain.
describe.only('ParsiqPancakeConverter', function () {
  let busd: ERC20;
  let prq: ERC20;
  let swapPair: IUniswapV2Pair;
  let router: IUniswapV2Router02;
  let converter: ParsiqPancakeConverter;
  let user: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async () => {
    [user, user2] = await ethers.getSigners();
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
      const estimatedPriceInPRQ = await converter.estimateConvert(busd.address, priceOfServiceInBusd, prq.address);

      const onePRQInBUSD = await swapPair.price0CumulativeLast();
      const expectedPrice = onePRQInBUSD.mul(priceOfServiceInBusd);
      expect(estimatedPriceInPRQ).to.equal(expectedPrice, 'The prices do not match!');

      console.log('Price of the service (10 BUSD) nominated in PRQ is:', estimatedPriceInPRQ.div(ONE_TOKEN).toString());
    });
    it('should not allow estimation between unregistered tokens', async () => {
      const WETH = await router.WETH();
      // WETH is not registered
      await expect(converter.estimateConvert(WETH, priceOfServiceInBusd, busd.address)).to.be.revertedWith('36');
      await expect(converter.estimateConvert(WETH, priceOfServiceInBusd, WETH)).to.be.revertedWith('36');
      await expect(converter.estimateConvert(prq.address, priceOfServiceInBusd, WETH)).to.be.revertedWith('36');
    });
    it('should not allow estimation with source and target tokens swapped', async () => {
      await expect(converter.estimateConvert(prq.address, priceOfServiceInBusd, busd.address)).to.be.revertedWith('36');
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
