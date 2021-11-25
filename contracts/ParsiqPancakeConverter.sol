// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility renting
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Stake strong!

pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IConverter.sol";
import "./libs/Errors.sol";
import "./libs/IUniswapV2Router02.sol";
import "./libs/IUniswapV2Pair.sol";
import "./libs/IUniswapV2Factory.sol";

/**
 * TODO: proper name here
 */
contract ParsiqPancakeConverter is IConverter {
    IUniswapV2Pair public immutable swapPair;
    IUniswapV2Router02 private _uniswapRouter;

    /**
     * TODO: proper natspec here
     */
    constructor(
        IUniswapV2Router02 uniswapRouter,
        IERC20 allowedSourceCoin, // <- STABLECOIN (BUSD)
        IERC20 allowedTargetCoin // <- PRQ
    ) {
        _uniswapRouter = uniswapRouter;
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(_uniswapRouter.factory());
        swapPair = IUniswapV2Pair(uniswapFactory.getPair(address(allowedSourceCoin), address(allowedTargetCoin)));
    }

    /**
     * TODO: proper natspec here
     */
    function estimateConvert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) external view override returns (uint256) {
        require(address(source) == swapPair.token0(), Errors.DC_UNSUPPORTED_PAIR);
        require(address(target) == swapPair.token1(), Errors.DC_UNSUPPORTED_PAIR);

        // the price of token1 denominated in token0
        return swapPair.price1CumulativeLast() * amount;
    }

    /**
     * @dev Converts `source` tokens to `target` tokens.
     * Converted tokens must be on `msg.sender` address after exiting this function
     */
    function convert(
        IERC20 source,
        uint256 amount,
        IERC20 target
    ) external pure override returns (uint256) {
        require(address(source) == address(target), Errors.DC_UNSUPPORTED_PAIR);
        return amount;
    }
}
