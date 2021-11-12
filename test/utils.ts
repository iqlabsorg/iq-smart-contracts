import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { Contract, ContractTransaction, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import {
  RentalToken,
  Enterprise,
  EnterpriseFactory,
  IConverter,
  IERC20,
  StakeToken,
  PowerToken,
  ProxyAdmin,
} from '../typechain';

export const ONE_DAY = 86400;
export const ONE_HOUR = 3600;

export const evmSnapshot = async (): Promise<unknown> => ethers.provider.send('evm_snapshot', []);
export const evmRevert = async (id: string): Promise<unknown> => ethers.provider.send('evm_revert', [id]);
export const nextBlock = async (timestamp = 0): Promise<unknown> =>
  ethers.provider.send('evm_mine', timestamp > 0 ? [timestamp] : []);
export const increaseTime = async (seconds: number): Promise<void> => {
  const time = await currentTime();
  await nextBlock(time + seconds);
};
export const setNextBlockTimestamp = async (timestamp: number): Promise<unknown> =>
  ethers.provider.send('evm_setNextBlockTimestamp', [timestamp]);
export const currentTime = async (): Promise<number> => {
  const block = await ethers.provider.getBlock('latest');
  return block.timestamp;
};

export const deployEnterprise = async (name: string, token: string, converterAddress?: string): Promise<Enterprise> => {
  const converter = (await ethers.getContract('DefaultConverter')) as IConverter;

  const factory = (await ethers.getContract('EnterpriseFactory')) as EnterpriseFactory;
  const tx = await factory.deploy(
    name,
    token,
    'https://test.iq.space',
    0, // 0% gc fee
    converterAddress || converter.address
  );

  return getEnterprise(factory, tx);
};

export const getEnterprise = async (
  enterpriseFactory: EnterpriseFactory,
  deployTx: ContractTransaction
): Promise<Enterprise> => {
  const receipt = await deployTx.wait(1);

  const events = await enterpriseFactory.queryFilter(
    enterpriseFactory.filters.EnterpriseDeployed(),
    receipt.blockNumber
  );

  const enterpriseAddress = events[0].args.deployed;

  const Enterprise = await ethers.getContractFactory('Enterprise');

  return Enterprise.attach(enterpriseAddress) as Enterprise;
};

export const getRentalToken = async (enterprise: Enterprise): Promise<RentalToken> => {
  const rentalTokenAddress = await enterprise.getRentalToken();
  const RentalToken = await ethers.getContractFactory('RentalToken');

  return RentalToken.attach(rentalTokenAddress) as RentalToken;
};

export const getPowerToken = async (
  enterprise: Enterprise,
  registerServiceTx: ContractTransaction
): Promise<PowerToken> => {
  const receipt = await registerServiceTx.wait(1);

  const events = await enterprise.queryFilter(enterprise.filters.ServiceRegistered(), receipt.blockNumber);

  const powerTokenAddress = events[0].args[0];

  const PowerToken = await ethers.getContractFactory('PowerToken');

  return PowerToken.attach(powerTokenAddress) as PowerToken;
};

export const getRentalTokenId = async (enterprise: Enterprise, rentingTx: ContractTransaction): Promise<BigNumber> => {
  const receipt = await rentingTx.wait(1);

  const events = await enterprise.queryFilter(enterprise.filters.Rented(), receipt.blockNumber);

  return BigNumber.from(events[0].args.rentalTokenId);
};

export const getStakeTokenId = async (enterprise: Enterprise, stakeTx: ContractTransaction): Promise<BigNumber> => {
  const receipt = await stakeTx.wait();
  const StakeToken = await ethers.getContractFactory('StakeToken');

  const stakeToken = StakeToken.attach(await enterprise.getStakeToken()) as StakeToken;

  const events = await stakeToken.queryFilter(stakeToken.filters.Transfer(), receipt.blockNumber);

  return BigNumber.from(events[0].args.tokenId);
};

export const getStakeToken = async (enterprise: Enterprise): Promise<StakeToken> => {
  const iTokenAddress = await enterprise.getStakeToken();

  const iToken = await ethers.getContractFactory('StakeToken');

  return iToken.attach(iTokenAddress) as StakeToken;
};

export const toTokens = (amount: BigNumberish, decimals = 2, tokenDecimals = 18): number => {
  const a = BigInt(amount.toString());
  const dec = 10n ** BigInt(tokenDecimals - decimals);
  return Number(a / dec) / 10 ** decimals;
};

export const fromTokens = (amount: number, decimals = 6, tokenDecimals = 18): BigNumber => {
  const a = BigInt(Math.trunc(amount));
  const f = amount - Math.trunc(amount);

  return BigNumber.from(
    (a * 10n ** BigInt(decimals) + BigInt(Math.trunc(f * 10 ** decimals))) * 10n ** BigInt(tokenDecimals - decimals)
  );
};

export const baseRate = (
  tokens: bigint,
  period: bigint,
  price: bigint,
  tokenDecimals = 18n,
  priceDecimals = 18n
): bigint => {
  if (tokenDecimals > priceDecimals) {
    return ((price * 10n ** (tokenDecimals - priceDecimals)) << 64n) / (tokens * period);
  } else if (tokenDecimals < priceDecimals) {
    return (price << 64n) / (tokens * 10n ** (priceDecimals - tokenDecimals) * period);
  }
  return (price << 64n) / (tokens * period);
};

export const basePrice = (tokens: number, period: number, price: number): number => {
  return price / (tokens * period);
};

export const estimateRentalFee = (
  basePrice: number,
  reserves: number,
  usedReserves: number,
  amount: number,
  duration: number,
  pole = 0.05,
  slope = 0.3
): number => {
  return g(amount) * basePrice * duration;

  function f(x: number) {
    return ((1.0 - pole) * slope) / (x - pole) + (1.0 - slope);
  }

  function h(x: number) {
    return x * f((reserves - x) / reserves);
  }

  function g(x: number) {
    return h(usedReserves + x) - h(usedReserves);
  }
};

export const stake = async (enterprise: Enterprise, amount: BigNumberish, user?: Signer): Promise<BigNumber> => {
  const ERC20 = await ethers.getContractFactory('ERC20Mock');
  const token = ERC20.attach(await enterprise.getEnterpriseToken());

  if (user) {
    await token.connect(user).approve(enterprise.address, amount);
    return getStakeTokenId(enterprise, await enterprise.connect(user).stake(amount));
  } else {
    await token.approve(enterprise.address, amount);
    return getStakeTokenId(enterprise, await enterprise.stake(amount));
  }
};

export const getProxyAdmin = async (enterprise: Enterprise): Promise<ProxyAdmin> => {
  const proxyAdminAddress = await enterprise.getProxyAdmin();
  const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin');
  return ProxyAdmin.attach(proxyAdminAddress) as ProxyAdmin;
};

export const getProxyImplementation = async (enterprise: Enterprise, proxy: Contract | string): Promise<string> => {
  const proxyAdmin = await getProxyAdmin(enterprise);
  return proxyAdmin.getProxyImplementation(typeof proxy === 'string' ? proxy : proxy.address);
};

export const rent = async (
  enterprise: Enterprise,
  powerToken: PowerToken,
  paymentToken: IERC20,
  rentalAmount: BigNumberish,
  rentalPeriod: number,
  maxPayment: BigNumberish,
  user?: Signer
): Promise<ContractTransaction> => {
  if (user) {
    await paymentToken.connect(user).approve(enterprise.address, maxPayment);
    return enterprise
      .connect(user)
      .rent(powerToken.address, paymentToken.address, rentalAmount, rentalPeriod, maxPayment);
  }
  await paymentToken.approve(enterprise.address, maxPayment);
  return enterprise.rent(powerToken.address, paymentToken.address, rentalAmount, rentalPeriod, maxPayment);
};

export const extendRentalPeriod = async (
  enterprise: Enterprise,
  rentalTokenId: BigNumberish,
  paymentToken: IERC20,
  rentalPeriod: number,
  maxPayment: BigNumberish,
  user?: Signer
): Promise<ContractTransaction> => {
  if (user) {
    await paymentToken.connect(user).approve(enterprise.address, maxPayment);
    return enterprise.connect(user).extendRentalPeriod(rentalTokenId, paymentToken.address, rentalPeriod, maxPayment);
  }
  await paymentToken.approve(enterprise.address, maxPayment);
  return enterprise.extendRentalPeriod(rentalTokenId, paymentToken.address, rentalPeriod, maxPayment);
};

export const registerService = async (
  enterprise: Enterprise,
  energyGapHalvingPeriod: BigNumberish,
  baseRate: BigNumberish,
  baseToken: string,
  serviceFeePercent: BigNumberish,
  minRentalPeriod: BigNumberish,
  maxRentalPeriod: BigNumberish,
  minGCFee: BigNumberish,
  swappingEnabledForever: boolean
): Promise<PowerToken> => {
  const tx = await enterprise.registerService(
    'IQ Power Test',
    'IQPT',
    energyGapHalvingPeriod,
    baseRate,
    baseToken,
    serviceFeePercent,
    minRentalPeriod,
    maxRentalPeriod,
    minGCFee,
    swappingEnabledForever
  );

  return getPowerToken(enterprise, tx);
};

export const resetFork = async (hre: HardhatRuntimeEnvironment, block?: number): Promise<void> => {
  await hre.network.provider.request({
    method: 'hardhat_reset',
    params: block
      ? [
          {
            forking: {
              jsonRpcUrl: process.env.ETH_NODE_URI_BINANCE,
              blockNumber: block,
            },
          },
        ]
      : [],
  });
};

export const impersonate = async (hre: HardhatRuntimeEnvironment, account: string): Promise<void> => {
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [account],
  });
};
