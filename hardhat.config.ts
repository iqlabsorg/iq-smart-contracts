import { task } from 'hardhat/config';
import 'solidity-coverage';
// import 'hardhat-typechain';
import '@nomiclabs/hardhat-waffle';
import { HardhatUserConfig } from 'hardhat/types';

// task action function receives the Hardhat Runtime Environment as second argument
task('accounts', 'Prints accounts', async (_, { ethers }) => {
  console.log(await ethers.getSigners());
});

const buidlerConfig: HardhatUserConfig = {
  solidity: {
    version: '0.8.2',
    settings: {
      optimizer: {
        enabled: false,
        runs: 200,
      },
    },
  },
  // typechain: {
  //   outDir: 'types',
  //   target: 'ethers-v5',
  // },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {},
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  mocha: {
    timeout: 20000,
  },
};

export default buidlerConfig;
