// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IEnterprise.sol";
import "./interfaces/IPowerTokenStorage.sol";
import "./EnterpriseOwnable.sol";
import "./libs/Errors.sol";

// This contract cannot be extended anymore. If you need to add state variables to PowerToken
// consider creating PowerTokenStorage2 or similar contract, make PowerToken inherit it
// and add state variables there
abstract contract PowerTokenStorage is EnterpriseOwnable, IPowerTokenStorage {
    uint16 internal constant MAX_SERVICE_FEE_PERCENT = 5000; // 50%
    struct State {
        uint112 lockedBalance;
        uint112 energy;
        uint32 timestamp;
    }
    // slot 1, 0 bytes left
    uint112 internal _baseRate; // base rate for price calculations, nominated in baseToken
    uint96 internal _minGCFee; // fee for collecting expired PowerTokens
    uint32 internal _gapHalvingPeriod; // fixed, not updatable
    uint16 internal _index; // index in _powerTokens array. Not updatable
    // slot 2, 0 bytes left
    IERC20Metadata internal _baseToken;
    uint32 internal _minLoanDuration;
    uint32 internal _maxLoanDuration;
    uint16 internal _serviceFeePercent; // 100 is 1%, 10_000 is 100%. Fee which goes to the enterprise to cover service operational costs for this service
    bool internal _wrappingEnabled; // allows wrapping tokens into perpetual PowerTokens
    bool internal _transfersEnabled; // allows transfers of PowerTokens

    mapping(address => State) internal _states;

    event BaseRateChanged(uint112 baseRate, address baseToken, uint96 minGCFee);
    event ServiceFeePercentChanged(uint16 percent);
    event LoanDurationLimitsChanged(uint32 minDuration, uint32 maxDuration);
    event WrappingEnabled();
    event TransfersEnabled();

    function initialize(
        IEnterprise enterprise,
        uint112 baseRate,
        uint96 minGCFee,
        uint32 gapHalvingPeriod,
        uint16 index,
        IERC20Metadata baseToken
    ) external override {
        require(_gapHalvingPeriod == 0, Errors.ALREADY_INITIALIZED);
        require(gapHalvingPeriod > 0, Errors.E_SERVICE_GAP_HALVING_PERIOD_NOT_GT_0);

        EnterpriseOwnable.initialize(enterprise);
        _baseRate = baseRate;
        _minGCFee = minGCFee;
        _gapHalvingPeriod = gapHalvingPeriod;
        _index = index;
        _baseToken = baseToken;
        emit BaseRateChanged(baseRate, address(baseToken), minGCFee);
    }

    function initialize2(
        uint32 minLoanDuration,
        uint32 maxLoanDuration,
        uint16 serviceFeePercent,
        bool wrappingEnabled
    ) external override {
        require(_maxLoanDuration == 0, Errors.ALREADY_INITIALIZED);
        require(maxLoanDuration > 0, Errors.PT_INVALID_MAX_LOAN_DURATION);
        require(minLoanDuration <= maxLoanDuration, Errors.ES_INVALID_LOAN_DURATION_RANGE);

        _minLoanDuration = minLoanDuration;
        _maxLoanDuration = maxLoanDuration;
        _serviceFeePercent = serviceFeePercent;
        _wrappingEnabled = wrappingEnabled;
        emit ServiceFeePercentChanged(serviceFeePercent);
        emit LoanDurationLimitsChanged(minLoanDuration, maxLoanDuration);
        if (wrappingEnabled) {
            emit WrappingEnabled();
        }
    }

    function setBaseRate(
        uint112 baseRate,
        IERC20Metadata baseToken,
        uint96 minGCFee
    ) external onlyEnterpriseOwner {
        require(address(_baseToken) != address(0), Errors.ES_INVALID_BASE_TOKEN_ADDRESS);

        _baseRate = baseRate;
        _baseToken = baseToken;
        _minGCFee = minGCFee;

        emit BaseRateChanged(baseRate, address(baseToken), minGCFee);
    }

    function setServiceFeePercent(uint16 newServiceFeePercent) external onlyEnterpriseOwner {
        require(newServiceFeePercent <= MAX_SERVICE_FEE_PERCENT, Errors.ES_MAX_SERVICE_FEE_PERCENT_EXCEEDED);

        _serviceFeePercent = newServiceFeePercent;
        emit ServiceFeePercentChanged(newServiceFeePercent);
    }

    function setLoanDurationLimits(uint32 minLoanDuration, uint32 maxLoanDuration) external onlyEnterpriseOwner {
        require(minLoanDuration <= maxLoanDuration, Errors.ES_INVALID_LOAN_DURATION_RANGE);

        _minLoanDuration = minLoanDuration;
        _maxLoanDuration = maxLoanDuration;
        emit LoanDurationLimitsChanged(minLoanDuration, maxLoanDuration);
    }

    function enableWrappingForever() external onlyEnterpriseOwner {
        require(!_wrappingEnabled, Errors.ES_WRAPPING_ALREADY_ENABLED);

        _wrappingEnabled = true;
        emit WrappingEnabled();
    }

    function enableTransfersForever() external onlyEnterpriseOwner {
        require(!_transfersEnabled, Errors.ES_TRANSFERS_ALREADY_ENABLED);

        _transfersEnabled = true;
        emit TransfersEnabled();
    }

    function isAllowedLoanDuration(uint32 duration) public view override returns (bool) {
        return _minLoanDuration <= duration && duration <= _maxLoanDuration;
    }

    function getBaseRate() external view returns (uint112) {
        return _baseRate;
    }

    function getMinGCFee() external view returns (uint96) {
        return _minGCFee;
    }

    function getGapHalvingPeriod() external view returns (uint32) {
        return _gapHalvingPeriod;
    }

    function getIndex() external view override returns (uint16) {
        return _index;
    }

    function getBaseToken() external view returns (IERC20Metadata) {
        return _baseToken;
    }

    function getMinLoanDuration() external view returns (uint32) {
        return _minLoanDuration;
    }

    function getMaxLoanDuration() external view returns (uint32) {
        return _maxLoanDuration;
    }

    function getServiceFeePercent() external view returns (uint16) {
        return _serviceFeePercent;
    }

    function getState(address account) external view returns (State memory) {
        return _states[account];
    }

    function isWrappingEnabled() external view override returns (bool) {
        return _wrappingEnabled;
    }

    function isTransfersEnabled() external view override returns (bool) {
        return _transfersEnabled;
    }
}
