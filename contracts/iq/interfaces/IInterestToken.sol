// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "../../token/IERC20Detailed.sol";

interface IInterestToken is IERC20Detailed {
    function initialize(string memory name, string memory symbol) external;

    function mint(address to, uint256 amount) external;
}
