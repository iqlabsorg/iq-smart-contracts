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
 * @dev Contract which stores Enterprise state
 * To prevent Enterprise from front-running it's users, it is supposed to be owned by some
 * Governance system. For example OpenZeppelin `TimelockController` contract can
 * be used as an `owner` of this contract
 */
contract EnterpriseStorage is InitializableOwnable {
    uint16 internal constant MAX_SERVICE_FEE_PERCENT = 5000; // 50%

    struct ServiceConfig {
        // 1 slot
        uint112 baseRate; // base rate for price calculations, nominated in baseToken
        uint112 minGCFee; // fee for collecting expired PowerTokens
        uint32 halfLife; // fixed, not updatable
        // 2 slot
        IERC20Metadata baseToken;
        uint32 minLoanDuration;
        uint32 maxLoanDuration;
        uint16 serviceFeePercent; // 100 is 1%, 10_000 is 100%. Fee which goes to the enterprise to cover service operational costs for this service
        uint16 index; // 1 - based because empty value points to 0 index. Not updatable
    }

    struct LoanInfo {
        uint112 amount; // 14 bytes
        uint16 powerTokenIndex; // 2 bytes, index in powerToken array
        uint32 borrowingTime; // 4 bytes
        uint32 maturityTime; // 4 bytes
        uint32 borrowerReturnGraceTime; // 4 bytes
        uint32 enterpriseCollectGraceTime; // 4 bytes
        // slot 1, 0 bytes left
        uint112 gcFee; // 14 bytes, loan return reward
        uint16 gcFeeTokenIndex; // 2 bytes, index in supportedPaymentTokens array
        // slot 2, 16 bytes left
    }

    struct LiquidityInfo {
        uint256 amount;
        uint256 shares;
        uint256 block;
    }

    /**
     * @dev ERC20 token backed by enterprise services
     */
    IERC20Metadata internal _liquidityToken;

    IInterestToken internal _interestToken;
    /**
     * @dev ERC721 token to keep loan
     */
    IBorrowToken internal _borrowToken;
    address internal _powerTokenImpl;

    ILoanCostEstimator internal _estimator;
    IConverter internal _converter;
    address internal _enterpriseCollector;

    address internal _enterpriseVault;
    uint32 internal _borrowerLoanReturnGracePeriod = 1 days;
    uint32 internal _enterpriseLoanCollectGracePeriod = 2 days;
    uint16 internal _gcFeePercent; // 100 is 1%, 10_000 is 100%

    mapping(address => int16) internal _paymentTokensIndex;
    address[] internal _paymentTokens;
    string internal _baseUri;

    /**
     * @dev Total amount of `_liquidityToken`
     */
    uint256 internal _reserve;

    /**
     * @dev Available to borrow reserves of `_liquidityToken`
     */
    uint256 internal _availableReserve;

    uint256 internal _totalShares;

    string internal _name;
    mapping(uint256 => LoanInfo) internal _loanInfo;
    mapping(uint256 => LiquidityInfo) internal _liquidityInfo;
    mapping(IPowerToken => ServiceConfig) internal _serviceConfig;
    IPowerToken[] internal _powerTokens;

    modifier registeredPowerToken(IPowerToken powerToken) {
        require(isRegisteredPowerToken(powerToken), "Unknown PowerToken");
        _;
    }

    function initialize(
        string memory enterpriseName,
        string calldata baseUri,
        ILoanCostEstimator estimator,
        IConverter converter,
        address owner
    ) external {
        require(address(_interestToken) == address(0), "Already initialized");
        InitializableOwnable.initialize(owner);
        _name = enterpriseName;
        _baseUri = baseUri;
        _estimator = estimator;
        _converter = converter;
        _enterpriseVault = owner;
        _enterpriseCollector = owner;
    }

    function initializeTokens(
        address powerTokenImpl,
        IERC20Metadata liquidityToken,
        IInterestToken interestToken,
        IBorrowToken borrowToken
    ) public {
        require(_powerTokenImpl == address(0), "Already initialized");
        _powerTokenImpl = powerTokenImpl;
        _liquidityToken = liquidityToken;
        _interestToken = interestToken;
        _borrowToken = borrowToken;
        _enablePaymentToken(address(liquidityToken));
    }

    function getLiquidityToken() public view returns (IERC20Metadata) {
        return _liquidityToken;
    }

    function getInterestToken() public view returns (IInterestToken) {
        return _interestToken;
    }

    function getBorrowToken() public view returns (IBorrowToken) {
        return _borrowToken;
    }

    function setLoanCostEstimator(ILoanCostEstimator newEstimator) external onlyOwner {
        require(address(newEstimator) != address(0), "Zero address");
        _estimator = newEstimator;
        //TODO: emit event
    }

    function getLoanCostEstimator() public view returns (ILoanCostEstimator) {
        return _estimator;
    }

    function supportedPaymentTokensIndex(IERC20 token) public view returns (int16) {
        return _paymentTokensIndex[address(token)] - 1;
    }

    function supportedPaymentTokens(uint256 index) public view returns (address) {
        return _paymentTokens[index];
    }

    function isSupportedPaymentToken(IERC20 token) public view returns (bool) {
        return _paymentTokensIndex[address(token)] > 0;
    }

    function getEnterpriseCollector() public view returns (address) {
        return _enterpriseCollector;
    }

    function getEnterpriseVault() public view returns (address) {
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

    function getServiceFeePercent(IPowerToken powerToken) public view returns (uint112) {
        return _serviceConfig[powerToken].serviceFeePercent;
    }

    function getServiceHalfLife(IPowerToken powerToken) public view returns (uint32) {
        return _serviceConfig[powerToken].halfLife;
    }

    function getConverter() public view returns (IConverter) {
        return _converter;
    }

    function getBaseUri() public view returns (string memory) {
        return _baseUri;
    }

    function getInfo()
        external
        view
        returns (
            uint256 reserve,
            uint256 availableReserve,
            uint256 totalShares,
            string memory name
        )
    {
        return (_reserve, _availableReserve, _totalShares, _name);
    }

    function getPowerTokens() external view returns (IPowerToken[] memory) {
        return _powerTokens;
    }

    function getPowerTokensInfo()
        external
        view
        returns (
            address[] memory addresses,
            string[] memory names,
            string[] memory symbols,
            uint32[] memory halfLifes
        )
    {
        uint256 powerTokenCount = _powerTokens.length;
        addresses = new address[](powerTokenCount);
        names = new string[](powerTokenCount);
        symbols = new string[](powerTokenCount);
        halfLifes = new uint32[](powerTokenCount);

        for (uint256 i = 0; i < powerTokenCount; i++) {
            IPowerToken token = _powerTokens[i];
            addresses[i] = address(token);
            names[i] = token.name();
            symbols[i] = token.symbol();
            halfLifes[i] = getServiceHalfLife(token);
        }
    }

    function getLoanInfo(uint256 tokenId) external view returns (LoanInfo memory) {
        return _loanInfo[tokenId];
    }

    function getLiquidityInfo(uint256 tokenId) external view returns (LiquidityInfo memory) {
        return _liquidityInfo[tokenId];
    }

    function getPowerToken(uint256 index) external view returns (IPowerToken) {
        return _powerTokens[index];
    }

    function getPowerTokenIndex(IPowerToken powerToken)
        external
        view
        registeredPowerToken(powerToken)
        returns (uint16)
    {
        return _serviceConfig[powerToken].index;
    }

    function getReserve() external view returns (uint256) {
        return _reserve;
    }

    function getAvailableReserve() external view returns (uint256) {
        return _availableReserve;
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

    function setBorrowerLoanReturnGracePeriod(uint32 newPeriod) external onlyOwner {
        require(newPeriod <= _enterpriseLoanCollectGracePeriod, "Invalid grace periods");

        _borrowerLoanReturnGracePeriod = newPeriod;
    }

    function setEnterpriseLoanCollectGracePeriod(uint32 newPeriod) external onlyOwner {
        require(_borrowerLoanReturnGracePeriod <= newPeriod, "Invalid grace periods");

        _enterpriseLoanCollectGracePeriod = newPeriod;
    }

    function setBaseUri(string calldata baseUri) external onlyOwner {
        _baseUri = baseUri;
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

    function setServiceBaseRate(
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

    function setServiceLoanDurationLimits(
        IPowerToken powerToken,
        uint32 minLoanDuration,
        uint32 maxLoanDuration
    ) external onlyOwner registeredPowerToken(powerToken) {
        require(minLoanDuration <= maxLoanDuration, "Invalid durations");
        ServiceConfig storage config = _serviceConfig[powerToken];

        config.minLoanDuration = minLoanDuration;
        config.maxLoanDuration = maxLoanDuration;
    }

    function setGcFeePercent(uint16 newGcFeePercent) external onlyOwner {
        _gcFeePercent = newGcFeePercent;
    }

    function getGCFeePercent() public view returns (uint16) {
        return _gcFeePercent;
    }

    function getServiceBaseRate(IPowerToken powerToken) public view returns (uint112) {
        return _serviceConfig[powerToken].baseRate;
    }

    function getServiceMinGCFee(IPowerToken powerToken) public view returns (uint112) {
        return _serviceConfig[powerToken].minGCFee;
    }

    function getServiceBaseToken(IPowerToken powerToken) public view returns (IERC20Metadata) {
        return _serviceConfig[powerToken].baseToken;
    }

    function getServiceMinLoanDuration(IPowerToken powerToken) public view returns (uint32) {
        return _serviceConfig[powerToken].minLoanDuration;
    }

    function getServiceMaxLoanDuration(IPowerToken powerToken) public view returns (uint32) {
        return _serviceConfig[powerToken].maxLoanDuration;
    }

    function isServiceAllowedLoanDuration(IPowerToken powerToken, uint32 duration) public view returns (bool) {
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

    function isRegisteredPowerToken(IPowerToken powerToken) public view returns (bool) {
        return _serviceConfig[powerToken].halfLife != 0;
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
