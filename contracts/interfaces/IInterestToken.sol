// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IInterestTokenStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IInterestToken is IERC721, IInterestTokenStorage {
    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId) external;

    function getNextTokenId() external view returns (uint256);
}
