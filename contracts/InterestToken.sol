// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility loans
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Lend long and prosper!

pragma solidity 0.8.4;

import "./interfaces/IInterestToken.sol";
import "./interfaces/IEnterprise.sol";
import "./InterestTokenStorage.sol";

contract InterestToken is InterestTokenStorage, IInterestToken {
    function getNextTokenId() public view override returns (uint256) {
        return uint256(keccak256(abi.encodePacked("i", address(this), _tokenIdTracker)));
    }

    function _baseURI() internal view override returns (string memory) {
        string memory baseURI = getEnterprise().getBaseUri();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, "interest/")) : "";
    }

    function mint(address to) external override onlyEnterprise returns (uint256) {
        uint256 tokenId = getNextTokenId();
        _safeMint(to, tokenId);
        _tokenIdTracker++;
        return tokenId;
    }

    function burn(uint256 tokenId) external override onlyEnterprise {
        _burn(tokenId);
    }
}
