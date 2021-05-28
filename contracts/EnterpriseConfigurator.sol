// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IPowerToken.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/ILoanCostEstimator.sol";
import "./interfaces/IConverter.sol";
import "./InitializableOwnable.sol";

/**
 * @dev Contract which holds configuration parameters for Enterprise
 * To prevent Enterprise from front-running it's users, it is supposed to be owned by some
 * Governance system. For example OpenZeppelin `TimelockController` contract can
 * be used as an `owner` of this contract
 */
contract EnterpriseConfigurator is InitializableOwnable {
    uint16 private constant MAX_SERVICE_FEE_PERCENT = 5000; // 50%

    struct ServiceConfig {
        // 1 slot
        uint112 baseRate; // base rate for price calculations, nominated in baseToken
        uint112 minGCFee; // fee for collecting expired PowerTokens
        uint32 halfLife; // fixed, not changeable
        // 2 slot
        IERC20Metadata baseToken;
        uint32 minLoanDuration;
        uint32 maxLoanDuration;
        uint16 serviceFeePercent; // 100 is 1%, 10_000 is 100%. Fee which goes to the enterprise to cover service operational costs for this service
    }

    IEnterprise private _enterprise;
    /**
     * @dev ERC20 token backed by enterprise services
     */
    IERC20Metadata private _liquidityToken;

    IInterestToken private _interestToken;
    /**
     * @dev ERC721 token to keep loan
     */
    IBorrowToken private _borrowToken;
    address private _powerTokenImpl;

    ILoanCostEstimator private _loanCostEstimator;
    IConverter private _converter;
    address private _enterpriseCollector;

    address private _enterpriseVault;
    uint32 private _borrowerLoanReturnGracePeriod;
    uint32 private _enterpriseLoanCollectGracePeriod;
    uint16 private _gcFeePercent; // 100 is 1%, 10_000 is 100%

    mapping(address => int16) private _paymentTokensIndex;
    address[] private _paymentTokens;

    mapping(IPowerToken => ServiceConfig) private _serviceConfig;

    modifier registeredPowerToken(IPowerToken powerToken) {
        require(isRegisteredPowerToken(powerToken), "Unknown PowerToken");
        _;
    }

    function initialize(
        IEnterprise enterprise,
        IERC20Metadata liquidityToken,
        IInterestToken interestToken,
        IBorrowToken borrowToken,
        address owner
    ) public {
        require(address(_interestToken) == address(0), "Already initialized");
        InitializableOwnable.initialize(owner);
        _enterprise = enterprise;
        _interestToken = interestToken;
        _borrowToken = borrowToken;
        _liquidityToken = liquidityToken;
        _enterpriseCollector = this.owner();
        _enterpriseVault = this.owner();
        _enablePaymentToken(address(liquidityToken));
    }

    function initialize2(
        address powerTokenImpl,
        uint32 borrowerLoanReturnGracePeriod,
        uint32 enterpriseLoanCollectGracePeriod,
        ILoanCostEstimator estimator,
        IConverter converter
    ) public {
        require(_powerTokenImpl == address(0), "Already initialized");
        require(borrowerLoanReturnGracePeriod <= enterpriseLoanCollectGracePeriod, "Invalid grace periods");
        _powerTokenImpl = powerTokenImpl;
        _borrowerLoanReturnGracePeriod = borrowerLoanReturnGracePeriod;
        _enterpriseLoanCollectGracePeriod = enterpriseLoanCollectGracePeriod;
        _loanCostEstimator = estimator;
        _converter = converter;
    }

    function setLoanCostEstimator(ILoanCostEstimator newEstimator) external onlyOwner {
        require(address(newEstimator) != address(0), "Zero address");
        _loanCostEstimator = newEstimator;
        //TODO: emit event
    }

    function isRegisteredPowerToken(IPowerToken powerToken) internal view returns (bool) {
        return _serviceConfig[powerToken].halfLife != 0;
    }

    function getLoanCostEstimator() external view returns (ILoanCostEstimator) {
        return _loanCostEstimator;
    }

    function getLiquidityToken() external view returns (IERC20Metadata) {
        return _liquidityToken;
    }

    function getInterestToken() external view returns (IInterestToken) {
        return _interestToken;
    }

    function getBorrowToken() external view returns (IBorrowToken) {
        return _borrowToken;
    }

    function supportedPaymentTokensIndex(IERC20 token) external view returns (int16) {
        return _paymentTokensIndex[address(token)] - 1;
    }

    function supportedPaymentTokens(uint256 index) external view returns (address) {
        return _paymentTokens[index];
    }

    function isSupportedPaymentToken(IERC20 token) external view returns (bool) {
        return _paymentTokensIndex[address(token)] > 0;
    }

    function getEnterpriseCollector() external view returns (address) {
        return _enterpriseCollector;
    }

    function getEnterpriseVault() external view returns (address) {
        return _enterpriseVault;
    }

    function getBorrowerLoanReturnGracePeriod() external view returns (uint32) {
        return _borrowerLoanReturnGracePeriod;
    }

    function getEnterpriseLoanCollectGracePeriod() external view returns (uint32) {
        return _enterpriseLoanCollectGracePeriod;
    }

    function getPowerTokenImpl() external view returns (address) {
        return _powerTokenImpl;
    }

    function getServiceFeePercent(IPowerToken powerToken) external view returns (uint112) {
        return _serviceConfig[powerToken].serviceFeePercent;
    }

    function getHalfLife(IPowerToken powerToken) external view returns (uint32) {
        return _serviceConfig[powerToken].halfLife;
    }

    function getConverter() external view returns (IConverter) {
        return _converter;
    }

    function setEnterpriseCollector(address newCollector) public onlyOwner {
        require(newCollector != address(0), "Zero address");
        _enterpriseCollector = newCollector;
    }

    function setEnterpriseVault(address newVault) public onlyOwner {
        require(newVault != address(0), "Zero address");
        _enterpriseVault = newVault;
    }

    function setConverter(IConverter newConverter) external onlyOwner {
        require(address(newConverter) != address(0), "Zero address");
        _converter = newConverter;
    }

    function setServiceFeePercent(IPowerToken powerToken, uint16 newFeePercent)
        public
        onlyOwner
        registeredPowerToken(powerToken)
    {
        _setServiceFeePercent(powerToken, newFeePercent);
    }

    function scheduleServiceFeePercentBatch(IPowerToken[] calldata powerToken, uint16[] calldata newServiceFeePercent)
        external
        onlyOwner
    {
        require(powerToken.length == newServiceFeePercent.length, "Invalid array length");

        for (uint256 i = 0; i < powerToken.length; i++) {
            require(isRegisteredPowerToken(powerToken[i]), "Unknown PowerToken");
            _setServiceFeePercent(powerToken[i], newServiceFeePercent[i]);
        }
    }

    function _setServiceFeePercent(IPowerToken powerToken, uint16 newServiceFeePercent) internal {
        require(newServiceFeePercent <= MAX_SERVICE_FEE_PERCENT, "Maximum service fee percent threshold");

        _serviceConfig[powerToken].serviceFeePercent = newServiceFeePercent;
        //TODO: emit event
    }

    function addService(IPowerToken powerToken, ServiceConfig memory config) public {
        require(msg.sender == address(_enterprise), "Not an enterprise");
        _serviceConfig[powerToken] = config;
    }

    function setBaseRate(
        IPowerToken powerToken,
        uint112 baseRate,
        IERC20Metadata baseToken,
        uint112 minGCFee
    ) public onlyOwner registeredPowerToken(powerToken) {
        require(address(baseToken) != address(0), "Invalid Base Token");
        ServiceConfig storage config = _serviceConfig[powerToken];

        config.baseRate = baseRate;
        config.baseToken = baseToken;
        config.minGCFee = minGCFee;
    }

    function setLoanDurationLimits(
        IPowerToken powerToken,
        uint32 minLoanDuration,
        uint32 maxLoanDuration
    ) external onlyOwner registeredPowerToken(powerToken) {
        ServiceConfig storage config = _serviceConfig[powerToken];

        config.minLoanDuration = minLoanDuration;
        config.maxLoanDuration = maxLoanDuration;
    }

    function setGcFeePercent(uint16 newGcFeePercent) external onlyOwner {
        _gcFeePercent = newGcFeePercent;
    }

    function getGCFeePercent() external view returns (uint16) {
        return _gcFeePercent;
    }

    function getBaseRate(IPowerToken powerToken) external view returns (uint112) {
        return _serviceConfig[powerToken].baseRate;
    }

    function getMinGCFee(IPowerToken powerToken) external view returns (uint112) {
        return _serviceConfig[powerToken].minGCFee;
    }

    function getBaseToken(IPowerToken powerToken) external view returns (IERC20Metadata) {
        return _serviceConfig[powerToken].baseToken;
    }

    function getMinLoanDuration(IPowerToken powerToken) external view returns (uint32) {
        return _serviceConfig[powerToken].minLoanDuration;
    }

    function getMaxLoanDuration(IPowerToken powerToken) external view returns (uint32) {
        return _serviceConfig[powerToken].maxLoanDuration;
    }

    function isAllowedLoanDuration(IPowerToken powerToken, uint32 duration) external view returns (bool) {
        ServiceConfig storage config = _serviceConfig[powerToken];
        return config.minLoanDuration <= duration && duration <= config.maxLoanDuration;
    }

    function enablePaymentToken(address token) public onlyOwner {
        require(token != address(0), "Zero address");
        _enablePaymentToken(token);
    }

    function disablePaymentToken(address token) public onlyOwner {
        _disablePaymentToken(token);
    }

    function _enablePaymentToken(address token) internal {
        if (_paymentTokensIndex[token] == 0) {
            _paymentTokens.push(token);
            _paymentTokensIndex[token] = int16(uint16(_paymentTokens.length));
        } else if (_paymentTokensIndex[token] < 0) {
            _paymentTokensIndex[token] = -_paymentTokensIndex[token];
        }
    }

    function _disablePaymentToken(address token) internal {
        require(_paymentTokensIndex[token] != 0, "Invalid token");

        if (_paymentTokensIndex[token] > 0) {
            _paymentTokensIndex[token] = -_paymentTokensIndex[token];
        }
    }
}
