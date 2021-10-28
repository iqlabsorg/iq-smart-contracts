// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./EnterpriseOwnable.sol";
import "./token/ERC721Enumerable.sol";
import "./interfaces/IStakeTokenStorage.sol";

abstract contract StakeTokenStorage is IStakeTokenStorage, EnterpriseOwnable, ERC721Enumerable {
    uint256 internal _tokenIdTracker;

    function initialize(
        string memory name,
        string memory symbol,
        IEnterprise enterprise
    ) external override {
        EnterpriseOwnable.initialize(enterprise);
        ERC721.initialize(name, symbol);
    }
}
