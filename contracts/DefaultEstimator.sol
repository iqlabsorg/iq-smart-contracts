// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;
import "./interfaces/IEstimator.sol";
import "./math/ExpMath.sol";
import "./Enterprise.sol";

contract DefaultEstimator is IEstimator {
    uint256 internal constant ONE = 1 << 64;

    Enterprise private _enterprise;
    mapping(IPowerToken => uint256) private _serviceLambda;

    modifier onlyOwner() {
        require(msg.sender == _enterprise.owner(), "Not an owner");
        _;
    }

    function initialize(Enterprise enterprise) external override {
        require(address(enterprise) != address(0), "Zero address");
        require(address(_enterprise) == address(0), "Already initialized");

        _enterprise = enterprise;
    }

    function initializeService(IPowerToken powerToken) external override {
        require(address(_enterprise) != address(0), "Not initialized");
        require(_enterprise.isRegisteredPowerToken(powerToken), "Unknown Power Token");
        _serviceLambda[powerToken] = ONE;
    }

    function setLambda(IPowerToken powerToken, uint256 lambda) external onlyOwner {
        require(lambda > 0, "Cannot be zero");
        _serviceLambda[powerToken] = lambda;
    }

    /**
     * @dev
     * f(x) = 1 - λln(x)
     * h(x) = x * f((T - x) / T)
     * g(x) = h(U + x) - h(U)
     */
    function estimateCost(
        IPowerToken powerToken,
        uint112 amount,
        uint32 duration
    ) external view override returns (uint112) {
        uint256 availableReserve = _enterprise.getAvailableReserve();
        if (availableReserve <= amount) return type(uint112).max;

        uint256 basePrice = _enterprise.getServiceBaseRate(powerToken);
        uint256 lambda = _serviceLambda[powerToken];

        uint256 price = (g(amount, lambda) * basePrice * duration) >> 64;

        return uint112(price);
    }

    function f(uint128 x, uint256 lambda) internal pure returns (uint256) {
        return ONE + ((lambda * uint128(ExpMath.log_2(int128(x)))) >> 64);
    }

    function h(
        uint256 x,
        uint256 lambda,
        uint256 reserve
    ) internal pure returns (uint256) {
        return (x * f(uint128((reserve << 64) / ((reserve - x))), lambda)) >> 64;
    }

    function g(uint256 x, uint256 lambda) internal view returns (uint256) {
        uint256 usedReserve = _enterprise.getUsedReserve();
        uint256 reserve = _enterprise.getReserve();

        return h(usedReserve + x, lambda, reserve) - h(usedReserve, lambda, reserve);
    }

    function notifyNewLoan(uint256 tokenId) external override {}
}
