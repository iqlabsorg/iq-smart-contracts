// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBorrowToken is IERC721 {
    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId, address burner) external;

    function getNextTokenId() external returns (uint256);
}
