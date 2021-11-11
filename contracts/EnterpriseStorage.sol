// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "./interfaces/IPowerToken.sol";
import "./interfaces/IStakeToken.sol";
import "./interfaces/IRentalToken.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IEnterpriseStorage.sol";
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
abstract contract EnterpriseStorage is InitializableOwnable, IEnterpriseStorage {
    struct Stake {
        uint256 amount;
        uint256 shares;
        uint256 block;
    }
    struct PaymentTokenInfo {
        address paymentToken;
        bool enabled;
    }

    // This is the keccak-256 hash of "iq.protocol.proxy.admin" subtracted by 1
    bytes32 private constant _PROXY_ADMIN_SLOT = 0xd1248cccb5fef9131c731321e43e9a924840ffee7dc68c7d1d3e5cb7dedcae03;

    /**
     * @dev ERC20 token backed by enterprise services
     */
    IERC20Metadata internal _enterpriseToken;

    /**
     * @dev ERC721 stake bearing token
     */
    IStakeToken internal _stakeToken;

    /**
     * @dev ERC721 rental agreement bearing token
     */
    IRentalToken internal _rentalToken;

    /**
     * @dev Enterprise factory address
     */
    EnterpriseFactory internal _factory;

    /**
     * @dev This is a time period after which the half of the received pool fee will be streamed to the renting pool.
     */
    uint32 internal _streamingReserveHalvingPeriod;

    bool internal _enterpriseShutdown;

    /**
     * @dev Token conversion service address
     */
    IConverter internal _converter;

    /**
     * @dev Account which have rights to collect power tokens after rental agreement expiration
     */
    address internal _enterpriseCollector;

    /**
     * @dev Enterprise wallet address
     */
    address internal _enterpriseWallet;

    uint32 internal _renterOnlyReturnPeriod;
    uint32 internal _enterpriseOnlyCollectionPeriod;
    uint16 internal _gcFeePercent; // 100 is 1%, 10_000 is 100%

    mapping(address => int16) internal _paymentTokensIndex;
    address[] internal _paymentTokens;

    /**
     * @dev Fixed amount of enterprise tokens currently present in the renting pool
     */
    uint256 internal _fixedReserve;

    /**
     * @dev Total amount of used enterprise tokens
     */
    uint256 internal _usedReserve;

    /**
     * @dev Outstanding amount of enterprise tokens (rental payments) which is being continuously streamed to the renting pool
     */
    uint112 internal _streamingReserve;
    uint112 internal _streamingReserveTarget;
    uint32 internal _streamingReserveUpdated;

    /**
     * @dev Total number of renting pool shares issued to the stakers
     */
    uint256 internal _totalShares;

    /**
     * @dev Bonding factor calculation parameters
     */
    uint256 internal _bondingSlope;
    uint256 internal _bondingPole;

    string internal _name;
    string internal _baseUri;
    mapping(uint256 => RentalAgreement) internal _rentalAgreements;
    mapping(uint256 => Stake) internal _stakes;
    mapping(address => bool) internal _registeredPowerTokens;
    IPowerToken[] internal _powerTokens;

    event EnterpriseOnlyCollectionPeriodChanged(uint32 period);
    event RenterOnlyReturnPeriodChanged(uint32 period);
    event BondingChanged(uint256 pole, uint256 slope);
    event ConverterChanged(address converter);
    event StreamingReserveHalvingPeriodChanged(uint32 period);
    event GcFeePercentChanged(uint16 percent);
    event EnterpriseShutdown();
    event FixedReserveChanged(uint256 fixedReserve);
    event StreamingReserveChanged(uint112 streamingReserve, uint112 streamingReserveTarget);
    event PaymentTokenChange(address paymentToken, bool enabled);
    event EnterpriseWalletChanged(address wallet);
    event EnterpriseCollectorChanged(address collector);
    event BaseUriChanged(string baseUri);

    modifier whenNotShutdown() {
        require(!_enterpriseShutdown, Errors.E_ENTERPRISE_SHUTDOWN);
        _;
    }

    modifier onlyRentalToken() {
        require(msg.sender == address(_rentalToken), Errors.E_CALLER_NOT_RENTAL_TOKEN);
        _;
    }

    modifier onlyStakeTokenOwner(uint256 stakeTokenId) {
        require(_stakeToken.ownerOf(stakeTokenId) == msg.sender, Errors.CALLER_NOT_OWNER);
        _;
    }

    function initialize(
        string memory enterpriseName,
        string calldata baseUri,
        uint16 gcFeePercent,
        IConverter converter,
        ProxyAdmin proxyAdmin,
        address owner
    ) external override {
        require(bytes(_name).length == 0, Errors.ALREADY_INITIALIZED);
        require(bytes(enterpriseName).length > 0, Errors.E_INVALID_ENTERPRISE_NAME);
        InitializableOwnable.initialize(owner);
        StorageSlot.getAddressSlot(_PROXY_ADMIN_SLOT).value = address(proxyAdmin);
        _factory = EnterpriseFactory(msg.sender);
        _name = enterpriseName;
        _baseUri = baseUri;
        _gcFeePercent = gcFeePercent;
        _converter = converter;
        _enterpriseWallet = owner;
        _enterpriseCollector = owner;
        _streamingReserveHalvingPeriod = 7 days;
        _renterOnlyReturnPeriod = 12 hours;
        _enterpriseOnlyCollectionPeriod = 1 days;
        _bondingPole = uint256(5 << 64) / 100; // 5%
        _bondingSlope = uint256(3 << 64) / 10; // 0.3

        emit BaseUriChanged(baseUri);
        emit GcFeePercentChanged(_gcFeePercent);
        emit ConverterChanged(address(_converter));
        emit EnterpriseWalletChanged(_enterpriseWallet);
        emit EnterpriseCollectorChanged(_enterpriseCollector);
        emit StreamingReserveHalvingPeriodChanged(_streamingReserveHalvingPeriod);
        emit RenterOnlyReturnPeriodChanged(_renterOnlyReturnPeriod);
        emit EnterpriseOnlyCollectionPeriodChanged(_enterpriseOnlyCollectionPeriod);
        emit BondingChanged(_bondingPole, _bondingSlope);
    }

    function initializeTokens(
        IERC20Metadata enterpriseToken,
        IStakeToken stakeToken,
        IRentalToken rentalToken
    ) external override {
        require(address(_enterpriseToken) == address(0), Errors.ALREADY_INITIALIZED);
        require(address(enterpriseToken) != address(0), Errors.INVALID_ADDRESS);
        _enterpriseToken = enterpriseToken;
        _stakeToken = stakeToken;
        _rentalToken = rentalToken;
        // Initially the enterprise token is the only accepted payment token.
        _enablePaymentToken(address(enterpriseToken));
    }

    function isRegisteredPowerToken(address powerToken) external view returns (bool) {
        return _registeredPowerTokens[powerToken];
    }

    function getEnterpriseToken() external view override returns (IERC20Metadata) {
        return _enterpriseToken;
    }

    function getStakeToken() external view returns (IStakeToken) {
        return _stakeToken;
    }

    function getRentalToken() external view returns (IRentalToken) {
        return _rentalToken;
    }

    function getPaymentTokens() external view returns (PaymentTokenInfo[] memory) {
        uint256 length = _paymentTokens.length;
        PaymentTokenInfo[] memory info = new PaymentTokenInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            address token = _paymentTokens[i];
            info[i] = PaymentTokenInfo(token, _paymentTokensIndex[token] > 0);
        }
        return info;
    }

    function getPaymentTokenIndex(address token) public view returns (int16) {
        return _paymentTokensIndex[token] - 1;
    }

    function getPaymentToken(uint256 index) external view override returns (address) {
        return _paymentTokens[index];
    }

    function isSupportedPaymentToken(address token) public view override returns (bool) {
        return _paymentTokensIndex[token] > 0;
    }

    function getProxyAdmin() public view returns (ProxyAdmin) {
        return ProxyAdmin(StorageSlot.getAddressSlot(_PROXY_ADMIN_SLOT).value);
    }

    function getEnterpriseCollector() external view returns (address) {
        return _enterpriseCollector;
    }

    function getEnterpriseWallet() external view returns (address) {
        return _enterpriseWallet;
    }

    function getRenterOnlyReturnPeriod() external view returns (uint32) {
        return _renterOnlyReturnPeriod;
    }

    function getEnterpriseOnlyCollectionPeriod() external view returns (uint32) {
        return _enterpriseOnlyCollectionPeriod;
    }

    function getStreamingReserveHalvingPeriod() external view returns (uint32) {
        return _streamingReserveHalvingPeriod;
    }

    function getConverter() external view override returns (IConverter) {
        return _converter;
    }

    function getBaseUri() external view override returns (string memory) {
        return _baseUri;
    }

    function getFactory() external view returns (address) {
        return address(_factory);
    }

    function getInfo()
        external
        view
        returns (
            string memory name,
            string memory baseUri,
            uint32 streamingReserveHalvingPeriod,
            uint32 renterOnlyReturnPeriod,
            uint32 enterpriseOnlyCollectionPeriod,
            uint16 gcFeePercent,
            uint256 totalShares,
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
            _streamingReserveHalvingPeriod,
            _renterOnlyReturnPeriod,
            _enterpriseOnlyCollectionPeriod,
            _gcFeePercent,
            _totalShares,
            _fixedReserve,
            _usedReserve,
            _streamingReserve,
            _streamingReserveTarget,
            _streamingReserveUpdated
        );
    }

    function getPowerTokens() external view returns (IPowerToken[] memory) {
        return _powerTokens;
    }

    function getRentalAgreement(uint256 rentalTokenId) external view override returns (RentalAgreement memory) {
        _rentalToken.ownerOf(rentalTokenId); // will throw on non existent tokenId
        return _rentalAgreements[rentalTokenId];
    }

    function getStake(uint256 stakeTokenId) external view returns (Stake memory) {
        _stakeToken.ownerOf(stakeTokenId); // will throw on non existent tokenId
        return _stakes[stakeTokenId];
    }

    function getReserve() public view override returns (uint256) {
        return _fixedReserve + _getStreamingReserve();
    }

    function getUsedReserve() external view override returns (uint256) {
        return _usedReserve;
    }

    function getAvailableReserve() public view override returns (uint256) {
        return _getAvailableReserve(getReserve());
    }

    function getBondingCurve() external view override returns (uint256 pole, uint256 slope) {
        return (_bondingPole, _bondingSlope);
    }

    function setEnterpriseCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), Errors.ES_INVALID_COLLECTOR_ADDRESS);
        _enterpriseCollector = newCollector;
        emit EnterpriseCollectorChanged(newCollector);
    }

    function setEnterpriseWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), Errors.ES_INVALID_WALLET_ADDRESS);
        _enterpriseWallet = newWallet;
        emit EnterpriseWalletChanged(newWallet);
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

    function setRenterOnlyReturnPeriod(uint32 newPeriod) external onlyOwner {
        require(newPeriod <= _enterpriseOnlyCollectionPeriod, Errors.ES_INVALID_RENTER_ONLY_RETURN_PERIOD);

        _renterOnlyReturnPeriod = newPeriod;
        emit RenterOnlyReturnPeriodChanged(newPeriod);
    }

    function setEnterpriseOnlyCollectionPeriod(uint32 newPeriod) external onlyOwner {
        require(_renterOnlyReturnPeriod <= newPeriod, Errors.ES_INVALID_ENTERPRISE_ONLY_COLLECTION_PERIOD);

        _enterpriseOnlyCollectionPeriod = newPeriod;
        emit EnterpriseOnlyCollectionPeriodChanged(newPeriod);
    }

    function setBaseUri(string calldata baseUri) external onlyOwner {
        _baseUri = baseUri;
        emit BaseUriChanged(baseUri);
    }

    function setStreamingReserveHalvingPeriod(uint32 streamingReserveHalvingPeriod) external onlyOwner {
        require(streamingReserveHalvingPeriod > 0, Errors.ES_STREAMING_RESERVE_HALVING_PERIOD_NOT_GT_0);
        _streamingReserveHalvingPeriod = streamingReserveHalvingPeriod;
        emit StreamingReserveHalvingPeriodChanged(streamingReserveHalvingPeriod);
    }

    function upgrade(
        address enterpriseFactory,
        address enterpriseImplementation,
        address rentalTokenImplementation,
        address stakeTokenImplementation,
        address powerTokenImplementation,
        address[] calldata powerTokens
    ) external onlyOwner {
        require(enterpriseFactory != address(0), Errors.E_INVALID_ENTERPRISE_FACTORY_ADDRESS);
        _factory = EnterpriseFactory(enterpriseFactory);
        ProxyAdmin admin = getProxyAdmin();
        if (enterpriseImplementation != address(0)) {
            admin.upgrade(TransparentUpgradeableProxy(payable(address(this))), enterpriseImplementation);
        }
        if (rentalTokenImplementation != address(0)) {
            admin.upgrade(TransparentUpgradeableProxy(payable(address(_rentalToken))), rentalTokenImplementation);
        }
        if (stakeTokenImplementation != address(0)) {
            admin.upgrade(TransparentUpgradeableProxy(payable(address(_stakeToken))), stakeTokenImplementation);
        }
        if (powerTokenImplementation != address(0)) {
            for (uint256 i = 0; i < powerTokens.length; i++) {
                require(_registeredPowerTokens[powerTokens[i]], Errors.UNREGISTERED_POWER_TOKEN);
                admin.upgrade(TransparentUpgradeableProxy(payable(powerTokens[i])), powerTokenImplementation);
            }
        }
    }

    function setGcFeePercent(uint16 newGcFeePercent) external onlyOwner {
        _gcFeePercent = newGcFeePercent;
        emit GcFeePercentChanged(newGcFeePercent);
    }

    function getGCFeePercent() external view override returns (uint16) {
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
                _streamingReserveHalvingPeriod,
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

    function _getAvailableReserve(uint256 reserve) internal view returns (uint256) {
        return reserve - _usedReserve;
    }
}
