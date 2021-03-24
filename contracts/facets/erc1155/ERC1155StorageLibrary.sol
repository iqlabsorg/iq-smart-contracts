// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

library ERC1155StorageLibrary {
    bytes32 constant ERC1155_STORAGE_POSITION = keccak256('iq.protocol.erc1155');

    struct ERC1155Storage {
        mapping(uint256 => mapping(address => uint256)) balances;
        mapping(address => mapping(address => bool)) operatorApproval;
    }

    function erc1155Storage() internal pure returns (ERC1155Storage storage result) {
        bytes32 position = ERC1155_STORAGE_POSITION;
        assembly {
            result.slot := position
        }
    }
}
