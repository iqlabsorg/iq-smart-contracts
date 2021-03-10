// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

library ERC1155StorageLibrary {
  bytes32 constant ERC1155_STORAGE_POSITION = keccak256("iq.protocol.erc1155");

  struct ERC1155Storage {
    mapping (uint256 => mapping(address => uint256)) balances;
    mapping (address => mapping(address => bool)) operatorApproval;
  }

  function erc1155Storage() internal pure returns (ERC1155Storage storage erc1155storage) {
    bytes32 position = ERC1155_STORAGE_POSITION;
    assembly {
      erc1155storage.slot := position
    }
  }
}