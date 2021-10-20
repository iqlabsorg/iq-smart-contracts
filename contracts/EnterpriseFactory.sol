// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility loans
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Lend long and prosper!

pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IEnterprise.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IPowerToken.sol";
import "./libs/Errors.sol";

contract EnterpriseFactory {
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
        require(enterpriseImpl != address(0), Errors.EF_INVALID_ENTERPRISE_IMPLEMENTATION_ADDRESS);
        require(powerTokenImpl != address(0), Errors.EF_INVALID_POWER_TOKEN_IMPLEMENTATION_ADDRESS);
        require(interestTokenImpl != address(0), Errors.EF_INVALID_INTEREST_TOKEN_IMPLEMENTATION_ADDRESS);
        require(borrowTokenImpl != address(0), Errors.EF_INVALID_BORROW_TOKEN_IMPLEMENTATION_ADDRESS);
        _enterpriseImpl = enterpriseImpl;
        _powerTokenImpl = powerTokenImpl;
        _interestTokenImpl = interestTokenImpl;
        _borrowTokenImpl = borrowTokenImpl;
    }

    function deploy(
        string calldata name,
        IERC20Metadata liquidityToken,
        string calldata baseUri,
        uint16 gcFeePercent,
        IConverter converter
    ) external returns (IEnterprise) {
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        IEnterprise enterprise = IEnterprise(deployProxy(_enterpriseImpl, proxyAdmin));
        proxyAdmin.transferOwnership(address(enterprise));
        {
            enterprise.initialize(name, baseUri, gcFeePercent, converter, proxyAdmin, msg.sender);
        }
        {
            IInterestToken interestToken = _deployInterestToken(liquidityToken.symbol(), enterprise, proxyAdmin);
            IBorrowToken borrowToken = _deployBorrowToken(liquidityToken.symbol(), enterprise, proxyAdmin);
            enterprise.initializeTokens(liquidityToken, interestToken, borrowToken);
        }

        emit EnterpriseDeployed(msg.sender, address(liquidityToken), name, baseUri, address(enterprise));

        return enterprise;
    }

    function deployProxy(address implementation, ProxyAdmin admin) internal returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, address(admin), ""));
    }

    function deployService(ProxyAdmin admin) external returns (IPowerToken) {
        return IPowerToken(deployProxy(_powerTokenImpl, admin));
    }

    function _deployInterestToken(
        string memory symbol,
        IEnterprise enterprise,
        ProxyAdmin proxyAdmin
    ) internal returns (IInterestToken) {
        string memory interestTokenName = string(abi.encodePacked("Interest Bearing ", symbol));
        string memory interestTokenSymbol = string(abi.encodePacked("i", symbol));

        IInterestToken interestToken = IInterestToken(deployProxy(_interestTokenImpl, proxyAdmin));
        interestToken.initialize(interestTokenName, interestTokenSymbol, enterprise);
        return interestToken;
    }

    function _deployBorrowToken(
        string memory symbol,
        IEnterprise enterprise,
        ProxyAdmin proxyAdmin
    ) internal returns (IBorrowToken) {
        string memory borrowTokenName = string(abi.encodePacked("Borrow ", symbol));
        string memory borrowTokenSymbol = string(abi.encodePacked("b", symbol));

        IBorrowToken borrowToken = IBorrowToken(deployProxy(_borrowTokenImpl, proxyAdmin));
        borrowToken.initialize(borrowTokenName, borrowTokenSymbol, enterprise);
        return borrowToken;
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
