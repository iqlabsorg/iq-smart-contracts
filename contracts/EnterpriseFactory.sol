// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Enterprise.sol";
import "./interfaces/IEstimator.sol";
import "./interfaces/IConverter.sol";
import "./InterestToken.sol";
import "./BorrowToken.sol";

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
        IERC20Metadata liquidityToken,
        string calldata baseUri,
        address estimatorImpl,
        IConverter converter
    ) external returns (Enterprise) {
        Enterprise enterprise = Enterprise(_enterpriseImpl.clone());
        IEstimator estimator = IEstimator(estimatorImpl.clone());

        InterestToken interestToken = _deployInterestToken(liquidityToken.symbol(), enterprise);
        BorrowToken borrowToken = _deployBorrowToken(liquidityToken.symbol(), enterprise);

        enterprise.initialize(name, baseUri, estimator, converter, msg.sender);
        enterprise.initializeTokens(_powerTokenImpl, liquidityToken, interestToken, borrowToken);

        estimator.initialize(enterprise);

        emit EnterpriseDeployed(msg.sender, address(liquidityToken), name, baseUri, address(enterprise));

        return enterprise;
    }

    function _deployInterestToken(string memory symbol, Enterprise enterprise) internal returns (InterestToken) {
        string memory interestTokenName = string(abi.encodePacked("Interest Bearing ", symbol));
        string memory interestTokenSymbol = string(abi.encodePacked("i", symbol));

        InterestToken interestToken = InterestToken(_interestTokenImpl.clone());
        interestToken.initialize(interestTokenName, interestTokenSymbol, enterprise);
        return interestToken;
    }

    function _deployBorrowToken(string memory symbol, Enterprise enterprise) internal returns (BorrowToken) {
        string memory borrowTokenName = string(abi.encodePacked("Borrow ", symbol));
        string memory borrowTokenSymbol = string(abi.encodePacked("b", symbol));

        BorrowToken borrowToken = BorrowToken(_borrowTokenImpl.clone());
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
