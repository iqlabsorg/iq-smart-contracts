import {Contract} from '@ethersproject/contracts';
import {ethers} from 'hardhat';

export const evmSnapshot = async () => ethers.provider.send('evm_snapshot', []);
export const evmRevert = async (id: string) =>
  ethers.provider.send('evm_revert', [id]);
export const nextBlock = async (timestamp = 0) =>
  ethers.provider.send('evm_mine', timestamp > 0 ? [timestamp] : []);
export const increaseTime = async (seconds: number) =>
  ethers.provider.send('evm_increaseTime', [seconds]);
export const currentTime = async (): Promise<number> => {
  const block = await ethers.provider.getBlock('latest');
  return block.timestamp;
};

export const getEnterprise = async (
  enterpriseFactory: Contract,
  deployTx: any
): Promise<Contract> => {
  const receipt = await deployTx.wait(1);

  const events = await enterpriseFactory.queryFilter(
    enterpriseFactory.filters.EnterpriseDeployed(),
    receipt.blockNumber
  );

  const enterpriseAddress = events[0].args?.[4];

  const Enterprise = await ethers.getContractFactory('Enterprise');

  return Enterprise.attach(enterpriseAddress);
};

export const getPowerToken = async (
  enterprise: Contract,
  registerServiceTx: any
): Promise<Contract> => {
  const receipt = await registerServiceTx.wait(1);

  const events = await enterprise.queryFilter(
    enterprise.filters.ServiceRegistered(),
    receipt.blockNumber
  );

  const powerTokenAddress = events[0].args?.[0];

  const PowerToken = await ethers.getContractFactory('PowerToken');

  return PowerToken.attach(powerTokenAddress);
};

export const getTokenId = async (
  rentingPool: Contract,
  borrowTx: any
): Promise<string> => {
  const receipt = await borrowTx.wait(1);

  const events = await rentingPool.queryFilter(
    rentingPool.filters.Borrowed(),
    receipt.blockNumber
  );

  return events[0].args?.tokenId;
};

export const getInterestToken = async (
  rentingPool: Contract
): Promise<Contract> => {
  const iTokenAddress = await rentingPool.iToken();

  const iToken = await ethers.getContractFactory('InterestToken');

  return iToken.attach(iTokenAddress);
};
