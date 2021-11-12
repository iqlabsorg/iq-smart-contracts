// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility renting
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Stake strong!

pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IEnterprise.sol";
import "./interfaces/IStakeToken.sol";
import "./interfaces/IRentalToken.sol";
import "./interfaces/IPowerToken.sol";
import "./libs/Errors.sol";

contract EnterpriseFactory {
    event EnterpriseDeployed(
        address indexed creator,
        address indexed enterpriseToken,
        string name,
        string baseUri,
        address deployed
    );

    address private immutable _enterpriseImpl;
    address private immutable _powerTokenImpl;
    address private immutable _stakeTokenImpl;
    address private immutable _rentalTokenImpl;

    constructor(
        address enterpriseImpl,
        address powerTokenImpl,
        address stakeTokenImpl,
        address rentalTokenImpl
    ) {
        require(enterpriseImpl != address(0), Errors.EF_INVALID_ENTERPRISE_IMPLEMENTATION_ADDRESS);
        require(powerTokenImpl != address(0), Errors.EF_INVALID_POWER_TOKEN_IMPLEMENTATION_ADDRESS);
        require(stakeTokenImpl != address(0), Errors.EF_INVALID_STAKE_TOKEN_IMPLEMENTATION_ADDRESS);
        require(rentalTokenImpl != address(0), Errors.EF_INVALID_RENTAL_TOKEN_IMPLEMENTATION_ADDRESS);
        _enterpriseImpl = enterpriseImpl;
        _powerTokenImpl = powerTokenImpl;
        _stakeTokenImpl = stakeTokenImpl;
        _rentalTokenImpl = rentalTokenImpl;
    }

    function deploy(
        string calldata name,
        IERC20Metadata enterpriseToken,
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
            IStakeToken stakeToken = _deployStakeToken(enterpriseToken.symbol(), enterprise, proxyAdmin);
            IRentalToken rentalToken = _deployRentalToken(enterpriseToken.symbol(), enterprise, proxyAdmin);
            enterprise.initializeTokens(enterpriseToken, stakeToken, rentalToken);
        }

        emit EnterpriseDeployed(msg.sender, address(enterpriseToken), name, baseUri, address(enterprise));

        return enterprise;
    }

    function deployProxy(address implementation, ProxyAdmin admin) internal returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, address(admin), ""));
    }

    function deployService(ProxyAdmin admin) external returns (IPowerToken) {
        return IPowerToken(deployProxy(_powerTokenImpl, admin));
    }

    function _deployStakeToken(
        string memory symbol,
        IEnterprise enterprise,
        ProxyAdmin proxyAdmin
    ) internal returns (IStakeToken) {
        string memory stakeTokenName = string(abi.encodePacked("Staking ", symbol));
        string memory stakeTokenSymbol = string(abi.encodePacked("s", symbol));

        IStakeToken stakeToken = IStakeToken(deployProxy(_stakeTokenImpl, proxyAdmin));
        stakeToken.initialize(stakeTokenName, stakeTokenSymbol, enterprise);
        return stakeToken;
    }

    function _deployRentalToken(
        string memory symbol,
        IEnterprise enterprise,
        ProxyAdmin proxyAdmin
    ) internal returns (IRentalToken) {
        string memory rentalTokenName = string(abi.encodePacked("Rental ", symbol));
        string memory rentalTokenSymbol = string(abi.encodePacked("r", symbol));

        IRentalToken rentalToken = IRentalToken(deployProxy(_rentalTokenImpl, proxyAdmin));
        rentalToken.initialize(rentalTokenName, rentalTokenSymbol, enterprise);
        return rentalToken;
    }

    function getEnterpriseImpl() external view returns (address) {
        return _enterpriseImpl;
    }

    function getPowerTokenImpl() external view returns (address) {
        return _powerTokenImpl;
    }

    function getStakeTokenImpl() external view returns (address) {
        return _stakeTokenImpl;
    }

    function getRentalTokenImpl() external view returns (address) {
        return _rentalTokenImpl;
    }
}
