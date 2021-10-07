// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "./IEnterprise.sol";

interface IInterestTokenStorage {
    function initialize(
        string memory name,
        string memory symbol,
        IEnterprise enterprise
    ) external;
}
