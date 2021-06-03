import {BigNumber, BigNumberish} from '@ethersproject/bignumber';
import {ContractTransaction} from 'ethers';
import {ethers} from 'hardhat';
import {
  BorrowToken,
  Enterprise,
  EnterpriseFactory,
  IConverter,
  IEstimator,
  InterestToken,
  PowerToken,
} from '../typechain';

export const evmSnapshot = async (): Promise<any> =>
  ethers.provider.send('evm_snapshot', []);
export const evmRevert = async (id: string): Promise<any> =>
  ethers.provider.send('evm_revert', [id]);
export const nextBlock = async (timestamp = 0) =>
  ethers.provider.send('evm_mine', timestamp > 0 ? [timestamp] : []);
export const increaseTime = async (seconds: number) => {
  ethers.provider.send('evm_increaseTime', [seconds]);
  await nextBlock();
};
export const currentTime = async (): Promise<number> => {
  const block = await ethers.provider.getBlock('latest');
  return block.timestamp;
};

export const deployEnterprise = async (
  name: string,
  token: string
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
    estimator.address,
    converter.address
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

export const toTokens = (amount: BigNumberish, decimals = 2): string => {
  const a = BigInt(amount.toString());
  const dec = 10n ** BigInt(18 - decimals);
  return (Number(a / dec) / 10 ** decimals).toFixed(decimals);
};

export const baseRate = (
  tokens: bigint,
  period: bigint,
  price: bigint
): bigint => {
  return (price << 64n) / (tokens * period);
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
