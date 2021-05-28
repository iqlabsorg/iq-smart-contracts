// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;
import "./interfaces/ILoanCostEstimator.sol";
import "./interfaces/IEnterprise.sol";
import "hardhat/console.sol";

contract DefaultLoanCostEstimator is ILoanCostEstimator {
    IEnterprise private _enterprise;

    function initialize(IEnterprise enterprise) external override {
        require(address(enterprise) != address(0), "Zero address");
        require(address(_enterprise) == address(0), "Already initialized");

        _enterprise = enterprise;
    }

    // y = (1 / (2 * log(2, ((100 - 5) / (100 - x)))) + 1) * 100, x = 5 to 100
    function estimateCost(
        IPowerToken powerToken,
        uint112 amount,
        uint32 duration
    ) external view override returns (uint112) {
        uint256 availableReserve = _enterprise.getAvailableReserve();
        if (availableReserve <= amount) return type(uint112).max;

        EnterpriseConfigurator configurator = _enterprise.getConfigurator();
        uint256 basePrice = (uint256(amount) * duration * configurator.getBaseRate(powerToken));
        console.log("BASE", basePrice);

        uint256 reserve = _enterprise.getReserve();

        uint256 R0 = uint256(5 << 64) / 100; // 5% in 64 bits
        uint256 ONE = uint256(1 << 64);
        uint256 LAMBDA = uint256(2 << 64);

        uint256 X = ((availableReserve - amount) << 64) / reserve;
        if (X < R0) {
            X = R0;
        }

        console.log("X   ", X);
        console.log("ONE ", ONE);
        console.log("R0  ", R0);
        console.log("O-R0", ONE - R0);
        uint128 D = (ONE - X == 0) ? uint128(type(int128).max) : uint128(((ONE - R0) << 64) / (ONE - X));
        console.log("D   ", D);

        int128 F = log_2(int128(D));
        console.log("F   ", uint128(F));
        uint256 LAMBDA_F = (LAMBDA * uint256(uint128(F))) >> 64;
        console.log("LF  ", uint128(LAMBDA_F));
        uint256 DF = (ONE << 64) / LAMBDA_F;
        console.log("DF  ", DF);

        return uint112(((DF + ONE) * basePrice) >> 128);

        // uint112 effectiveK = ;

        // uint256 totalCost = uint112((uint256(amount) * duration * effectiveK));

        // loanReturnLien = totalCost * 0.05;

        // enterpriseFee = totalCost * _enterpriseFee;

        // interest = totalCost - enterpriseFee;

        // uint112 interestInLiquidityTokens = interest > type(uint112).max ? type(uint112).max : uint112(interest);

        // uint256 uintInterestInLiquidityTokens = _reserve / (_availableReserve - amount); //BONDING

        // convertTo(interestInLiquidityTokens, interestPaymentToken),

        //return uint112(reserve);
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
