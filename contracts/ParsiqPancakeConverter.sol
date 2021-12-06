// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility renting
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Stake strong!

pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./interfaces/IConverter.sol";
import "./libs/Errors.sol";

/**
 * Pancakeswap converter for estimating token prices.
 */
contract ParsiqPancakeConverter is IConverter {
    IUniswapV2Pair public immutable swapPair;
    IUniswapV2Router02 private immutable _uniswapRouter;

    /**
     * @notice Constructor for `ParsiqPancakeConverter`
     * @param uniswapRouter - UniswapV2 router implementation. On BSC that would be Pancakeswap.
     * @param allowedTokenOne - The ERC20 token that's used for finding the swap pair
     * @param allowedTargetTwo - The ERC20 token that's used for finding the swap pair
     * @dev The token pair must be pre-deployed and registered on the router!
     * @dev The contract will find the existing token pair.
     */
    constructor(
        IUniswapV2Router02 uniswapRouter,
        IERC20 allowedTokenOne, // <- STABLECOIN (BUSD)
        IERC20 allowedTargetTwo // <- PRQ
    ) {
        _uniswapRouter = uniswapRouter;
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());
        swapPair = IUniswapV2Pair(uniswapFactory.getPair(address(allowedTokenOne), address(allowedTargetTwo)));
    }

    /**
     * @notice Perform estimation of how many `target` tokens are necessary to cover required amount of `source` tokens.
     * @param source - the source token address (e.g. stablecoin)
     * @param target - the target token address (e.g. volitale coin)
     * @param amountInSourceTokens - the amount of source token price
     * @dev Source and target token addresses must be the exact ones as specified in the constructor of this contract.
     */
    function estimateConvert(
        IERC20 source,
        uint256 amountInSourceTokens,
        IERC20 target
    ) public view override returns (uint256) {
        if (address(source) == address(target)) return amountInSourceTokens;
        (uint112 targetReserve, uint112 sourceReserve, ) = retrieveReservesInSourceTargetOrder(
            address(source),
            address(target)
        );
        return estimateConvertWithReserves(sourceReserve, amountInSourceTokens, targetReserve);
    }

    /**
     * @notice Noop converter. Reverts if `source` and `target` tokens differ.
     */
    function convert(
        IERC20 source,
        uint256 amountInSourceTokens,
        IERC20 target
    ) external override returns (uint256) {
        if (address(source) == address(target)) return amountInSourceTokens;

        (uint112 targetReserve, uint112 sourceReserve, bool token0IsTarget) = retrieveReservesInSourceTargetOrder(
            address(source),
            address(target)
        );
        uint256 amountInTargetTokens = (targetReserve / sourceReserve) * amountInSourceTokens;

        // https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair#swap-1
        address[] memory path = new address[](2);
        if (token0IsTarget) {
            path[0] = address(source);
            path[1] = address(target);
        } else {
            path[0] = address(target);
            path[1] = address(source);
        }

        // 0. (must be done before) Approve: msg.sender -> converter
        // 1. Transfer: msg.sender -> converter
        // 2. Approve: covnerter -> uniswap router
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountInTargetTokens);
        IERC20(path[0]).approve(address(_uniswapRouter), amountInTargetTokens);

        // https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02#swapexacttokensfortokens
        // Swaps an exact amount of input tokens for as many output tokens as possible, along the route determined by the path.
        // The first element of path is the input token, the last is the output token, and any intermediate elements represent
        // intermediate pairs to trade through (if, for example, a direct pair does not exist).
        uint256[] memory resultAmounts = _uniswapRouter.swapExactTokensForTokens(
            amountInSourceTokens,
            amountInTargetTokens,
            path,
            msg.sender,
            block.timestamp
        );
        return resultAmounts[1];
    }

    /**
     * @notice Return price estimations on given token reserves
     * @dev Formula for conversion: https://ethereum.stackexchange.com/a/103869
     *      `Y * I / (X + I)`
     *          I is your input amount of source tokens
     *          X is the balance of the pool in the source token
     *          Y is the balance of the pool in the target token
     */
    function estimateConvertWithReserves(
        uint256 sourceReserve,
        uint256 amountInSourceTokens,
        uint256 targetReserve
    ) internal pure returns (uint256) {
        return (targetReserve * amountInSourceTokens) / (sourceReserve + amountInSourceTokens);
    }

    function retrieveReservesInSourceTargetOrder(address source, address target)
        internal
        view
        returns (
            uint112 targetReserve,
            uint112 sourceReserve,
            bool token0IsTarget
        )
    {
        // Initially assume that token0 == target and token1 == source
        address targetToken = swapPair.token0();
        address sourceToken = swapPair.token1();
        (targetReserve, sourceReserve, ) = swapPair.getReserves();
        token0IsTarget = true;

        if (targetToken == address(source) && sourceToken == address(target)) {
            // Swap token reserves if necessary.
            (targetReserve, sourceReserve) = (sourceReserve, targetReserve);
            token0IsTarget = false;
        } else if (targetToken != address(target) || sourceToken != address(source)) {
            // Received tokens that are not registered on the pair.
            revert(Errors.DC_UNSUPPORTED_PAIR);
        }
    }
}
