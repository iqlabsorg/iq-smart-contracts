// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./EnterpriseOwnable.sol";
import "./libs/Errors.sol";

contract PowerTokenStorage is EnterpriseOwnable {
    uint16 internal constant MAX_SERVICE_FEE_PERCENT = 5000; // 50%
    struct State {
        uint112 lockedBalance;
        uint112 energy;
        uint32 timestamp;
    }
    // slot 1, 0 bytes left
    uint112 public baseRate; // base rate for price calculations, nominated in baseToken
    uint96 public minGCFee; // fee for collecting expired PowerTokens
    uint32 public gapHalvingPeriod; // fixed, not updatable
    uint16 public index; // index in _powerTokens array. Not updatable
    // slot 2, 1 byte left
    IERC20Metadata public baseToken;
    uint32 public minLoanDuration;
    uint32 public maxLoanDuration;
    uint16 public serviceFeePercent; // 100 is 1%, 10_000 is 100%. Fee which goes to the enterprise to cover service operational costs for this service
    bool public allowsPerpetual; // allows wrapping tokens into perpetual PowerTokens
    // slot 3
    uint256 public lambda;

    mapping(address => State) public states;

    function initialize(
        Enterprise enterprise_,
        uint112 baseRate_,
        uint96 minGCFee_,
        uint32 gapHalvingPeriod_,
        uint16 index_,
        IERC20Metadata baseToken_,
        uint32 minLoanDuration_,
        uint32 maxLoanDuration_,
        uint16 serviceFeePercent_,
        bool allowsPerpetual_
    ) external {
        require(gapHalvingPeriod == 0, Errors.ALREADY_INITIALIZED);
        require(gapHalvingPeriod_ > 0, Errors.E_SERVICE_GAP_HALVING_PERIOD_NOT_GT_0);
        require(serviceFeePercent_ <= MAX_SERVICE_FEE_PERCENT, Errors.ES_MAX_SERVICE_FEE_PERCENT_EXCEEDED);
        require(minLoanDuration <= maxLoanDuration, Errors.E_INVALID_LOAN_DURATION_RANGE);

        EnterpriseOwnable.initialize(enterprise_);
        baseRate = baseRate_;
        minGCFee = minGCFee_;
        gapHalvingPeriod = gapHalvingPeriod_;
        index = index_;
        baseToken = baseToken_;
        minLoanDuration = minLoanDuration_;
        maxLoanDuration = maxLoanDuration_;
        serviceFeePercent = serviceFeePercent_;
        allowsPerpetual = allowsPerpetual_;
    }

    function setBaseRate(
        uint112 baseRate_,
        IERC20Metadata baseToken_,
        uint96 minGCFee_
    ) public onlyEnterpriseOwner {
        require(address(baseToken) != address(0), Errors.ES_INVALID_BASE_TOKEN_ADDRESS);

        baseRate = baseRate_;
        baseToken = baseToken_;
        minGCFee = minGCFee_;
    }

    function setServiceFeePercent(uint16 newServiceFeePercent) external onlyEnterpriseOwner {
        require(newServiceFeePercent <= MAX_SERVICE_FEE_PERCENT, Errors.ES_MAX_SERVICE_FEE_PERCENT_EXCEEDED);

        serviceFeePercent = newServiceFeePercent;
    }

    function setLoanDurationLimits(uint32 minLoanDuration_, uint32 maxLoanDuration_) external onlyEnterpriseOwner {
        require(minLoanDuration_ <= maxLoanDuration_, Errors.ES_INVALID_LOAN_DURATION_RANGE);

        minLoanDuration = minLoanDuration_;
        maxLoanDuration = maxLoanDuration_;
    }

    function allowPerpetualForever() external onlyEnterpriseOwner {
        require(allowsPerpetual == false, Errors.ES_PERPETUAL_TOKENS_ALREADY_ALLOWED);

        allowsPerpetual = true;
    }

    function isAllowedLoanDuration(uint32 duration) public view returns (bool) {
        return minLoanDuration <= duration && duration <= maxLoanDuration;
    }
}
