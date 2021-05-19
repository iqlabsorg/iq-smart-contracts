// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma abicoder v2;

import "./IPowerToken.sol";

interface IEnterprise {
    struct BorrowInfo {
        IPowerToken powerToken; // 20 bytes
        uint32 from; // 4 bytes
        uint32 to; // 4 bytes
        // slot 1, 4 bytes left
        uint112 amount; // 14 bytes
        // slot 2, 18 bytes left
    }

    function initialize(
        string memory name,
        address liquidityToken,
        string memory baseUri,
        address interestTokenImpl,
        address powerTokenImpl,
        address borrowTokenImpl,
        address owner
    ) external;

    function getBorrowInfo(uint256 tokenId) external view returns (BorrowInfo memory);

    function returnBorrowed(uint256 tokenId) external;
}
