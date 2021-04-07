import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from '@ethersproject/contracts';
import { f2b, b2f } from '../scripts/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish } from 'ethers';

type EnegryTestCase = [BigNumberish, number, BigNumberish];

const ONE_ETHER = ethers.constants.WeiPerEther;

describe('PowerToken', function () {
  let token: Contract;
  let userToken: Contract;
  let accounts: SignerWithAddress[];
  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  let other: SignerWithAddress;
  const HALF_LIFE = 100;

  beforeEach(async () => {
    accounts = await ethers.getSigners();
    [admin, user, other] = accounts;

    const PowerToken = await ethers.getContractFactory('PowerToken');
    token = await PowerToken.deploy('Test', 'TST', 'https://test.io/', HALF_LIFE);
    userToken = token.connect(user);
  });

  it('should mint', async () => {
    await token.mint(user.address, 999, ONE_ETHER.mul(1000), '0x');
  });

  it('should return balance', async () => {
    await token.mint(user.address, 999, ONE_ETHER.mul(1000), '0x');

    expect(await token.balanceOf(user.address, 999)).to.equal(ONE_ETHER.mul(1000));
  });

  describe('transfer', () => {
    it('should transfer tokens', async () => {
      await token.mint(user.address, 999, ONE_ETHER.mul(1000), '0x');

      await userToken.safeTransferFrom(user.address, other.address, 999, ONE_ETHER.mul(1000), '0x');

      expect(await token.balanceOf(other.address, 999)).to.equal(ONE_ETHER.mul(1000));
    });
  });

  describe('energy', () => {
    ([
      [ONE_ETHER.mul(1000), HALF_LIFE, ONE_ETHER.mul(500)],
      [ONE_ETHER.mul(9999), HALF_LIFE, ethers.utils.parseEther('4999.5')],
    ] as EnegryTestCase[]).forEach(([amount, period, expected], idx) => {
      it(`should calculate energy: ${idx}`, async () => {
        const tx = await token.mint(user.address, 999, amount, '0x');
        const block = await ethers.provider.getBlock(tx.blockNumber);

        const result = await token.energyAt(user.address, block.timestamp + period);

        expect(result).to.equal(expected);
      });
    });
  });
});
