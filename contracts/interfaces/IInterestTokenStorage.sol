// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./IEnterprise.sol";

interface IInterestTokenStorage is IERC721Enumerable {
    function initialize(
        string memory name,
        string memory symbol,
        IEnterprise enterprise
    ) external;
}
