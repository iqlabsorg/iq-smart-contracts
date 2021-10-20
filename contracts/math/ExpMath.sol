// SPDX-License-Identifier: MIT
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
}
