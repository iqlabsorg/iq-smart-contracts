// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../token/IERC20Detailed.sol";
import "./IInitializableOwnable.sol";
import "../EnterpriseConfigurator.sol";

interface IPowerToken is IERC20Detailed, IInitializableOwnable {
    function initialize(
        string memory name,
        string memory symbol,
        EnterpriseConfigurator configurator
    ) external;

    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function mint(address account, uint256 amoun) external;

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
