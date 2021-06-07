// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./math/ExpMath.sol";
import "./token/ERC20.sol";
import "./interfaces/IPowerToken.sol";
import "./Enterprise.sol";
import "./EnterpriseStorage.sol";
import "./PowerTokenStorage.sol";
import "./libs/Errors.sol";

contract PowerToken is IPowerToken, PowerTokenStorage, ERC20 {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    uint256 internal constant ONE = 1 << 64;

    function mint(address to, uint256 value) external override onlyEnterprise {
        _mint(to, value, true);
    }

    function burnFrom(address account, uint256 value) external override onlyEnterprise {
        _burn(account, value, true);
    }

    function availableBalanceOf(address account) external view returns (uint256) {
        return balanceOf(account) - states[account].lockedBalance;
    }

    function energyAt(address who, uint32 timestamp) public view returns (uint112) {
        State memory state = states[who];
        return _getEnergy(state, who, timestamp);
    }

    function _getEnergy(
        State memory state,
        address who,
        uint32 timestamp
    ) internal view returns (uint112) {
        uint112 balance = uint112(balanceOf(who));
        if (balance > state.energy) {
            return balance - ExpMath.halfLife(state.timestamp, balance - state.energy, gapHalvingPeriod, timestamp);
        } else {
            return balance + ExpMath.halfLife(state.timestamp, state.energy - balance, gapHalvingPeriod, timestamp);
        }
    }

    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external override onlyEnterprise returns (bool) {
        _transfer(from, to, amount, true);
        return true;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 value,
        bool updateLockedBalance
    ) internal override {
        uint32 timestamp = uint32(block.timestamp);

        if (from != address(0)) {
            State memory fromState = states[from];
            fromState.energy = _getEnergy(fromState, from, timestamp);
            fromState.timestamp = timestamp;
            if (!updateLockedBalance) {
                require(balanceOf(from) - value >= fromState.lockedBalance, Errors.PT_INSUFFICIENT_AVAILABLE_BALANCE);
            } else {
                fromState.lockedBalance -= uint112(value);
            }
            states[from] = fromState;
        }

        if (to != address(0)) {
            State memory toState = states[to];
            toState.energy = _getEnergy(toState, to, timestamp);
            toState.timestamp = timestamp;
            if (updateLockedBalance) {
                toState.lockedBalance += uint112(value);
            }
            states[to] = toState;
        }
    }

    function getInfo()
        external
        view
        returns (
            string memory name,
            string memory symbol,
            uint112 baseRate,
            uint96 minGCFee,
            uint32 gapHalvingPeriod,
            uint16 index,
            IERC20Metadata baseToken,
            uint32 minLoanDuration,
            uint32 maxLoanDuration,
            uint16 serviceFeePercent,
            bool allowsPerpetual
        )
    {
        return (
            this.name(),
            this.symbol(),
            this.baseRate(),
            this.minGCFee(),
            this.gapHalvingPeriod(),
            this.index(),
            this.baseToken(),
            this.minLoanDuration(),
            this.maxLoanDuration(),
            this.serviceFeePercent(),
            this.allowsPerpetual()
        );
    }

    /**
     * @dev Wraps liquidity tokens to perpetual PowerTokens
     *
     * One must approve sufficient amount of liquidity tokens to
     * corresponding PowerToken address before calling this function
     */
    function wrap(uint256 amount) public returns (bool) {
        return _wrapTo(msg.sender, amount);
    }

    /**
     * @dev Wraps liquidity tokens to perpetual PowerTokens
     *
     * One must approve sufficient amount of liquidity tokens to
     * corresponding PowerToken address before calling this function
     */
    function wrapTo(address to, uint256 amount) public returns (bool) {
        return _wrapTo(to, amount);
    }

    function _wrapTo(address to, uint256 amount) internal returns (bool) {
        require(allowsPerpetual == true, Errors.E_WRAPPING_NOT_ALLOWED);

        getEnterprise().getLiquidityToken().safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount, false);
        return true;
    }

    function unwrap(uint256 amount) external returns (bool) {
        _burn(msg.sender, amount, false);
        getEnterprise().getLiquidityToken().safeTransfer(msg.sender, amount);
        return true;
    }

    function estimateLoan(
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    ) external view returns (uint256) {
        (uint112 interest, uint112 serviceFee, uint112 gcFee) = _estimateLoanDetailed(paymentToken, amount, duration);

        return interest + serviceFee + gcFee;
    }

    /**
     * @dev Estimates loan cost divided into 3 parts:
     *  1) Pool interest
     *  2) Service operational fee
     *  3) Loan return lien
     */
    function estimateLoanDetailed(
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    )
        public
        view
        returns (
            uint112 interest,
            uint112 serviceFee,
            uint112 gcFee
        )
    {
        return _estimateLoanDetailed(paymentToken, amount, duration);
    }

    function _estimateLoanDetailed(
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    )
        internal
        view
        returns (
            uint112 interest,
            uint112 serviceFee,
            uint112 gcFee
        )
    {
        require(getEnterprise().isSupportedPaymentToken(paymentToken), Errors.E_UNSUPPORTED_INTEREST_PAYMENT_TOKEN);
        require(isAllowedLoanDuration(duration), Errors.E_LOAN_DURATION_OUT_OF_RANGE);

        uint112 loanBaseCost = estimateCost(amount, duration);
        uint112 serviceBaseFee = uint112((uint256(loanBaseCost) * serviceFeePercent) / 10_000);
        uint256 loanCost = getEnterprise().getConverter().estimateConvert(baseToken, loanBaseCost, paymentToken);

        serviceFee = uint112((uint256(serviceBaseFee) * loanCost) / loanBaseCost);
        interest = uint112(loanCost - serviceFee);
        gcFee = _estimateGCFee(paymentToken, amount);
    }

    function _estimateGCFee(IERC20 paymentToken, uint112 amount) internal view returns (uint112) {
        uint112 gcFeeAmount = uint112((uint256(amount) * getEnterprise().getGCFeePercent()) / 10_000);
        uint112 minGcFee = uint112(getEnterprise().getConverter().estimateConvert(baseToken, minGCFee, paymentToken));
        return gcFeeAmount < minGcFee ? minGcFee : gcFeeAmount;
    }

    function notifyNewLoan(uint256 tokenId) external {}

    /**
     * @dev
     * f(x) = 1 - λln(x)
     * h(x) = x * f((T - x) / T)
     * g(x) = h(U + x) - h(U)
     */
    function estimateCost(uint112 amount, uint32 duration) internal view returns (uint112) {
        uint256 availableReserve = getEnterprise().getAvailableReserve();
        if (availableReserve <= amount) return type(uint112).max;

        int8 decimalsDiff = int8(getEnterprise().getLiquidityToken().decimals()) - int8(baseToken.decimals());

        uint256 basePrice = g(amount, getEnterprise().getBondingLambda()) * duration;

        if (decimalsDiff > 0) {
            basePrice = ((basePrice * baseRate) / 10**uint8(decimalsDiff)) >> 64;
        } else if (decimalsDiff < 0) {
            basePrice = ((basePrice * baseRate) * 10**(uint8(-decimalsDiff))) >> 64;
        } else {
            basePrice = (basePrice * baseRate) >> 64;
        }
        return uint112(basePrice);
    }

    function g(uint256 x, uint256 lambda) internal view returns (uint256) {
        uint256 usedReserve = getEnterprise().getUsedReserve();
        uint256 reserve = getEnterprise().getReserve();

        return h(usedReserve + x, lambda, reserve) - h(usedReserve, lambda, reserve);
    }

    function f(uint128 x, uint256 lambda) internal pure returns (uint256) {
        return ONE + ((lambda * uint128(ExpMath.log_2(int128(x)))) >> 64);
    }

    function h(
        uint256 x,
        uint256 lambda,
        uint256 reserve
    ) internal pure returns (uint256) {
        return (x * f(uint128((reserve << 64) / ((reserve - x))), lambda)) >> 64;
    }
}
