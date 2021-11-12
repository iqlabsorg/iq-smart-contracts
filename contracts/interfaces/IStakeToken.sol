// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IStakeTokenStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStakeToken is IERC721, IStakeTokenStorage {
    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId) external;

    function getNextTokenId() external view returns (uint256);
}
