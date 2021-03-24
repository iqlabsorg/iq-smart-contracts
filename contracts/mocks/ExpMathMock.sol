// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import '../iq/ExpMath.sol';

contract ExpMathMock {
    uint256 public result;
    uint256 public gas;

    function halfLife(
        uint256 t0,
        uint256 c0,
        uint256 t12,
        uint256 t
    ) public pure returns (uint256) {
        return ExpMath.halfLife(t0, c0, t12, t);
    }

    function measure(
        uint256 t0,
        uint256 c0,
        uint256 t12,
        uint256 t
    ) public {
        uint256 tgas = gasleft();
        uint256 tmp = halfLife(t0, c0, t12, t);
        gas = tgas - gasleft();
        result = tmp;
    }
}
