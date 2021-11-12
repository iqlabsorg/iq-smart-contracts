// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IRentalTokenStorage.sol";

interface IRentalToken is IERC721, IRentalTokenStorage {
    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId, address burner) external;

    function getNextTokenId() external returns (uint256);
}
