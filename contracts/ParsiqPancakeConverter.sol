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
    IUniswapV2Factory private immutable _uniswapfactory;
    uint256 private immutable _swapFee;
    uint256 private immutable _feeBase;

    /**
     * @notice Constructor for `ParsiqPancakeConverter`
     * @param uniswapRouter - UniswapV2 router implementation. On BSC that would be Pancakeswap.
     * @param allowedTokenOne - The ERC20 token that's used for finding the swap pair
     * @param allowedTargetTwo - The ERC20 token that's used for finding the swap pair
     * @param swapFee - What fee does the exchange charge for a swap.
     * @param feeBase - What fee does the exchange charge for a swap.
     * @dev The token pair must be pre-deployed and registered on the router!
     * @dev The contract will find the existing token pair.
     *
     * @dev `swapFee` and `feeBase` table:
     *          - PancakeSwap: swapFee (uint256 9975); feeBase (uint256 10000) - 0.0025%
     *          - UniSwap: swapFee (uint256 997); feeBase (uint256 1000) - 0.003%
     */
    constructor(
        IUniswapV2Router02 uniswapRouter,
        IERC20 allowedTokenOne,
        IERC20 allowedTargetTwo,
        uint256 swapFee,
        uint256 feeBase
    ) {
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());
        swapPair = IUniswapV2Pair(uniswapFactory.getPair(address(allowedTokenOne), address(allowedTargetTwo)));

        _uniswapRouter = uniswapRouter;
        _uniswapfactory = uniswapFactory;

        _swapFee = swapFee;
        _feeBase = feeBase;
    }

    /**
     * @notice Perform estimation of how many `target` tokens are necessary to cover required amount of `source` tokens.
     * @param source - the source token address (e.g. stablecoin)
     * @param target - the target token address (e.g. volatile coin)
     * @param amountInSourceTokens - the amount of source token price
     * @dev Source and target token addresses must be the exact ones as specified in the constructor of this contract.
     */
    function estimateConvert(
        IERC20 source,
        uint256 amountInSourceTokens,
        IERC20 target
    ) public view override returns (uint256) {
        if (address(source) == address(target)) return amountInSourceTokens;
        (uint112 sourceReserve, uint112 targetReserve) = retrieveReservesInSourceTargetOrder(
            address(source),
            address(target)
        );

        return estimateConvertForTrade(sourceReserve, amountInSourceTokens, targetReserve);
    }

    /**
     * @notice Convert source tokens to target tokens as specified in `amountInSourceTokens`.
     * @dev A guaranteed amount of `amountInSourceTokens` will get converted to a volatile amount of targe tokens.
     * @dev msg.sender needs to give allowance to the converter (this contract) of `source tokens`
     *      for the amount of `amountInSourceTokens`.
     */
    function convert(
        IERC20 source,
        uint256 amountInSourceTokens,
        IERC20 target
    ) external override returns (uint256) {
        if (address(source) == address(target)) return amountInSourceTokens;

        // 0. (must be done before) Approve: msg.sender -> converter
        // 1. Transfer: msg.sender -> converter
        // 2. Approve: converter -> uniswap router
        IERC20(source).transferFrom(msg.sender, address(this), amountInSourceTokens);
        IERC20(source).approve(address(_uniswapRouter), amountInSourceTokens);

        // https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair#swap-1
        address[] memory path = new address[](2);
        path[0] = address(source);
        path[1] = address(target);

        uint256 amountInTargetTokens = estimateConvert(source, amountInSourceTokens, target);

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
     * @notice Copy of Uniswaps UniswapV2Library.getAmountOut()
     * @dev this library gets used internally by Uniswap to estimate swapping thresholds
     * @dev Other calculation methods will most likely fail - as an error returned by Uniswap.
     * @dev Cannot use the original library because of solidity version mis-match and misleading pragma for it.
     * @dev Will use contracts configured swap fee for more accurate estimation.
     */
    function estimateConvertForTrade(
        uint256 sourceReserve,
        uint256 amountInSourceTokens,
        uint256 targetReserve
    ) internal view returns (uint256) {
        uint256 amountInWithFee = amountInSourceTokens * _swapFee;
        uint256 numerator = amountInWithFee * targetReserve;
        uint256 denominator = sourceReserve * _feeBase + amountInWithFee;
        return numerator / denominator;
    }

    /**
     * @notice Return source and target reserves in order as the passed in parameters.
     * @dev Will revert if one of the tokens has not been registered in the constructor.
     */
    function retrieveReservesInSourceTargetOrder(address source, address target)
        internal
        view
        returns (uint112 sourceReserve, uint112 targetReserve)
    {
        // Initially assume that token0 == target and token1 == source
        address targetToken = swapPair.token0();
        address sourceToken = swapPair.token1();
        (targetReserve, sourceReserve, ) = swapPair.getReserves();

        if (targetToken == address(source) && sourceToken == address(target)) {
            // Swap token reserves if necessary.
            (targetReserve, sourceReserve) = (sourceReserve, targetReserve);
        } else if (targetToken != address(target) || sourceToken != address(source)) {
            // Received tokens that are not registered on the pair.
            revert(Errors.DC_UNSUPPORTED_PAIR);
        }
    }
}
