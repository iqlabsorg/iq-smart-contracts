// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "./interfaces/IPowerToken.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IConverter.sol";
import "./InitializableOwnable.sol";
import "./EnterpriseFactory.sol";
import "./math/ExpMath.sol";
import "./libs/Errors.sol";

/**
 * @dev Contract which stores Enterprise state
 * To prevent Enterprise from front-running it's users, it is supposed to be owned by some
 * Governance system. For example: OpenZeppelin `TimelockController` contract can
 * be used as an `owner` of this contract
 */
abstract contract EnterpriseStorage is InitializableOwnable {
    struct LoanInfo {
        // slot 1, 0 bytes left
        uint112 amount; // 14 bytes
        uint16 powerTokenIndex; // 2 bytes, index in powerToken array
        uint32 borrowingTime; // 4 bytes
        uint32 maturityTime; // 4 bytes
        uint32 borrowerReturnGraceTime; // 4 bytes
        uint32 enterpriseCollectGraceTime; // 4 bytes
        // slot 2, 16 bytes left
        uint112 gcFee; // 14 bytes, loan return reward
        uint16 gcFeeTokenIndex; // 2 bytes, index in `_paymentTokens` array
    }

    struct LiquidityInfo {
        uint256 amount;
        uint256 shares;
        uint256 block;
    }

    // This is the keccak-256 hash of "iq.protocol.proxy.admin" subtracted by 1
    bytes32 private constant _PROXY_ADMIN_SLOT = 0xd1248cccb5fef9131c731321e43e9a924840ffee7dc68c7d1d3e5cb7dedcae03;

    /**
     * @dev ERC20 token backed by enterprise services
     */
    IERC20Metadata internal _liquidityToken;

    /**
     * @dev ERC721 token for liquidity providers
     */
    IInterestToken internal _interestToken;

    /**
     * @dev ERC721 token for borrowers
     */
    IBorrowToken internal _borrowToken;
    EnterpriseFactory internal _factory;
    uint32 internal _interestGapHalvingPeriod;
    bool internal _enterpriseShutdown;

    IConverter internal _converter;

    /**
     * @dev address which have rights to collect expired PowerTokens
     */
    address internal _enterpriseCollector;

    /**
     * @dev address where collected service fee goes
     */
    address internal _enterpriseVault;

    uint32 internal _borrowerLoanReturnGracePeriod;
    uint32 internal _enterpriseLoanCollectGracePeriod;
    uint16 internal _gcFeePercent; // 100 is 1%, 10_000 is 100%

    mapping(address => int16) internal _paymentTokensIndex;
    address[] internal _paymentTokens;

    /**
     * @dev Amount of fixed `_liquidityToken`
     */
    uint256 internal _fixedReserve;

    /**
     * @dev Borrowed reserves of `_liquidityToken`
     */
    uint256 internal _usedReserve;

    /**
     * @dev Reserves which are streamed from borrower to the pool
     */
    uint112 internal _streamingReserve;
    uint112 internal _streamingReserveTarget;
    uint32 internal _streamingReserveUpdated;

    /**
     * Total shares given to liquidity providers
     */
    uint256 internal _totalShares;

    uint256 internal _bondingSlope;
    uint256 internal _bondingPole;

    string internal _name;
    string internal _baseUri;
    mapping(uint256 => LoanInfo) internal _loanInfo;
    mapping(uint256 => LiquidityInfo) internal _liquidityInfo;
    mapping(PowerToken => bool) internal _registeredPowerTokens;
    PowerToken[] internal _powerTokens;

    event EnterpriseLoanCollectGracePeriodChanged(uint32 period);
    event BorrowerLoanReturnGracePeriodChanged(uint32 period);
    event BondingChanged(uint256 pole, uint256 slope);
    event ConverterChanged(address converter);
    event InterestGapHalvingPeriodChanged(uint32 period);
    event GcFeePercentChanged(uint16 percent);
    event EnterpriseShutdown();
    event FixedReserveChanged(uint256 fixedReserve);
    event StreamingReserveChanged(uint112 streamingReserve, uint112 streamingReserveTarget);
    event PaymentTokenChange(address paymentToken, bool enabled);
    event EnterpriseVaultChanged(address vault);
    event EnterpriseCollectorChanged(address collector);
    event BaseUriChanged(string baseUri);

    modifier notShutdown() {
        require(!_enterpriseShutdown, Errors.E_ENTERPRISE_SHUTDOWN);
        _;
    }

    modifier onlyBorrowToken() {
        require(msg.sender == address(_borrowToken), Errors.E_CALLER_NOT_BORROW_TOKEN);
        _;
    }

    modifier onlyInterestTokenOwner(uint256 interestTokenId) {
        require(_interestToken.ownerOf(interestTokenId) == msg.sender, Errors.CALLER_NOT_OWNER);
        _;
    }

    function initialize(
        string memory enterpriseName,
        string calldata baseUri,
        uint16 gcFeePercent,
        IConverter converter,
        ProxyAdmin proxyAdmin,
        address owner
    ) external {
        require(bytes(_name).length == 0, Errors.ALREADY_INITIALIZED);
        InitializableOwnable.initialize(owner);
        StorageSlot.getAddressSlot(_PROXY_ADMIN_SLOT).value = address(proxyAdmin);
        _factory = EnterpriseFactory(msg.sender);
        _name = enterpriseName;
        _baseUri = baseUri;
        _gcFeePercent = gcFeePercent;
        _converter = converter;
        _enterpriseVault = owner;
        _enterpriseCollector = owner;
        _interestGapHalvingPeriod = 7 days;
        _borrowerLoanReturnGracePeriod = 12 hours;
        _enterpriseLoanCollectGracePeriod = 1 days;
        _bondingPole = uint256(5 << 64) / 100; // 5%
        _bondingSlope = uint256(3 << 64) / 10; // 0.3

        emit BaseUriChanged(baseUri);
        emit GcFeePercentChanged(_gcFeePercent);
        emit ConverterChanged(address(_converter));
        emit EnterpriseVaultChanged(_enterpriseVault);
        emit EnterpriseCollectorChanged(_enterpriseCollector);
        emit InterestGapHalvingPeriodChanged(_interestGapHalvingPeriod);
        emit BorrowerLoanReturnGracePeriodChanged(_borrowerLoanReturnGracePeriod);
        emit EnterpriseLoanCollectGracePeriodChanged(_enterpriseLoanCollectGracePeriod);
        emit BondingChanged(_bondingPole, _bondingSlope);
    }

    function initializeTokens(
        IERC20Metadata liquidityToken,
        IInterestToken interestToken,
        IBorrowToken borrowToken
    ) external {
        require(address(_liquidityToken) == address(0), Errors.ALREADY_INITIALIZED);
        _liquidityToken = liquidityToken;
        _interestToken = interestToken;
        _borrowToken = borrowToken;
        _enablePaymentToken(address(liquidityToken));
    }

    function isRegisteredPowerToken(PowerToken powerToken) external view returns (bool) {
        return _registeredPowerTokens[powerToken];
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

    function getPaymentTokenIndex(IERC20 token) public view returns (int16) {
        return _paymentTokensIndex[address(token)] - 1;
    }

    function getPaymentToken(uint256 index) external view returns (address) {
        return _paymentTokens[index];
    }

    function isSupportedPaymentToken(IERC20 token) public view returns (bool) {
        return _paymentTokensIndex[address(token)] > 0;
    }

    function getProxyAdmin() public view returns (ProxyAdmin) {
        return ProxyAdmin(StorageSlot.getAddressSlot(_PROXY_ADMIN_SLOT).value);
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

    function getInterestGapHalvingPeriod() external view returns (uint32) {
        return _interestGapHalvingPeriod;
    }

    function getConverter() external view returns (IConverter) {
        return _converter;
    }

    function getBaseUri() external view returns (string memory) {
        return _baseUri;
    }

    function getInfo()
        external
        view
        returns (
            string memory name,
            string memory baseUri,
            uint256 totalShares,
            uint32 interestGapHalvingPeriod,
            uint32 borrowerLoanReturnGracePeriod,
            uint32 enterpriseLoanCollectGracePeriod,
            uint16 gcFeePercent,
            uint256 fixedReserve,
            uint256 usedReserve,
            uint112 streamingReserve,
            uint112 streamingReserveTarget,
            uint32 streamingReserveUpdated
        )
    {
        return (
            _name,
            _baseUri,
            _totalShares,
            _interestGapHalvingPeriod,
            _borrowerLoanReturnGracePeriod,
            _enterpriseLoanCollectGracePeriod,
            _gcFeePercent,
            _fixedReserve,
            _usedReserve,
            _streamingReserve,
            _streamingReserveTarget,
            _streamingReserveUpdated
        );
    }

    function getPowerTokens() external view returns (PowerToken[] memory) {
        return _powerTokens;
    }

    function getLoanInfo(uint256 borrowTokenId) external view returns (LoanInfo memory) {
        _borrowToken.ownerOf(borrowTokenId); // will throw on non existent tokenId
        return _loanInfo[borrowTokenId];
    }

    function getLiquidityInfo(uint256 interestTokenId) external view returns (LiquidityInfo memory) {
        _interestToken.ownerOf(interestTokenId); // will throw on non existent tokenId
        return _liquidityInfo[interestTokenId];
    }

    function getReserve() public view returns (uint256) {
        return _fixedReserve + _getStreamingReserve();
    }

    function getUsedReserve() external view returns (uint256) {
        return _usedReserve;
    }

    function getAvailableReserve() public view returns (uint256) {
        return getReserve() - _usedReserve;
    }

    function getBondingCurve() external view returns (uint256 pole, uint256 slope) {
        return (_bondingPole, _bondingSlope);
    }

    function setEnterpriseCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), Errors.ES_INVALID_COLLECTOR_ADDRESS);
        _enterpriseCollector = newCollector;
        emit EnterpriseCollectorChanged(newCollector);
    }

    function setEnterpriseVault(address newVault) external onlyOwner {
        require(newVault != address(0), Errors.ES_INVALID_VAULT_ADDRESS);
        _enterpriseVault = newVault;
        emit EnterpriseVaultChanged(newVault);
    }

    function setConverter(IConverter newConverter) external onlyOwner {
        require(address(newConverter) != address(0), Errors.ES_INVALID_CONVERTER_ADDRESS);
        _converter = newConverter;
        emit ConverterChanged(address(newConverter));
    }

    function setBondingCurve(uint256 pole, uint256 slope) external onlyOwner {
        require(pole <= uint256(3 << 64) / 10, Errors.ES_INVALID_BONDING_POLE); // max is 30%
        require(slope <= (1 << 64), Errors.ES_INVALID_BONDING_SLOPE);
        _bondingPole = pole;
        _bondingSlope = slope;
        emit BondingChanged(_bondingPole, _bondingSlope);
    }

    function setBorrowerLoanReturnGracePeriod(uint32 newPeriod) external onlyOwner {
        require(newPeriod <= _enterpriseLoanCollectGracePeriod, Errors.ES_INVALID_BORROWER_LOAN_RETURN_GRACE_PERIOD);

        _borrowerLoanReturnGracePeriod = newPeriod;
        emit BorrowerLoanReturnGracePeriodChanged(newPeriod);
    }

    function setEnterpriseLoanCollectGracePeriod(uint32 newPeriod) external onlyOwner {
        require(_borrowerLoanReturnGracePeriod <= newPeriod, Errors.ES_INVALID_ENTERPRISE_LOAN_COLLECT_GRACE_PERIOD);

        _enterpriseLoanCollectGracePeriod = newPeriod;
        emit EnterpriseLoanCollectGracePeriodChanged(newPeriod);
    }

    function setBaseUri(string calldata baseUri) external onlyOwner {
        _baseUri = baseUri;
        emit BaseUriChanged(baseUri);
    }

    function setInterestGapHalvingPeriod(uint32 interestGapHalvingPeriod) external onlyOwner {
        require(interestGapHalvingPeriod > 0, Errors.ES_INTEREST_GAP_HALVING_PERIOD_NOT_GT_0);
        _interestGapHalvingPeriod = interestGapHalvingPeriod;
        emit InterestGapHalvingPeriodChanged(interestGapHalvingPeriod);
    }

    function upgradePowerToken(PowerToken powerToken, address implementation) external onlyOwner {
        require(_registeredPowerTokens[powerToken], Errors.UNREGISTERED_POWER_TOKEN);
        getProxyAdmin().upgrade(TransparentUpgradeableProxy(payable(address(powerToken))), implementation);
    }

    function upgradeBorrowToken(address implementation) external onlyOwner {
        getProxyAdmin().upgrade(TransparentUpgradeableProxy(payable(address(_borrowToken))), implementation);
    }

    function upgradeInterestToken(address implementation) external onlyOwner {
        getProxyAdmin().upgrade(TransparentUpgradeableProxy(payable(address(_interestToken))), implementation);
    }

    function upgradeEnterprise(address implementation) external onlyOwner {
        getProxyAdmin().upgrade(TransparentUpgradeableProxy(payable(address(this))), implementation);
    }

    function setGcFeePercent(uint16 newGcFeePercent) external onlyOwner {
        _gcFeePercent = newGcFeePercent;
        emit GcFeePercentChanged(newGcFeePercent);
    }

    function getGCFeePercent() external view returns (uint16) {
        return _gcFeePercent;
    }

    function enablePaymentToken(address token) external onlyOwner {
        require(token != address(0), Errors.ES_INVALID_PAYMENT_TOKEN_ADDRESS);
        _enablePaymentToken(token);
    }

    function disablePaymentToken(address token) external onlyOwner {
        require(_paymentTokensIndex[token] != 0, Errors.ES_UNREGISTERED_PAYMENT_TOKEN);

        if (_paymentTokensIndex[token] > 0) {
            _paymentTokensIndex[token] = -_paymentTokensIndex[token];
            emit PaymentTokenChange(token, false);
        }
    }

    function _enablePaymentToken(address token) internal {
        if (_paymentTokensIndex[token] == 0) {
            _paymentTokens.push(token);
            _paymentTokensIndex[token] = int16(uint16(_paymentTokens.length));
            emit PaymentTokenChange(token, true);
        } else if (_paymentTokensIndex[token] < 0) {
            _paymentTokensIndex[token] = -_paymentTokensIndex[token];
            emit PaymentTokenChange(token, true);
        }
    }

    function _getStreamingReserve() internal view returns (uint112) {
        return
            _streamingReserveTarget -
            ExpMath.halfLife(
                _streamingReserveUpdated,
                _streamingReserveTarget - _streamingReserve,
                _interestGapHalvingPeriod,
                uint32(block.timestamp)
            );
    }

    function _increaseStreamingReserveTarget(uint112 delta) internal {
        _streamingReserve = _getStreamingReserve();
        _streamingReserveTarget += delta;
        _streamingReserveUpdated = uint32(block.timestamp);
        emit StreamingReserveChanged(_streamingReserve, _streamingReserveTarget);
    }

    function _flushStreamingReserve() internal returns (uint112 streamingReserve) {
        streamingReserve = _getStreamingReserve();

        _streamingReserve = 0;
        _streamingReserveTarget -= streamingReserve;
        _streamingReserveUpdated = uint32(block.timestamp);
        emit StreamingReserveChanged(_streamingReserve, _streamingReserveTarget);
    }
}
