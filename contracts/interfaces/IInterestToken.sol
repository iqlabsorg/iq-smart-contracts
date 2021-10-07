// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./IInterestTokenStorage.sol";

interface IInterestToken is IERC721Enumerable, IInterestTokenStorage {
    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId) external;

    function getNextTokenId() external view returns (uint256);
}
