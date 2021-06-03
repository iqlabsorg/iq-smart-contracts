import {ethers, waffle} from 'hardhat';
import {expect} from 'chai';
import {BigNumberish, Wallet} from 'ethers';
import {
  Enterprise,
  ERC20,
  ERC20Mock,
  IERC20Metadata,
  PowerToken,
  PowerToken__factory,
} from '../typechain';
import {baseRate, deployEnterprise, registerService} from './utils';

type EnegryTestCase = [BigNumberish, number, BigNumberish];

const ONE_ETHER = 10n ** 18n;
const ONE_TOKEN = 10n ** 18n;

describe('PowerToken', function () {
  let token: ERC20Mock;
  let user: Wallet;
  let enterprise: Enterprise;
  let powerToken: PowerToken;
  let stranger: Wallet;

  const HALF_LIFE = 100;

  beforeEach(async () => {
    [user, stranger] = await waffle.provider.getWallets();
    token = (await ethers.getContract('ERC20Mock')) as ERC20Mock;
    enterprise = await deployEnterprise('Testing', token.address);

    powerToken = await registerService(
      enterprise,
      HALF_LIFE,
      baseRate(100n, 86400n, 3n),
      token.address,
      300,
      0,
      86400 * 365,
      ONE_TOKEN,
      true
    );
  });

  describe('energy', () => {
    (
      [
        [ONE_ETHER * 1000n, HALF_LIFE, ONE_ETHER * 500n],
        [ONE_ETHER * 9999n, HALF_LIFE, ethers.utils.parseEther('4999.5')],
      ] as EnegryTestCase[]
    ).forEach(([amount, period, expected], idx) => {
      it(`should calculate energy: ${idx}`, async () => {
        await token.approve(powerToken.address, amount);
        const tx = await enterprise.wrap(powerToken.address, amount);

        const block = await ethers.provider.getBlock(
          (
            await tx.wait()
          ).blockNumber
        );

        const result = await powerToken.energyAt(
          user.address,
          block.timestamp + period
        );

        expect(result).to.equal(expected);
      });
    });
  });
});
