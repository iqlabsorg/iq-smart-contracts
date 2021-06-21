// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./EnterpriseOwnable.sol";
import "./libs/Errors.sol";

abstract contract PowerTokenStorage is EnterpriseOwnable {
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
    // slot 2, 1 byte left
    IERC20Metadata internal _baseToken;
    uint32 internal _minLoanDuration;
    uint32 internal _maxLoanDuration;
    uint16 internal _serviceFeePercent; // 100 is 1%, 10_000 is 100%. Fee which goes to the enterprise to cover service operational costs for this service
    bool internal _allowsPerpetual; // allows wrapping tokens into perpetual PowerTokens

    mapping(address => State) internal _states;

    event BaseRateChanged(uint112 baseRate, address baseToken, uint96 minGCFee);
    event ServiceFeePercentChanged(uint16 percent);
    event LoanDurationLimitsChanged(uint32 minDuration, uint32 maxDuration);
    event PerpetualAllowed();

    function initialize(
        Enterprise enterprise,
        uint112 baseRate,
        uint96 minGCFee,
        uint32 gapHalvingPeriod,
        uint16 index,
        IERC20Metadata baseToken,
        uint32 minLoanDuration,
        uint32 maxLoanDuration,
        uint16 serviceFeePercent,
        bool allowsPerpetual
    ) external {
        require(_gapHalvingPeriod == 0, Errors.ALREADY_INITIALIZED);
        require(gapHalvingPeriod > 0, Errors.E_SERVICE_GAP_HALVING_PERIOD_NOT_GT_0);
        require(serviceFeePercent <= MAX_SERVICE_FEE_PERCENT, Errors.ES_MAX_SERVICE_FEE_PERCENT_EXCEEDED);
        require(_minLoanDuration <= _maxLoanDuration, Errors.E_INVALID_LOAN_DURATION_RANGE);

        EnterpriseOwnable.initialize(enterprise);
        _baseRate = baseRate;
        _minGCFee = minGCFee;
        _gapHalvingPeriod = gapHalvingPeriod;
        _index = index;
        _baseToken = baseToken;
        _minLoanDuration = minLoanDuration;
        _maxLoanDuration = maxLoanDuration;
        _serviceFeePercent = serviceFeePercent;
        _allowsPerpetual = allowsPerpetual;
        emit BaseRateChanged(baseRate, address(baseToken), minGCFee);
        emit ServiceFeePercentChanged(serviceFeePercent);
        emit LoanDurationLimitsChanged(minLoanDuration, maxLoanDuration);
        if (allowsPerpetual) {
            emit PerpetualAllowed();
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

    function allowPerpetualForever() external onlyEnterpriseOwner {
        require(!_allowsPerpetual, Errors.ES_PERPETUAL_TOKENS_ALREADY_ALLOWED);

        _allowsPerpetual = true;
        emit PerpetualAllowed();
    }

    function isAllowedLoanDuration(uint32 duration) public view returns (bool) {
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

    function getIndex() external view returns (uint16) {
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

    function getAllowsPerpetual() external view returns (bool) {
        return _allowsPerpetual;
    }

    function getState(address account) external view returns (State memory) {
        return _states[account];
    }
}
