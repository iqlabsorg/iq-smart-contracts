// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "./IOwnable.sol";

interface IInitializableOwnable is IOwnable {
    function initialize(address initialOwner) external;
}
