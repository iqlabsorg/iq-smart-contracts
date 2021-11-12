import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const [enterprise, powerToken, stakeToken, rentalToken] = await Promise.all([
    deployments.get('Enterprise'),
    deployments.get('PowerToken'),
    deployments.get('StakeToken'),
    deployments.get('RentalToken'),
  ]);

  await deploy('EnterpriseFactory', {
    from: deployer,
    args: [enterprise.address, powerToken.address, stakeToken.address, rentalToken.address],
    log: true,
  });
};
export default func;
func.tags = ['production', 'enterprise-factory'];
