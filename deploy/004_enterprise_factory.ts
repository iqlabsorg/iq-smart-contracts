import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {deployer} = await getNamedAccounts();

  const [powerToken, interestToken, enterprise] = await Promise.all([
    deployments.get('PowerToken'),
    deployments.get('InterestToken'),
    deployments.get('Enterprise'),
  ]);

  await deploy('EnterpriseFactory', {
    from: deployer,
    args: [powerToken.address, interestToken.address, enterprise.address],
    log: true,
  });
};
export default func;
func.tags = ['Enterprise'];
