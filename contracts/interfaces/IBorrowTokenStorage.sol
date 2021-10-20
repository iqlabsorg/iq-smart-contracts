// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IEnterprise.sol";

interface IBorrowTokenStorage {
    function initialize(
        string memory name,
        string memory symbol,
        IEnterprise enterprise
    ) external;
}
