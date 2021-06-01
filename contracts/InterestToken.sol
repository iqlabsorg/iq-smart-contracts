// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "./interfaces/IInterestToken.sol";
import "./Enterprise.sol";
import "./InitializableOwnable.sol";
import "./token/ERC721Enumerable.sol";

contract InterestToken is IInterestToken, InitializableOwnable, ERC721Enumerable {
    uint256 private _counter;
    Enterprise private _enterprise;

    function initialize(
        string memory name_,
        string memory symbol_,
        Enterprise enterprise
    ) external {
        InitializableOwnable.initialize(address(enterprise));
        ERC721.initialize(name_, symbol_);
        _enterprise = enterprise;
    }

    function getCounter() public view returns (uint256) {
        return _counter;
    }

    function _baseURI() internal view override returns (string memory) {
        string memory baseURI = _enterprise.getBaseUri();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, "interest/")) : "";
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
}
