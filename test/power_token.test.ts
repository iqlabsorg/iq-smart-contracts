import {ethers, getNamedAccounts} from 'hardhat';
import {expect} from 'chai';
import {Contract} from '@ethersproject/contracts';
import {BigNumberish} from 'ethers';
import {Address} from 'hardhat-deploy/types';
import {PowerToken__factory} from '../typechain';

type EnegryTestCase = [BigNumberish, number, BigNumberish];

const ONE_ETHER = ethers.constants.WeiPerEther;

describe('PowerToken', function () {
  let token: Contract;
  let userToken: Contract;
  let user: Address;
  let stranger: Address;
  const HALF_LIFE = 100;

  beforeEach(async () => {
    ({user, stranger} = await getNamedAccounts());

    token = await ethers.getContract('PowerToken');
    const factory = new PowerToken__factory(
      await ethers.getNamedSigner('deployer')
    );
    token = await factory.deploy();
    await token.initialize('Test', 'TST', 'https://test.io/', HALF_LIFE);

    userToken = PowerToken__factory.connect(
      token.address,
      await ethers.getNamedSigner('user')
    );
  });

  it('should mint', async () => {
    await token.mint(user, 999, ONE_ETHER.mul(1000), '0x');
  });

  it('should return balance', async () => {
    await token.mint(user, 999, ONE_ETHER.mul(1000), '0x');

    expect(await token.balanceOf(user, 999)).to.equal(ONE_ETHER.mul(1000));
  });

  describe('transfer', () => {
    it('should transfer tokens', async () => {
      await token.mint(user, 999, ONE_ETHER.mul(1000), '0x');

      await userToken.safeTransferFrom(
        user,
        stranger,
        999,
        ONE_ETHER.mul(1000),
        '0x'
      );

      expect(await token.balanceOf(stranger, 999)).to.equal(
        ONE_ETHER.mul(1000)
      );
    });
  });

  describe('energy', () => {
    ([
      [ONE_ETHER.mul(1000), HALF_LIFE, ONE_ETHER.mul(500)],
      [ONE_ETHER.mul(9999), HALF_LIFE, ethers.utils.parseEther('4999.5')],
    ] as EnegryTestCase[]).forEach(([amount, period, expected], idx) => {
      it(`should calculate energy: ${idx}`, async () => {
        const tx = await token.mint(user, 999, amount, '0x');
        const block = await ethers.provider.getBlock(tx.blockNumber);

        const result = await token.energyAt(user, block.timestamp + period);

        expect(result).to.equal(expected);
      });
    });
  });
});
