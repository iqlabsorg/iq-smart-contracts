// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility renting
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Stake strong!

pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IConverter.sol";
import "./libs/Errors.sol";
import "./libs/uniswap-v2/IUniswapV2Router02.sol";
import "./libs/uniswap-v2/IUniswapV2Pair.sol";
import "./libs/uniswap-v2/IUniswapV2Factory.sol";

/**
 * Pancakeswap converter for estimating token prices.
 */
contract ParsiqPancakeConverter is IConverter {
    IUniswapV2Pair public swapPair;
    IUniswapV2Router02 private _uniswapRouter;

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
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(_uniswapRouter.factory());
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
    ) external view override returns (uint256) {
        address pairToken0 = swapPair.token0();
        address pairToken1 = swapPair.token1();

        // Initially assume that token0 == target and token1 == source
        (uint112 targetReserve, uint112 sourceReserve, ) = swapPair.getReserves();

        if (pairToken0 == address(source) && pairToken1 == address(target)) {
            // Swap token reserves if necessary.
            (targetReserve, sourceReserve) = (sourceReserve, targetReserve);
        } else if (pairToken0 != address(target) || pairToken1 != address(source)) {
            // Received tokens that are not registered on the pair.
            revert(Errors.DC_UNSUPPORTED_PAIR);
        }

        return estimateConvertWithReserves(sourceReserve, amountInSourceTokens, targetReserve);
    }

    /**
     * @notice Noop converter. Reverts if `source` and `target` tokens differ.
     */
    function convert(
        IERC20 source,
        uint256 amountInSourceTokens,
        IERC20 target
    ) external pure override returns (uint256) {
        require(address(source) == address(target), Errors.DC_UNSUPPORTED_PAIR);
        return amountInSourceTokens;
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
}
