// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "./interfaces/IEnterprise.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IPowerToken.sol";
import "./InitializableOwnable.sol";
import "../token/ERC721.sol";

contract BorrowToken is IBorrowToken, InitializableOwnable, ERC721 {
    IEnterprise private _enterprise;
    uint256 private _counter = 1;

    function initialize(
        IEnterprise enterprise,
        string memory name,
        string memory symbol,
        string memory baseUri,
        address owner
    ) external override {
        initialize(owner);
        initialize(name, symbol);
        _setBaseURI(baseUri);
        _enterprise = enterprise;
    }

    function mint(address to) external override onlyOwner returns (uint256) {
        uint256 tokenId = _counter;
        _safeMint(to, tokenId);
        _counter++;
        return tokenId;
    }

    function burn(uint256 tokenId) external override onlyOwner {
        _burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        IEnterprise.BorrowInfo memory borrowed = _enterprise.getBorrowInfo(tokenId);
        require(
            block.timestamp <= borrowed.to || to == address(_enterprise) || to == address(0),
            "Cannot transfer expired tokens"
        );

        if (to == address(_enterprise)) {
            _enterprise.returnBorrowed(tokenId);
        } else if (to == address(0)) {
            borrowed.powerToken.burnFrom(from, borrowed.amount, true);
        } else {
            borrowed.powerToken.transfer(from, to, borrowed.amount);
        }
    }
}
