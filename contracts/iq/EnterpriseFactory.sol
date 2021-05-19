// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IEnterprise.sol";

contract EnterpriseFactory {
    using Clones for address;

    event EnterpriseDeployed(
        address indexed creator,
        address indexed liquidityToken,
        string name,
        string baseUri,
        address deployed
    );

    address private immutable _enterpriseImpl;
    address private immutable _powerTokenImpl;
    address private immutable _interestTokenImpl;
    address private immutable _borrowTokenImpl;

    constructor(
        address enterpriseImpl,
        address powerTokenImpl,
        address interestTokenImpl,
        address borrowTokenImpl
    ) {
        require(enterpriseImpl != address(0), "Invalid Enterprise address");
        require(powerTokenImpl != address(0), "Invalid PowerToken address");
        require(interestTokenImpl != address(0), "Invalid InterestToken address");
        require(borrowTokenImpl != address(0), "Invalid BorrowToken address");
        _enterpriseImpl = enterpriseImpl;
        _powerTokenImpl = powerTokenImpl;
        _interestTokenImpl = interestTokenImpl;
        _borrowTokenImpl = borrowTokenImpl;
    }

    function deploy(
        string calldata name,
        address liquidityToken,
        string calldata baseUri
    ) external {
        IEnterprise enterprise = IEnterprise(_enterpriseImpl.clone());
        enterprise.initialize(name, liquidityToken, baseUri, _interestTokenImpl, _powerTokenImpl, _borrowTokenImpl, msg.sender);

        emit EnterpriseDeployed(msg.sender, liquidityToken, name, baseUri, address(enterprise));
    }

    function getEnterpriseImpl() external view returns (address) {
        return _enterpriseImpl;
    }

    function getPowerTokenImpl() external view returns (address) {
        return _powerTokenImpl;
    }

    function getInterestTokenImpl() external view returns (address) {
        return _interestTokenImpl;
    }

    function getBorrowTokenImpl() external view returns (address) {
        return _borrowTokenImpl;
    }
}
