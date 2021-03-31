// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "../iq/ExpMath.sol";

contract ExpMathMock {
    uint112 public result;
    uint256 public gas;

    function halfLife(
        uint32 t0,
        uint112 c0,
        uint32 t12,
        uint32 t
    ) public pure returns (uint112) {
        return ExpMath.halfLife(t0, c0, t12, t);
    }

    function measure(
        uint32 t0,
        uint112 c0,
        uint32 t12,
        uint32 t
    ) public {
        uint256 tgas = gasleft();
        uint112 tmp = halfLife(t0, c0, t12, t);
        gas = tgas - gasleft();
        result = tmp;
    }
}
