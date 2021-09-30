import {task} from 'hardhat/config';
import {PowerToken__factory} from '../typechain/factories/PowerToken__factory';

task('set-base-rate', 'Sets base rate for PowerToken')
  .addParam<string>('addr', 'PowerToken address')
  .addParam<string>(
    'baserate',
    'Base rate calculated by the formula (shifted 64 bits left)'
  )
  .addParam<string>('basetoken', 'Base token')
  .addParam<string>('mingcfee', 'Min GC fee (in wei)')
  .setAction(async ({addr, baserate, basetoken, mingcfee}, {ethers}) => {
    try {
      if (!addr) {
        throw new Error(`No address specified!`);
      }

      const signers = await ethers.getSigners();
      console.log(`Using: ${signers[0].address}`);

      const powerToken = (
        (await ethers.getContractFactory('PowerToken')) as PowerToken__factory
      ).attach(addr);

      console.log(
        (await powerToken.setBaseRate(baserate, basetoken, mingcfee)).hash
      );
    } catch (e) {
      console.error(e);
    }
  });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

export default {};
