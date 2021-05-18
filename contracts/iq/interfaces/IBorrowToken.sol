// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IEnterprise.sol";

interface IBorrowToken is IERC721 {
    function initialize(
        IEnterprise enterprise,
        string memory name,
        string memory symbol,
        string memory baseUri
    ) external;

    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId) external;
}
