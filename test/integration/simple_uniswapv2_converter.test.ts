import { BigNumber } from '@ethersproject/bignumber';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';
import {
  ERC20,
  SimpleUniswapV2Converter,
  SimpleUniswapV2Converter__factory,
  ERC20__factory,
  IUniswapV2Router02__factory,
  IUniswapV2Router02,
  IUniswapV2Pair,
  IUniswapV2Pair__factory,
} from '../../typechain';
import { impersonate, resetFork } from '../utils';

const ONE_TOKEN = 10n ** 18n;

const PRQ_BUSD_PAIR = '0xCfaE4b92AAF0F56fAE420087833D7a8954f6fE16';
const PRQ_TOKEN = '0xd21d29b38374528675c34936bf7d5dd693d2a577';
const BUSD_TOKEN = '0xe9e7cea3dedca5984780bafc599bd69add087d56';
const PANCAKE_ROUTER = '0x10ED43C718714eb63d5aA57B78B54704E256024E';
const priceOfServiceInBusd = ONE_TOKEN * 10n; // 10 BUSD

// NOTE: https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol#L43
// NOTE:
//  Pancakeswap github contract swap fees differ from the deployed fees!
//  be careful when configuring the converter and always check the deployed code!
//   - https://github.com/pancakeswap/pancake-swap-periphery/blob/master/contracts/libraries/PancakeLibrary.sol#L44
//   - https://www.bscscan.com/address/0x10ED43C718714eb63d5aA57B78B54704E256024E#code
const performConversion = (source: bigint, amount: bigint, target: bigint) => {
  const amountInWithFee = amount * 9975n;
  const numerator = amountInWithFee * target;
  const denominator = source * 10000n + amountInWithFee;
  return numerator / denominator;
};

const humanReadableToken = (source: bigint) => {
  // NOTE: Ignore rounding.
  const whole = source / ONE_TOKEN;
  const residual = (source % ONE_TOKEN).toString().slice(0, 1);
  return `${whole}.${residual}`;
};

