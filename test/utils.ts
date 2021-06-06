import {BigNumber, BigNumberish} from '@ethersproject/bignumber';
import {ContractTransaction} from 'ethers';
import {ethers} from 'hardhat';
import {
  BorrowToken,
  Enterprise,
  EnterpriseFactory,
  IConverter,
  IERC20,
  IEstimator,
  InterestToken,
  IPowerToken,
  PowerToken,
} from '../typechain';
import {Wallet} from '@ethersproject/wallet';

export const ONE_DAY = 86400;
export const ONE_HOUR = 3600;

export const evmSnapshot = async (): Promise<unknown> =>
  ethers.provider.send('evm_snapshot', []);
export const evmRevert = async (id: string): Promise<unknown> =>
  ethers.provider.send('evm_revert', [id]);
export const nextBlock = async (timestamp = 0): Promise<unknown> =>
  ethers.provider.send('evm_mine', timestamp > 0 ? [timestamp] : []);
export const increaseTime = async (seconds: number): Promise<void> => {
  const time = await currentTime();
  await nextBlock(time + seconds);
};
export const currentTime = async (): Promise<number> => {
  const block = await ethers.provider.getBlock('latest');
  return block.timestamp;
};

export const deployEnterprise = async (
  name: string,
  token: string,
  converterAddress?: string,
  estimatorImpl?: string
): Promise<Enterprise> => {
  const estimator = (await ethers.getContract(
    'DefaultEstimator'
  )) as IEstimator;
  const converter = (await ethers.getContract(
    'DefaultConverter'
  )) as IConverter;

  const factory = (await ethers.getContract(
    'EnterpriseFactory'
  )) as EnterpriseFactory;
  const tx = await factory.deploy(
    'Testing',
    token,
    'https://test.iq.space',
    0, // 0% gc fee
    estimatorImpl || estimator.address,
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

  const enterpriseAddress = events[0].args?.deployed;

  const Enterprise = await ethers.getContractFactory('Enterprise');

  return Enterprise.attach(enterpriseAddress) as Enterprise;
};

export const getBorrowToken = async (
  enterprise: Enterprise
): Promise<BorrowToken> => {
  const borrowTokenAddress = await enterprise.getBorrowToken();
  const BorrowToken = await ethers.getContractFactory('BorrowToken');

  return BorrowToken.attach(borrowTokenAddress) as BorrowToken;
};

export const getPowerToken = async (
  enterprise: Enterprise,
  registerServiceTx: ContractTransaction
): Promise<PowerToken> => {
  const receipt = await registerServiceTx.wait(1);

  const events = await enterprise.queryFilter(
    enterprise.filters.ServiceRegistered(),
    receipt.blockNumber
  );

  const powerTokenAddress = events[0].args?.[0];

  const PowerToken = await ethers.getContractFactory('PowerToken');

  return PowerToken.attach(powerTokenAddress) as PowerToken;
};

export const getTokenId = async (
  enterprise: Enterprise,
  borrowTx: ContractTransaction
): Promise<BigNumber> => {
  const receipt = await borrowTx.wait(1);

  const events = await enterprise.queryFilter(
    enterprise.filters.Borrowed(),
    receipt.blockNumber
  );

  return events[0].args?.tokenId;
};

export const getInterestTokenId = async (
  enterprise: Enterprise,
  liquidityTx: ContractTransaction
): Promise<BigNumber> => {
  const receipt = await liquidityTx.wait();
  const InterestToken = await ethers.getContractFactory('InterestToken');

  const interestToken = InterestToken.attach(
    await enterprise.getInterestToken()
  ) as InterestToken;

  const events = await interestToken.queryFilter(
    interestToken.filters.Transfer(),
    receipt.blockNumber
  );

  return events[0].args?.tokenId;
};

export const getInterestToken = async (
  enterprise: Enterprise
): Promise<InterestToken> => {
  const iTokenAddress = await enterprise.getInterestToken();

  const iToken = await ethers.getContractFactory('InterestToken');

  return iToken.attach(iTokenAddress) as InterestToken;
};

export const toTokens = (
  amount: BigNumberish,
  decimals = 2,
  tokenDecimals = 18
): number => {
  const a = BigInt(amount.toString());
  const dec = 10n ** BigInt(tokenDecimals - decimals);
  return Number(a / dec) / 10 ** decimals;
};

export const fromTokens = (
  amount: number,
  decimals = 6,
  tokenDecimals = 18
): BigNumber => {
  const a = BigInt(Math.trunc(amount));
  const f = amount - Math.trunc(amount);

  return BigNumber.from(
    (a * 10n ** BigInt(decimals) + BigInt(Math.trunc(f * 10 ** decimals))) *
      10n ** BigInt(tokenDecimals - decimals)
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
    return (
      ((price * 10n ** (tokenDecimals - priceDecimals)) << 64n) /
      (tokens * period)
    );
  } else if (tokenDecimals < priceDecimals) {
    return (
      (price << 64n) /
      (tokens * 10n ** (priceDecimals - tokenDecimals) * period)
    );
  }
  return (price << 64n) / (tokens * period);
};

export const basePrice = (
  tokens: number,
  period: number,
  price: number
): number => {
  return price / (tokens * period);
};

export const estimateLoan = (
  basePrice: number,
  reserves: number,
  usedReserves: number,
  amount: number,
  duration: number,
  lambda = 1.0
): number => {
  return g(amount) * basePrice * duration;

  function f(x: number) {
    return 1.0 - lambda * Math.log2(x);
  }

  function h(x: number) {
    return x * f((reserves - x) / reserves);
  }

  function g(x: number) {
    return h(usedReserves + x) - h(usedReserves);
  }
};

export const addLiquidity = async (
  enterprise: Enterprise,
  amount: BigNumberish,
  user?: Wallet
): Promise<ContractTransaction> => {
  const ERC20 = await ethers.getContractFactory('ERC20Mock');
  const token = ERC20.attach(await enterprise.getLiquidityToken());

  if (user) {
    await token.connect(user).approve(enterprise.address, amount);
    return enterprise.connect(user).addLiquidity(amount);
  } else {
    await token.approve(enterprise.address, amount);
    return enterprise.addLiquidity(amount);
  }
};

export const borrow = async (
  enterprise: Enterprise,
  powerToken: IPowerToken,
  paymentToken: IERC20,
  amount: BigNumberish,
  duration: number,
  maxPayment: BigNumberish,
  user?: Wallet
): Promise<ContractTransaction> => {
  if (user) {
    await paymentToken.connect(user).approve(enterprise.address, maxPayment);
    return enterprise
      .connect(user)
      .borrow(
        powerToken.address,
        paymentToken.address,
        amount,
        duration,
        maxPayment
      );
  } else {
    await paymentToken.approve(enterprise.address, maxPayment);
    return enterprise.borrow(
      powerToken.address,
      paymentToken.address,
      amount,
      duration,
      maxPayment
    );
  }
};

export const registerService = async (
  enterprise: Enterprise,
  halfLife: BigNumberish,
  baseRate: BigNumberish,
  baseToken: string,
  serviceFee: BigNumberish,
  minLoanDuration: BigNumberish,
  maxLoanDuration: BigNumberish,
  minGCFee: BigNumberish,
  allowsPerpetualTokens: boolean
): Promise<PowerToken> => {
  const txPromise = enterprise.registerService(
    'IQ Power Test',
    'IQPT',
    halfLife,
    baseRate,
    baseToken,
    serviceFee,
    minLoanDuration,
    maxLoanDuration,
    minGCFee,
    allowsPerpetualTokens
  );

  return getPowerToken(enterprise, await txPromise);
};
