// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import '../../erc1155/SafeMath.sol';
import '../../erc1155/Address.sol';
import './ERC1155.sol';
import './ERC1155MintableStorageLibrary.sol';

/**
    @dev Mintable form of ERC1155
    Shows how easy it is to mint new items.
*/
contract ERC1155Mintable is ERC1155 {
    using SafeMath for uint256;
    using Address for address;
    bytes4 private constant INTERFACE_SIGNATURE_URI = 0x0e89341c;

    constructor() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[INTERFACE_SIGNATURE_URI] = true;
    }

    modifier creatorOnly(uint256 _id) {
        ERC1155MintableStorageLibrary.ERC1155MintableStorage storage ds =
            ERC1155MintableStorageLibrary.erc1155MintableStorage();
        require(ds.creators[_id] == msg.sender);
        _;
    }

    // Creates a new token type and assings _initialSupply to minter
    function create(uint256 _initialSupply, string calldata _uri) external returns (uint256 _id) {
        ERC1155MintableStorageLibrary.ERC1155MintableStorage storage ds =
            ERC1155MintableStorageLibrary.erc1155MintableStorage();
        ERC1155StorageLibrary.ERC1155Storage storage erc1155ds = ERC1155StorageLibrary.erc1155Storage();

        _id = ++ds.nonce;
        ds.creators[_id] = msg.sender;
        erc1155ds.balances[_id][msg.sender] = _initialSupply;

        // Transfer event with mint semantic
        emit TransferSingle(msg.sender, address(0x0), msg.sender, _id, _initialSupply);

        if (bytes(_uri).length > 0) emit URI(_uri, _id);
    }

    // Batch mint tokens. Assign directly to _to[].
    function mint(
        uint256 _id,
        address[] calldata _to,
        uint256[] calldata _quantities
    ) external creatorOnly(_id) {
        ERC1155StorageLibrary.ERC1155Storage storage ds = ERC1155StorageLibrary.erc1155Storage();

        for (uint256 i = 0; i < _to.length; ++i) {
            address to = _to[i];
            uint256 quantity = _quantities[i];

            // Grant the items to the caller
            ds.balances[_id][to] = quantity.add(ds.balances[_id][to]);

            // Emit the Transfer/Mint event.
            // the 0x0 source address implies a mint
            // It will also provide the circulating supply info.
            emit TransferSingle(msg.sender, address(0x0), to, _id, quantity);

            if (to.isContract()) {
                _doSafeTransferAcceptanceCheck(msg.sender, msg.sender, to, _id, quantity, '');
            }
        }
    }

    function setURI(string calldata _uri, uint256 _id) external creatorOnly(_id) {
        emit URI(_uri, _id);
    }
}
