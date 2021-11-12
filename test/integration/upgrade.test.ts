/* eslint-disable @typescript-eslint/no-var-requires */
import { Contract } from '@ethersproject/contracts';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signers';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';
import {
  RentalToken,
  RentalToken__factory,
  StakeToken,
  StakeToken__factory,
  PowerToken,
  PowerToken__factory,
} from '../../typechain';
import { impersonate, resetFork } from '../utils';
import { PARSIQ_ENTERPRISE_ADDRESS } from './addresses';
import { BigNumber } from '@ethersproject/bignumber';

// prettier-ignore
const ENTERPRISE_ABI = require('../../deployments/binance/Enterprise.json').abi;
// prettier-ignore
const RENTAL_TOKEN_ABI = require('../../deployments/binance/BorrowToken.json').abi;
// prettier-ignore
const STAKE_TOKEN_ABI = require('../../deployments/binance/InterestToken.json').abi;
// prettier-ignore
const POWER_TOKEN_ABI = require('../../deployments/binance/PowerToken.json').abi;

describe('Integration', () => {
  let user: SignerWithAddress;
  let enterprise: Contract;
  let admin: SignerWithAddress;
  let factoryAddress: string;

  beforeEach(async () => {
    await resetFork(hre, 11963530);

    [, user] = await ethers.getSigners();
    enterprise = new Contract(PARSIQ_ENTERPRISE_ADDRESS, ENTERPRISE_ABI, user);
    [factoryAddress] = await enterprise.functions.getFactory();
    const [owner] = await enterprise.functions.owner();
    await impersonate(hre, owner);
    admin = await ethers.getSigner(owner);
  });

  describe('RentalToken', () => {
    let rentalToken: Contract;
    let newRentalToken: RentalToken;

    beforeEach(async () => {
      const rentalTokenAddress = await enterprise.functions.getBorrowToken();

      rentalToken = new Contract(rentalTokenAddress[0], RENTAL_TOKEN_ABI, user);

      newRentalToken = await new RentalToken__factory(user).deploy();
    });

    it('should successfully upgrade', async () => {
      // TODO: uncomment after renaming patch is deployed
      // const [tokenId] = await rentalToken.functions.getNextTokenId();
      const [enterpriseAddress] = await rentalToken.functions.getEnterprise();
      const [zeroTokenId] = await rentalToken.functions.tokenByIndex(0);
      const [totalSupply] = await rentalToken.functions.totalSupply();

      await enterprise
        .connect(admin)
        .upgrade(
          factoryAddress,
          ethers.constants.AddressZero,
          newRentalToken.address,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          []
        );

      const upgraded = RentalToken__factory.connect(rentalToken.address, user);

      // TODO: uncomment after renaming patch is deployed
      // expect(tokenId).is.above(0);
      // expect(await upgraded.getNextTokenId()).to.deep.eq(tokenId);
      expect(await upgraded.totalSupply()).to.deep.eq(totalSupply);
      expect(await upgraded.getEnterprise()).to.deep.eq(enterpriseAddress);
      expect(await upgraded.tokenByIndex(0)).to.deep.eq(zeroTokenId);
    });
  });

  describe('StakeToken', () => {
    let stakeToken: Contract;
    let newStakeToken: StakeToken;

    beforeEach(async () => {
      const [stakeTokenAddress] = await enterprise.functions.getInterestToken();

      stakeToken = new Contract(stakeTokenAddress, STAKE_TOKEN_ABI, user);

      newStakeToken = await new StakeToken__factory(user).deploy();
    });

    it('should successfully upgrade', async () => {
      // TODO: uncomment after renaming patch is deployed
      // const [tokenId] = await stakeToken.functions.getNextTokenId();
      const [enterpriseAddress] = await stakeToken.functions.getEnterprise();
      const [zeroTokenId] = await stakeToken.functions.tokenByIndex(0);
      const [totalSupply] = await stakeToken.functions.totalSupply();

      await enterprise
        .connect(admin)
        .upgrade(
          factoryAddress,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          newStakeToken.address,
          ethers.constants.AddressZero,
          []
        );

      const upgraded = StakeToken__factory.connect(stakeToken.address, user);
      // TODO: uncomment after renaming patch is deployed
      // expect(tokenId).is.above(0);
      // expect(await upgraded.getNextTokenId()).to.deep.eq(tokenId);
      expect(await upgraded.totalSupply()).to.deep.eq(totalSupply);
      expect(await upgraded.getEnterprise()).to.deep.eq(enterpriseAddress);
      expect(await upgraded.tokenByIndex(0)).to.deep.eq(zeroTokenId);
    });
  });

  describe('PowerToken', () => {
    const referenceAddress = '0x979c2f8df5d6df2bcf2a6771117f7a62a7462621';
    let powerTokens: Contract[];
    let newPowerToken: PowerToken;
    let swappingEnabled: boolean[];
    let balances: BigNumber[];
    let totalSupply: BigNumber[];
    let upgraded: PowerToken[];

    beforeEach(async () => {
      const [tokens] = await enterprise.functions.getPowerTokens();

      powerTokens = tokens.map((x: string) => new Contract(x, POWER_TOKEN_ABI, user));

      newPowerToken = await new PowerToken__factory(user).deploy();
      swappingEnabled = await Promise.all(powerTokens.map((x) => x.functions.isWrappingEnabled())).then((x) =>
        x.map((y) => y[0])
      );
      balances = await Promise.all(powerTokens.map((x) => x.functions.balanceOf(referenceAddress))).then((x) =>
        x.map((y) => y[0])
      );
      totalSupply = await Promise.all(powerTokens.map((x) => x.functions.totalSupply())).then((x) =>
        x.map((y) => y[0])
      );

      await enterprise
        .connect(admin)
        .upgrade(
          factoryAddress,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          newPowerToken.address,
          tokens
        );

      upgraded = powerTokens.map((x) => PowerToken__factory.connect(x.address, user));
    });

    it('should successfully upgrade', async () => {
      expect(await Promise.all(upgraded.map((x) => x.isSwappingEnabled()))).to.deep.eq(swappingEnabled);
      expect(await Promise.all(upgraded.map((x) => x.balanceOf(referenceAddress)))).to.deep.eq(balances);
      expect(await Promise.all(upgraded.map((x) => x.totalSupply()))).to.deep.eq(totalSupply);
      expect(await Promise.all(upgraded.map((x) => x.isTransferEnabled()))).to.deep.eq([false, false, false, false]);
      expect(await Promise.all(upgraded.map((x) => x.getEnterprise()))).to.deep.eq([
        enterprise.address,
        enterprise.address,
        enterprise.address,
        enterprise.address,
      ]);
    });

    it('should keep the same after transfer is enabled', async () => {
      await Promise.all(upgraded.map((x) => x.connect(admin).enableTransferForever()));

      expect(await Promise.all(upgraded.map((x) => x.isSwappingEnabled()))).to.deep.eq(swappingEnabled);
      expect(await Promise.all(upgraded.map((x) => x.balanceOf(referenceAddress)))).to.deep.eq(balances);
      expect(await Promise.all(upgraded.map((x) => x.totalSupply()))).to.deep.eq(totalSupply);
      expect(await Promise.all(upgraded.map((x) => x.isTransferEnabled()))).to.deep.eq([true, true, true, true]);
      expect(await Promise.all(upgraded.map((x) => x.getEnterprise()))).to.deep.eq([
        enterprise.address,
        enterprise.address,
        enterprise.address,
        enterprise.address,
      ]);
    });
  });
});
