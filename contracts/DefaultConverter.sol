// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IConverter.sol";

/**
 * Noop converter
 */
contract DefaultConverter is IConverter {
    function estimateConvert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) external pure override returns (uint256) {
        require(address(source) == address(target), "Not supported");

        return amount;
    }

    function convert(
        IERC20 source,
        uint256,
        IERC20 target
    ) external pure override {
        require(address(source) == address(target), "Not supported");
    }
}
