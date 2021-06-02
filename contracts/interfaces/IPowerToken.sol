// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../Enterprise.sol";

interface IPowerToken is IERC20Metadata {
    function initialize(
        string memory name,
        string memory symbol,
        Enterprise enterprise
    ) external;

    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function mint(address account, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function wrap(
        IERC20 liquidityToken,
        address from,
        address to,
        uint256 amount
    ) external;

    function unwrap(
        IERC20 liquidityToken,
        address from,
        uint256 amount
    ) external;
}