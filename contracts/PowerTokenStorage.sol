// SPDX-License-Identifier: MIT

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
    uint32 internal _energyGapHalvingPeriod; // fixed, not updatable
    uint16 internal _index; // index in _powerTokens array. Not updatable
    // slot 2, 0 bytes left
    IERC20Metadata internal _baseToken;
    uint32 internal _minRentalPeriod;
    uint32 internal _maxRentalPeriod;
    uint16 internal _serviceFeePercent; // 100 is 1%, 10_000 is 100%. Fee which goes to the enterprise to cover service operational costs for this service
    bool internal _swappingEnabled; // allows swapping enterprise tokens into PowerTokens
    bool internal _transferEnabled; // allows transfers of PowerTokens

    mapping(address => State) internal _states;

    event BaseRateChanged(uint112 baseRate, address baseToken, uint96 minGCFee);
    event ServiceFeePercentChanged(uint16 percent);
    event RentalPeriodLimitsChanged(uint32 minRentalPeriod, uint32 maxRentalPeriod);
    event SwappingEnabled();
    event TransferEnabled();

    function initialize(
        IEnterprise enterprise,
        IERC20Metadata baseToken,
        uint112 baseRate,
        uint96 minGCFee,
        uint16 serviceFeePercent,
        uint32 energyGapHalvingPeriod,
        uint16 index,
        uint32 minRentalPeriod,
        uint32 maxRentalPeriod,
        bool swappingEnabled
    ) external override {
        require(_energyGapHalvingPeriod == 0, Errors.ALREADY_INITIALIZED);
        require(energyGapHalvingPeriod > 0, Errors.E_SERVICE_ENERGY_GAP_HALVING_PERIOD_NOT_GT_0);
        require(maxRentalPeriod > 0, Errors.PT_INVALID_MAX_RENTAL_PERIOD);
        require(minRentalPeriod <= maxRentalPeriod, Errors.ES_INVALID_RENTAL_PERIOD_RANGE);

        EnterpriseOwnable.initialize(enterprise);
        _baseToken = baseToken;
        _baseRate = baseRate;
        _minGCFee = minGCFee;
        _serviceFeePercent = serviceFeePercent;
        _energyGapHalvingPeriod = energyGapHalvingPeriod;
        _index = index;
        _minRentalPeriod = minRentalPeriod;
        _maxRentalPeriod = maxRentalPeriod;
        _swappingEnabled = swappingEnabled;

        emit BaseRateChanged(baseRate, address(baseToken), minGCFee);
        emit ServiceFeePercentChanged(serviceFeePercent);
        emit RentalPeriodLimitsChanged(minRentalPeriod, maxRentalPeriod);
        if (swappingEnabled) {
            emit SwappingEnabled();
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

    function setRentalPeriodLimits(uint32 minRentalPeriod, uint32 maxRentalPeriod) external onlyEnterpriseOwner {
        require(minRentalPeriod <= maxRentalPeriod, Errors.ES_INVALID_RENTAL_PERIOD_RANGE);

        _minRentalPeriod = minRentalPeriod;
        _maxRentalPeriod = maxRentalPeriod;
        emit RentalPeriodLimitsChanged(minRentalPeriod, maxRentalPeriod);
    }

    function enableSwappingForever() external onlyEnterpriseOwner {
        require(!_swappingEnabled, Errors.ES_SWAPPING_ALREADY_ENABLED);

        _swappingEnabled = true;
        emit SwappingEnabled();
    }

    function enableTransferForever() external onlyEnterpriseOwner {
        require(!_transferEnabled, Errors.ES_TRANSFER_ALREADY_ENABLED);

        _transferEnabled = true;
        emit TransferEnabled();
    }

    function isAllowedRentalPeriod(uint32 period) public view override returns (bool) {
        return _minRentalPeriod <= period && period <= _maxRentalPeriod;
    }

    function getBaseRate() external view returns (uint112) {
        return _baseRate;
    }

    function getMinGCFee() external view returns (uint96) {
        return _minGCFee;
    }

    function getEnergyGapHalvingPeriod() external view returns (uint32) {
        return _energyGapHalvingPeriod;
    }

    function getIndex() external view override returns (uint16) {
        return _index;
    }

    function getBaseToken() external view returns (IERC20Metadata) {
        return _baseToken;
    }

    function getMinRentalPeriod() external view returns (uint32) {
        return _minRentalPeriod;
    }

    function getMaxRentalPeriod() external view returns (uint32) {
        return _maxRentalPeriod;
    }

    function getServiceFeePercent() external view returns (uint16) {
        return _serviceFeePercent;
    }

    function getState(address account) external view returns (State memory) {
        return _states[account];
    }

    function isSwappingEnabled() external view override returns (bool) {
        return _swappingEnabled;
    }

    function isTransferEnabled() external view override returns (bool) {
        return _transferEnabled;
    }
}
