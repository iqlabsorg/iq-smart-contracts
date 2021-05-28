// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Currency converter interface.
 */
interface IConverter {
    /**
     * Estimates convertion of `source` currency into `target` currency
     */
    function estimateConvert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) external view returns (uint256);

    /**
     * After calling this function it is expected that requested currency will be
     * transferred to the msg.sender automatically
     */
    function convert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) external returns (uint256);
}
