// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "./interfaces/IInterestToken.sol";
import "./Enterprise.sol";
import "./EnterpriseOwnable.sol";
import "./token/ERC721Enumerable.sol";

contract InterestToken is IInterestToken, EnterpriseOwnable, ERC721Enumerable {
    uint256 private _tokenIdTracker;

    function initialize(
        string memory name_,
        string memory symbol_,
        Enterprise enterprise
    ) external {
        EnterpriseOwnable.initialize(enterprise);
        ERC721.initialize(name_, symbol_);
    }

    function getNextTokenId() public view returns (uint256) {
        return _tokenIdTracker;
    }

    function _baseURI() internal view override returns (string memory) {
        string memory baseURI = getEnterprise().getBaseUri();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, "interest/")) : "";
    }

    function mint(address to) external override onlyEnterprise returns (uint256) {
        uint256 tokenId = _tokenIdTracker;
        _safeMint(to, tokenId);
        _tokenIdTracker++;
        return tokenId;
    }

    function burn(uint256 tokenId) external override onlyEnterprise {
        _burn(tokenId);
    }
}
