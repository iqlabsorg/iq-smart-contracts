// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;
import "./interfaces/ILoanCostEstimator.sol";
import "./Enterprise.sol";
import "hardhat/console.sol";

contract DefaultLoanCostEstimator is ILoanCostEstimator {
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

        console.log("AVAIL", availableReserve);

        uint256 basePrice = _enterprise.getServiceBaseRate(powerToken);
        console.log("BASE", basePrice);
        uint256 lambda = _serviceLambda[powerToken];
        console.log("L", lambda);

        uint256 price = (g(amount, lambda) * basePrice * duration) >> 64;

        return uint112(price);
    }

    function f(uint128 x, uint256 lambda) internal view returns (uint256) {
        console.log("LOG", x, uint128(log_2(int128(x))));
        return ONE + ((lambda * uint128(log_2(int128(x)))) >> 64);
    }

    function h(uint256 x, uint256 lambda) internal view returns (uint256) {
        uint256 reserve = _enterprise.getReserve();

        console.log("H", x);

        return (x * f(uint128((reserve << 64) / ((reserve - x))), lambda)) >> 64;
    }

    function g(uint256 x, uint256 lambda) internal view returns (uint256) {
        uint256 usedReserve = _enterprise.getReserve() - _enterprise.getAvailableReserve();

        return h(usedReserve + x, lambda) - h(usedReserve, lambda);
    }

    function log_2(int128 x) internal pure returns (int128) {
        unchecked {
            require(x > 0);

            int256 msb = 0;
            int256 xc = x;
            if (xc >= 0x10000000000000000) {
                xc >>= 64;
                msb += 64;
            }
            if (xc >= 0x100000000) {
                xc >>= 32;
                msb += 32;
            }
            if (xc >= 0x10000) {
                xc >>= 16;
                msb += 16;
            }
            if (xc >= 0x100) {
                xc >>= 8;
                msb += 8;
            }
            if (xc >= 0x10) {
                xc >>= 4;
                msb += 4;
            }
            if (xc >= 0x4) {
                xc >>= 2;
                msb += 2;
            }
            if (xc >= 0x2) msb += 1; // No need to shift xc anymore

            int256 result = (msb - 64) << 64;
            uint256 ux = uint256(int256(x)) << uint256(127 - msb);
            for (int256 bit = 0x8000000000000000; bit > 0; bit >>= 1) {
                ux *= ux;
                uint256 b = ux >> 255;
                ux >>= 127 + b;
                result += bit * int256(b);
            }

            return int128(result);
        }
    }

    function notifyNewLoan(uint256 tokenId) external override {}
}
