// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
import "../libs/Errors.sol";

library ExpMath {
    uint256 private constant ONE = 1 << 144;
    uint256 private constant LOG_ONE_HALF = 15457698658747239244624307340191628289589491; // log(0.5) * 2 ** 144

    function halfLife(
        uint32 t0,
        uint112 c0,
        uint32 t12,
        uint32 t
    ) internal pure returns (uint112) {
        unchecked {
            require(t >= t0, Errors.EXP_INVALID_PERIOD);

            t -= t0;
            c0 >>= t / t12;
            t %= t12;
            if (t == 0 || c0 == 0) return c0;

            uint256 sum = 0;
            uint256 z = c0;
            uint256 x = (LOG_ONE_HALF * t) / t12;
            uint256 i = ONE;

            while (z != 0) {
                sum += z;
                z = (z * x) / i;
                i += ONE;
                sum -= z;
                z = (z * x) / i;
                i += ONE;
            }

            return uint112(sum);
        }
    }

    /**
     * @dev Credit to ABDK Consulting under BSD-4 license https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e
     */
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
}
