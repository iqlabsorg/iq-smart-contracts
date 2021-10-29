import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { parseEther } from 'ethers/lib/utils';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy('ERC20Mock', {
    from: deployer,
    args: ['Testing', 'TST', 18, parseEther('1000000000')],
    log: true,
  });

  await deploy('ExpMathMock', {
    from: deployer,
    log: true,
  });
};
export default func;
func.tags = ['test'];
