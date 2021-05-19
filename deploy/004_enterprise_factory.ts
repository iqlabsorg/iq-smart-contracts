import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {deployer} = await getNamedAccounts();

  const [powerToken, interestToken, borrowToken, enterprise] =
    await Promise.all([
      deployments.get('PowerToken'),
      deployments.get('InterestToken'),
      deployments.get('BorrowToken'),
      deployments.get('Enterprise'),
    ]);

  await deploy('EnterpriseFactory', {
    from: deployer,
    args: [
      enterprise.address,
      powerToken.address,
      interestToken.address,
      borrowToken.address,
    ],
    log: true,
  });
};
export default func;
func.tags = ['EnterpriseFactory'];
