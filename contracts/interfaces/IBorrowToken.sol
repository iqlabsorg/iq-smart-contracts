// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IEnterprise.sol";
import "../EnterpriseConfigurator.sol";

interface IBorrowToken is IERC721 {
    function initialize(
        string memory name,
        string memory symbol,
        string memory baseUri,
        EnterpriseConfigurator configurator,
        IEnterprise enterprise
    ) external;

    function mint(address to) external returns (uint256);

    function burn(uint256 tokenId, address burner) external;

    function getCounter() external returns (uint256);
}