/// Supposed to be run as a fork of BSC chain.
describe('SimpleUniswapV2Converter', function () {
  let busd: ERC20;
  let prq: ERC20;
  let swapPair: IUniswapV2Pair;
  let router: IUniswapV2Router02;
  let converter: SimpleUniswapV2Converter;
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
    converter = await new SimpleUniswapV2Converter__factory(user).deploy(
      router.address,
      busd.address,
      prq.address,
      9975n,
      10000n
    );
  });

  describe('Basic', () => {
    it('should find the correct `Pair` token', async () => {
      const extractedPairAddress = await converter.swapPair();
      expect(extractedPairAddress).to.equal(swapPair.address, 'The expected PRQ/BUSD pair was not found!');
    });
  });
  describe('Estimate convert', () => {
    it('should correctly estimate the required PRQ tokens', async () => {
      const data = await swapPair.getReserves();
      const fetchedTargetReserve = BigInt(data.reserve0.toString());
      const fetchedSourceReserve = BigInt(data.reserve1.toString());

      const estimatedPriceInPRQ = BigInt(
        (await converter.estimateConvert(busd.address, priceOfServiceInBusd, prq.address)).toString()
      );

      const expectedPriceInPRQ = performConversion(fetchedSourceReserve, priceOfServiceInBusd, fetchedTargetReserve);
      expect(estimatedPriceInPRQ.toString()).to.equal(expectedPriceInPRQ.toString(), 'The prices do not match!');
      // Sanity check (mostly just for "visual" confirmation)
      const priceAsANiceString = humanReadableToken(estimatedPriceInPRQ);
      expect(priceAsANiceString).to.equal('29.7', `The prices do not match the expected one at block 9346625!`);
    });
    it('should correctly estimate the required BUSD tokens', async () => {
      const priceOfServiceInPRQ = priceOfServiceInBusd;
      const data = await swapPair.getReserves();
      const fetchedTargetReserve = BigInt(data.reserve1.toString());
      const fetchedSourceReserve = BigInt(data.reserve0.toString());

      const estimatedPriceInBUSD = BigInt(
        (await converter.estimateConvert(prq.address, priceOfServiceInPRQ, busd.address)).toString()
      );

      const expectedPriceInBUSD = performConversion(fetchedSourceReserve, priceOfServiceInPRQ, fetchedTargetReserve);
      expect(estimatedPriceInBUSD.toString()).to.equal(expectedPriceInBUSD.toString(), 'The prices do not match!');
      // Sanity check (mostly just for "visual" confirmation)
      expect(humanReadableToken(estimatedPriceInBUSD)).to.equal(
        '3.3',
        `The prices do not match the expected one at block 9346625!`
      );
    });
    it('should not allow estimation between a registered and an unregistered token', async () => {
      // WETH is not registered
      const WETH = await router.WETH();

      await expect(converter.estimateConvert(WETH, priceOfServiceInBusd, busd.address)).to.be.revertedWith('36');
      await expect(converter.estimateConvert(prq.address, priceOfServiceInBusd, WETH)).to.be.revertedWith('36');
    });
    it('should allow estimation when source and target are the same, even when unregistered', async () => {
      // WETH is not registered in the constructor!
      const WETH = await router.WETH();

      const estimatedPrice = await converter.estimateConvert(WETH, priceOfServiceInBusd, WETH);

      expect(estimatedPrice).to.equal(priceOfServiceInBusd.toString());
    });
    it('should allow to use the same registered token for `target` and `source` fields', async () => {
      const estimatedPrice = await converter.estimateConvert(busd.address, priceOfServiceInBusd, busd.address);

      expect(estimatedPrice).to.equal(priceOfServiceInBusd.toString());
    });
  });
  describe('Convert', () => {
    const BUSD_HOLDER = '0x8c7de13ecf6e92e249696defed7aa81e9c93931a';
    const PRQ_HOLDER = '0xfaa9721d51c49f0ca7e82203d7914c9726b5ccab'; // (note: this the IQ protocols address, but that does not matter for these tests )

    beforeEach(async () => {
      console.log('busd.balanceOf(BUSD_HOLDER)', (await busd.balanceOf(BUSD_HOLDER)).toString());
      console.log('prq.balanceOf(PRQ_HOLDER)', (await prq.balanceOf(PRQ_HOLDER)).toString());

      // Sanity check to make sure the addresses do not contain the other token type
      const balanceOfPRQforBUSDHolder = await prq.balanceOf(BUSD_HOLDER);
      const balanceOfBUSDforPRQHolder = await busd.balanceOf(PRQ_HOLDER);
      expect(balanceOfBUSDforPRQHolder).to.equal(0);
      expect(balanceOfPRQforBUSDHolder).to.equal(0);

      await hre.network.provider.send('hardhat_setBalance', [PRQ_HOLDER, '0x1000000000000000000000000000000000000000']);
    });

    it('should allow conversion BUSD -> PRQ when both tokens are registered', async () => {
      await impersonate(hre, BUSD_HOLDER);
      const busdHolder = await ethers.getSigner(BUSD_HOLDER);
      await busd.connect(busdHolder).approve(converter.address, priceOfServiceInBusd);

      await converter.connect(busdHolder).convert(busd.address, priceOfServiceInBusd, prq.address);

      const balanceOfPRQ = await prq.balanceOf(BUSD_HOLDER);
      expect(humanReadableToken(balanceOfPRQ.toBigInt())).to.equal('29.7');
    });
    it('should allow conversion PRQ -> BUSD when both tokens are registered', async () => {
      const priceOfServiceInPRQ = ONE_TOKEN;
      await impersonate(hre, PRQ_HOLDER);
      const prqHolder = await ethers.getSigner(PRQ_HOLDER);
      await prq.connect(prqHolder).approve(converter.address, priceOfServiceInPRQ);

      await converter.connect(prqHolder).convert(prq.address, priceOfServiceInPRQ, busd.address);

      // NOTE The service price is 10x smaller here than in the estimation tests.
      const balanceOfBUSD = await busd.balanceOf(PRQ_HOLDER);
      expect(humanReadableToken(balanceOfBUSD.toBigInt())).to.equal('0.3');
    });
  });
});
