// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

interface IInitializableOwnable {
    function initialize(address initialOwner) external;

    function owner() external view returns (address);
}
