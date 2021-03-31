import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from '@ethersproject/contracts';
import { f2b, b2f } from '../scripts/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber } from '@ethersproject/bignumber';

describe('PowerToken', function () {
  let token: Contract;
  let accounts: SignerWithAddress[];
  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  const HALF_LIFE = 100;

  beforeEach(async () => {
    accounts = await ethers.getSigners();
    [admin, user] = accounts;

    const PowerToken = await ethers.getContractFactory('PowerToken');
    token = await PowerToken.deploy(HALF_LIFE);
    await token.deployed();
  });

  it('should mint', async () => {
    await token.mint(999, user.address, ethers.constants.WeiPerEther.mul(BigNumber.from(1000)));
  });

  it('should return balance', async () => {
    await token.mint(999, user.address, ethers.constants.WeiPerEther.mul(BigNumber.from(1000)));

    expect(await token.balanceOf(user.address, 999)).to.equal(ethers.constants.WeiPerEther.mul(BigNumber.from(1000)));
  });

  it('should ');
});
