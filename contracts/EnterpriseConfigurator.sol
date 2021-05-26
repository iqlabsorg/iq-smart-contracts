// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "./interfaces/IPowerToken.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/ILoanCostEstimator.sol";
import "./interfaces/IConverter.sol";
import "./token/IERC20Detailed.sol";
import "./InitializableOwnable.sol";

contract EnterpriseConfigurator is InitializableOwnable {
    uint32 private constant ENTERPRISE_CONFIG_CHANGE_MINIMUM_GRACE_PERIOD = 24 hours;
    uint16 private constant MAX_ENTERPRISE_FEE = 5000; // 50%

    struct ServiceConfig {
        // 1 slot
        uint112 factor;
        uint32 halfLife;
        uint16 serviceFee; // 100 is 1%, fee which goes to the enterprise on each loan to cover service operational costs
        uint16 previousServiceFee;
        // 2 slot
        IERC20 factorToken;
        uint32 serviceFeeChangeTime;
        uint32 minLoanPeriod;
        uint32 maxLoanPeriod;
    }

    /**
     * @dev ERC20 token backed by enterprise services
     */
    IERC20Detailed private _liquidityToken;

    IInterestToken private _interestToken;
    /**
     * @dev ERC721 token to keep loan
     */
    IBorrowToken private _borrowToken;
    address private _powerTokenImpl;
    IEnterprise private _enterprise;

    ILoanCostEstimator private _loanCostEstimator;
    ILoanCostEstimator private _previousLoanCostEstimator;
    IConverter private _converter;
    address private _enterpriseCollector;
    uint32 private _enterpriseConfigChangeGracePeriod = ENTERPRISE_CONFIG_CHANGE_MINIMUM_GRACE_PERIOD;
    uint32 private _loanCostEstimatorChangeTime;

    address private _enterpriseVault;
    uint32 private _borrowerLoanReturnGracePeriod;
    uint32 private _enterpriseLoanCollectGracePeriod;

    mapping(address => int16) private _supportedPaymentTokensIndex;
    address[] private _supportedPaymentTokens;

    mapping(IPowerToken => ServiceConfig) serviceConfig;

    modifier registeredPowerToken(IPowerToken powerToken) {
        require(isRegisteredPowerToken(powerToken), "Unknown PowerToken");
        _;
    }

    function isRegisteredPowerToken(IPowerToken powerToken) internal view returns (bool) {
        return serviceConfig[powerToken].halfLife != 0;
    }

    function initialize(
        IEnterprise enterprise,
        IERC20Detailed liquidityToken,
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

    function getConfig()
        external
        view
        returns (
            address loanEstimator,
            address previousEstimator,
            uint32 loanEstimatorChangeTime
        )
    {
        return (address(_loanCostEstimator), address(_previousLoanCostEstimator), _loanCostEstimatorChangeTime);
    }

    function setEnterpriseFeeGracePeriod(uint32 newPeriod) public onlyOwner {
        _enterpriseConfigChangeGracePeriod = newPeriod;
    }

    function scheduleLoanCostEstimator(ILoanCostEstimator newEstimator) external onlyOwner {
        require(address(newEstimator) != address(0), "Zero address");
        if (_loanCostEstimatorChangeTime <= block.timestamp) {
            _previousLoanCostEstimator = _loanCostEstimator;
        }
        _loanCostEstimator = newEstimator;
        _loanCostEstimatorChangeTime = uint32(block.timestamp) + _enterpriseConfigChangeGracePeriod;

        //TODO: emit event
    }

    function getLoanCostEstimator() public view returns (ILoanCostEstimator) {
        if (block.timestamp < _loanCostEstimatorChangeTime) return _previousLoanCostEstimator;

        return _loanCostEstimator;
    }

    function getLiquidityToken() external view returns (IERC20Detailed) {
        return _liquidityToken;
    }

    function getInterestToken() external view returns (IInterestToken) {
        return _interestToken;
    }

    function getBorrowToken() external view returns (IBorrowToken) {
        return _borrowToken;
    }

    function supportedPaymentTokensIndex(IERC20 token) external view returns (int16) {
        return _supportedPaymentTokensIndex[address(token)] - 1;
    }

    function supportedPaymentTokens(uint256 index) external view returns (address) {
        return _supportedPaymentTokens[index];
    }

    function isSupportedPaymentToken(IERC20 token) external view returns (bool) {
        return _supportedPaymentTokensIndex[address(token)] > 0;
    }

    function getEnterpriseCollector() external view returns (address) {
        return _enterpriseCollector;
    }

    function getEnterpriseVault() external view returns (address) {
        return _enterpriseVault;
    }

    function getBorrowerLoanReturnGracePeriod() public view returns (uint32) {
        return _borrowerLoanReturnGracePeriod;
    }

    function getEnterpriseLoanCollectGracePeriod() public view returns (uint32) {
        return _enterpriseLoanCollectGracePeriod;
    }

    function getPowerTokenImpl() public view returns (address) {
        return _powerTokenImpl;
    }

    function getServiceFee(IPowerToken powerToken) public view returns (uint112) {
        ServiceConfig storage config = serviceConfig[powerToken];
        if (block.timestamp < config.serviceFeeChangeTime) return config.previousServiceFee;

        return config.serviceFee;
    }

    function getHalfLife(IPowerToken powerToken) public view returns (uint32) {
        return serviceConfig[powerToken].halfLife;
    }

    function setEnterpriseCollector(address newCollector) public onlyOwner {
        require(newCollector != address(0), "Zero address");
        _enterpriseCollector = newCollector;
    }

    function setEnterpriseVault(address newVault) public onlyOwner {
        require(newVault != address(0), "Zero address");
        _enterpriseVault = newVault;
    }

    function scheduleEnterpriseFee(IPowerToken powerToken, uint16 newFee)
        public
        onlyOwner
        registeredPowerToken(powerToken)
    {
        _scheduleServiceFee(powerToken, newFee, uint32(block.timestamp) + _enterpriseConfigChangeGracePeriod);
    }

    function scheduleEnterpriseFeeBatch(IPowerToken[] calldata powerToken, uint16[] calldata newFee)
        external
        onlyOwner
    {
        require(powerToken.length == newFee.length, "Invalid array length");

        uint32 changeTime = uint32(block.timestamp) + _enterpriseConfigChangeGracePeriod;
        for (uint256 i = 0; i < powerToken.length; i++) {
            require(isRegisteredPowerToken(powerToken[i]), "Unknown PowerToken");
            _scheduleServiceFee(powerToken[i], newFee[i], changeTime);
        }
    }

    function _scheduleServiceFee(
        IPowerToken powerToken,
        uint16 newFee,
        uint32 changeTime
    ) internal {
        ServiceConfig storage config = serviceConfig[powerToken];

        if (config.serviceFeeChangeTime <= block.timestamp) {
            config.previousServiceFee = config.serviceFee;
        }
        config.serviceFee = newFee;
        config.serviceFeeChangeTime = changeTime;
        //TODO: emit event
    }

    function addService(IPowerToken powerToken, ServiceConfig memory config) public {
        require(msg.sender == address(_enterprise), "Not an enterprise");
        serviceConfig[powerToken] = config;
    }

    function setFactor(
        IPowerToken powerToken,
        uint112 factor,
        IERC20 factorToken
    ) public onlyOwner registeredPowerToken(powerToken) {
        require(address(factorToken) != address(0), "Invalid Factor Token");
        ServiceConfig storage config = serviceConfig[powerToken];

        config.factor = factor;
        config.factorToken = factorToken;
    }

    function getFactor(IPowerToken powerToken) external view returns (uint112) {
        return serviceConfig[powerToken].factor;
    }

    function getFactorToken(IPowerToken powerToken) external view returns (IERC20) {
        return serviceConfig[powerToken].factorToken;
    }

    function getMinLoanPeriod(IPowerToken powerToken) external view returns (uint32) {
        return serviceConfig[powerToken].minLoanPeriod;
    }

    function getMaxLoanPeriod(IPowerToken powerToken) external view returns (uint32) {
        return serviceConfig[powerToken].maxLoanPeriod;
    }

    function isAllowedLoanDuration(IPowerToken powerToken, uint32 duration) external view returns (bool) {
        ServiceConfig storage config = serviceConfig[powerToken];
        return config.minLoanPeriod <= duration && duration <= config.maxLoanPeriod;
    }

    function _enablePaymentToken(address token) internal {
        if (_supportedPaymentTokensIndex[token] == 0) {
            _supportedPaymentTokens.push(token);
            _supportedPaymentTokensIndex[token] = int16(_supportedPaymentTokens.length);
        } else if (_supportedPaymentTokensIndex[token] < 0) {
            _supportedPaymentTokensIndex[token] = -_supportedPaymentTokensIndex[token];
        }
    }

    function _disablePaymentToken(address token) internal {
        require(_supportedPaymentTokensIndex[token] != 0, "Invalid token");

        if (_supportedPaymentTokensIndex[token] > 0) {
            _supportedPaymentTokensIndex[token] = -_supportedPaymentTokensIndex[token];
        }
    }
}
