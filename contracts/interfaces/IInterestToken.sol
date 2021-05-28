// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IInterestToken is IERC20Metadata {
    function initialize(string memory name, string memory symbol) external;

    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}
