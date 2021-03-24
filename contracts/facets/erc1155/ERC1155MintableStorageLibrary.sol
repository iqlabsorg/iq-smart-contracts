// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

library ERC1155MintableStorageLibrary {
    bytes32 constant ERC1155_MINTABLE_STORAGE_POSITION = keccak256('iq.protocol.erc1155.mintable');

    struct ERC1155MintableStorage {
        mapping(uint256 => address) creators;
        // A nonce to ensure we have a unique id each time we mint.
        uint256 nonce;
    }

    function erc1155MintableStorage() internal pure returns (ERC1155MintableStorage storage result) {
        bytes32 position = ERC1155_MINTABLE_STORAGE_POSITION;
        assembly {
            result.slot := position
        }
    }
}
