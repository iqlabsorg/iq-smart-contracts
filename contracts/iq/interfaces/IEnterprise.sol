// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

interface IEnterprise {
    function initialize(
        string memory _name,
        address _liquidityToken,
        string memory _baseUri,
        address _interestTokenImpl,
        address _powerTokenImpl
    ) external;
}
