import {task} from 'hardhat/config';
import {PowerToken__factory} from '../typechain/factories/PowerToken__factory';

task(
  'allow-perpetual',
  'Updates snapshot and save new rewards root on the contract'
)
  .addParam<string>('addr', 'PowerToken address')
  .setAction(async ({addr}, hre) => {
    try {
      if (!addr) {
        throw new Error(`No address specified!`);
      }

      const signers = await hre.ethers.getSigners();
      console.log(`Using: ${signers[0].address}`);

      const powerToken = (
        (await hre.ethers.getContractFactory(
          'PowerToken'
        )) as PowerToken__factory
      ).attach(addr);

      console.log((await powerToken.allowPerpetualForever()).hash);
    } catch (e) {
      console.error(e);
    }
  });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

export default {};
