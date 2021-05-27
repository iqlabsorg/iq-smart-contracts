// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IEnterprise.sol";
import "./DefaultLoanCostEstimator.sol";
import "./DefaultConverter.sol";

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
    address private immutable _configuratorImpl;

    constructor(
        address enterpriseImpl,
        address powerTokenImpl,
        address interestTokenImpl,
        address borrowTokenImpl,
        address configuratorImpl
    ) {
        require(enterpriseImpl != address(0), "Invalid Enterprise address");
        require(powerTokenImpl != address(0), "Invalid PowerToken address");
        require(interestTokenImpl != address(0), "Invalid InterestToken address");
        require(borrowTokenImpl != address(0), "Invalid BorrowToken address");
        require(configuratorImpl != address(0), "Invalid Configurator address");
        _enterpriseImpl = enterpriseImpl;
        _powerTokenImpl = powerTokenImpl;
        _interestTokenImpl = interestTokenImpl;
        _borrowTokenImpl = borrowTokenImpl;
        _configuratorImpl = configuratorImpl;
    }

    function deploy(
        string calldata name,
        IERC20Detailed liquidityToken,
        string calldata baseUri,
        uint32 borrowerLoanReturnGracePeriod,
        uint32 enterpriseLoanCollectGracePeriod,
        ILoanCostEstimator estimator,
        IConverter converter
    ) external returns (IEnterprise) {
        IEnterprise enterprise = IEnterprise(_enterpriseImpl.clone());
        string memory symbol = liquidityToken.symbol();

        EnterpriseConfigurator configurator = EnterpriseConfigurator(_configuratorImpl.clone());
        {
            // scope to avoid stack too deep error
            IInterestToken interestToken = deployInterestToken(symbol);
            IBorrowToken borrowToken = deployBorrowToken(symbol, baseUri, configurator, enterprise);

            configurator.initialize(enterprise, liquidityToken, interestToken, borrowToken, msg.sender);
        }
        {
            // scope to avoid stack too deep error
            configurator.initialize2(
                _powerTokenImpl,
                borrowerLoanReturnGracePeriod,
                enterpriseLoanCollectGracePeriod,
                estimator,
                converter
            );
        }
        enterprise.initialize(name, configurator);

        estimator.initialize(enterprise);

        emit EnterpriseDeployed(msg.sender, address(liquidityToken), name, baseUri, address(enterprise));

        return enterprise;
    }

    function deployInterestToken(string memory symbol) internal returns (IInterestToken) {
        string memory interestTokenName = string(abi.encodePacked("Interest Bearing ", symbol));
        string memory interestTokenSymbol = string(abi.encodePacked("i", symbol));

        IInterestToken interestToken = IInterestToken(_interestTokenImpl.clone());
        interestToken.initialize(interestTokenName, interestTokenSymbol);
        return interestToken;
    }

    function deployBorrowToken(
        string memory symbol,
        string memory baseUri,
        EnterpriseConfigurator configurator,
        IEnterprise enterprise
    ) internal returns (IBorrowToken) {
        string memory borrowTokenName = string(abi.encodePacked("Borrow ", symbol));
        string memory borrowTokenSymbol = string(abi.encodePacked("b", symbol));

        IBorrowToken borrowToken = IBorrowToken(_borrowTokenImpl.clone());
        borrowToken.initialize(borrowTokenName, borrowTokenSymbol, baseUri, configurator, enterprise);
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
