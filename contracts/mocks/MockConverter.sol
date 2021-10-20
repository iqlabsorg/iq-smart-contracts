// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IConverter.sol";

/**
 * Mock converter, for testing purposes only
 * DO NOT USE IN PRODUCTION!!!
 */
contract MockConverter is IConverter {
    mapping(IERC20 => mapping(IERC20 => uint256)) rates;

    function estimateConvert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) external view override returns (uint256) {
        if (address(source) == address(target)) return amount;

        return _estimateConvert(source, amount, target);
    }

    function _estimateConvert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) internal view returns (uint256) {
        uint256 rate = rates[source][target];

        uint256 source_one = 10**IERC20Metadata(address(source)).decimals();

        return
            normalize(IERC20Metadata(address(source)), IERC20Metadata(address(target)), (amount * source_one) / rate);
    }

    /**
     * @dev Converts `source` tokens to `target` tokens.
     * Converted tokens must be on `msg.sender` address after exiting this function
     */
    function convert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) external override returns (uint256) {
        if (address(source) == address(target)) return amount;

        uint256 converted = _estimateConvert(source, amount, target);

        source.transferFrom(msg.sender, address(this), amount);
        target.transfer(msg.sender, converted);

        return converted;
    }

    function setRate(
        IERC20Metadata source,
        IERC20Metadata target,
        uint256 rate
    ) public {
        rates[source][target] = rate;

        uint256 source_one = 10**source.decimals();

        uint256 inverseRate = normalize(source, target, (source_one * 10**source.decimals()) / rate);

        rates[target][source] = inverseRate;
    }

    function normalize(
        IERC20Metadata source,
        IERC20Metadata target,
        uint256 rate
    ) internal view returns (uint256) {
        if (source.decimals() > target.decimals()) {
            return rate / 10**(source.decimals() - target.decimals());
        } else if (source.decimals() < target.decimals()) {
            return rate * 10**(target.decimals() - source.decimals());
        }
        return rate;
    }
}
