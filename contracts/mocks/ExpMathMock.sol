// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../math/ExpMath.sol";

contract ExpMathMock {
    uint112 public result;
    uint256 public gas;

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

    function halfLife(
        uint32 t0,
        uint112 c0,
        uint32 t12,
        uint32 t
    ) public pure returns (uint112) {
        return ExpMath.halfLife(t0, c0, t12, t);
    }
}
