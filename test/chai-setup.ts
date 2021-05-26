import chaiModule from 'chai';
import {chaiEthers} from 'chai-ethers'; // TODO: move to hardhat-waffle
chaiModule.use(chaiEthers);
export = chaiModule;
