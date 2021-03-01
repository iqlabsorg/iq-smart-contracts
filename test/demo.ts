const { expect } = require('chai');
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Demo, Demo__factory } from '../types';

describe('Test', () => {
  let accounts: Signer[];
  let demo: Demo;
  beforeEach(async () => {
    accounts = await ethers.getSigners();
    const factory = new Demo__factory(accounts[0]);
    demo = await factory.deploy();
  });

  it('should call hello()', async () => {
    await demo.hello();
  });
});
