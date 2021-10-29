import { waffle } from 'hardhat';
import chaiModule from 'chai';

chaiModule.use(waffle.solidity);

// import {chaiEthers} from 'chai-ethers'; // TODO: move to hardhat-waffle
// chaiModule.use(chaiEthers);
export = chaiModule;
