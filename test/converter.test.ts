import {ethers, waffle} from 'hardhat';
import {expect} from 'chai';
import {BigNumberish, Wallet} from 'ethers';
import {Enterprise, ERC20Mock, PowerToken} from '../typechain';
import {baseRate, deployEnterprise, ONE_DAY, registerService} from './utils';

type EnegryTestCase = [BigNumberish, number, BigNumberish];

const ONE_ETHER = 10n ** 18n;
const ONE_TOKEN = 10n ** 18n;

describe('PowerToken', function () {
  let token: ERC20Mock;
  let user: Wallet;
  let enterprise: Enterprise;
  let powerToken: PowerToken;

  const GAP_HALVING_PERIOD = 100;

  beforeEach(async () => {
    [user] = await waffle.provider.getWallets();
    token = (await ethers.getContract('ERC20Mock')) as ERC20Mock;
    enterprise = await deployEnterprise('Testing', token.address);

    powerToken = await registerService(
      enterprise,
      GAP_HALVING_PERIOD,
      baseRate(100n, 86400n, 3n),
      token.address,
      300,
      0,
      ONE_DAY * 365,
      ONE_TOKEN,
      true
    );
  });
});
