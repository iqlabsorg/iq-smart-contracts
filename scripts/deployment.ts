import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import { FacetCutAction, getSelectors } from './utils';

export async function deployDiamond() {
  const [admin] = await ethers.getSigners();
  const ERC1155Mintable = await ethers.getContractFactory('ERC1155Mintable');
  const erc1155Proxy = await ERC1155Mintable.deploy();
  // We get the contract to deploy
  const DiamondCutFacet = await ethers.getContractFactory('DiamondCutFacet');
  const diamondCutFacetProxy = await DiamondCutFacet.deploy();
  const DiamondLoupeFacet = await ethers.getContractFactory('DiamondLoupeFacet');
  const diamondLoupeFacetProxy = await DiamondLoupeFacet.deploy();
  const OwnershipFacet = await ethers.getContractFactory('OwnershipFacet');
  const ownershipFacetProxy = await OwnershipFacet.deploy();

  const Diamond = await ethers.getContractFactory('Diamond');
  const diamond = await Diamond.deploy(
    [
      [diamondCutFacetProxy.address, FacetCutAction.Add, getSelectors(diamondCutFacetProxy)],
      [diamondLoupeFacetProxy.address, FacetCutAction.Add, getSelectors(diamondLoupeFacetProxy)],
      [ownershipFacetProxy.address, FacetCutAction.Add, getSelectors(ownershipFacetProxy)],
      [erc1155Proxy.address, FacetCutAction.Add, getSelectors(erc1155Proxy)],
    ],
    {
      owner: admin.address,
    }
  );
  console.log('Diamond deployed to:', diamond.address);
}

export async function deploy(account: SignerWithAddress, liquidityToken: string, baseUri: string) {
  const RentingPool = await ethers.getContractFactory('RentingPool', account);
  const pool = await RentingPool.deploy(liquidityToken, baseUri);
  return pool;
}
