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

contract PowerToken is ERC20, PowerTokenStorage, IPowerToken {
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
        return balanceOf(account) - _states[account].lockedBalance;
    }

    function energyAt(address who, uint32 timestamp) external view returns (uint112) {
        State memory state = _states[who];
        return _getEnergy(state, who, timestamp);
    }

    function _getEnergy(
        State memory state,
        address who,
        uint32 timestamp
    ) internal view returns (uint112) {
        uint112 balance = uint112(balanceOf(who));
        if (balance > state.energy) {
            return balance - ExpMath.halfLife(state.timestamp, balance - state.energy, _gapHalvingPeriod, timestamp);
        } else {
            return balance + ExpMath.halfLife(state.timestamp, state.energy - balance, _gapHalvingPeriod, timestamp);
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
        bool isBorrowedTokenTransfer
    ) internal override {
        require(
            from == address(0) || to == address(0) || isBorrowedTokenTransfer || _transfersEnabled,
            Errors.PT_TRANSFERS_DISABLED
        );

        uint32 timestamp = uint32(block.timestamp);
        if (from != address(0)) {
            State memory fromState = _states[from];
            fromState.energy = _getEnergy(fromState, from, timestamp);
            fromState.timestamp = timestamp;
            if (!isBorrowedTokenTransfer) {
                require(balanceOf(from) - value >= fromState.lockedBalance, Errors.PT_INSUFFICIENT_AVAILABLE_BALANCE);
            } else {
                fromState.lockedBalance -= uint112(value);
            }
            _states[from] = fromState;
        }

        if (to != address(0)) {
            State memory toState = _states[to];
            toState.energy = _getEnergy(toState, to, timestamp);
            toState.timestamp = timestamp;
            if (isBorrowedTokenTransfer) {
                toState.lockedBalance += uint112(value);
            }
            _states[to] = toState;
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
            bool wrappingEnabled,
            bool transfersEnabled
        )
    {
        return (
            this.name(),
            this.symbol(),
            _baseRate,
            _minGCFee,
            _gapHalvingPeriod,
            _index,
            _baseToken,
            _minLoanDuration,
            _maxLoanDuration,
            _serviceFeePercent,
            _wrappingEnabled,
            _transfersEnabled
        );
    }

    /**
     * @dev Wraps liquidity tokens to perpetual PowerTokens
     *
     * One must approve sufficient amount of liquidity tokens to
     * corresponding PowerToken address before calling this function
     */
    function wrap(uint256 amount) external returns (bool) {
        return _wrapTo(msg.sender, amount);
    }

    /**
     * @dev Wraps liquidity tokens to perpetual PowerTokens
     *
     * One must approve sufficient amount of liquidity tokens to
     * corresponding PowerToken address before calling this function
     */
    function wrapTo(address to, uint256 amount) external returns (bool) {
        return _wrapTo(to, amount);
    }

    function _wrapTo(address to, uint256 amount) internal returns (bool) {
        require(_wrappingEnabled, Errors.E_WRAPPING_DISABLED);

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
        address paymentToken,
        uint112 amount,
        uint32 duration
    ) external view override returns (uint256) {
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
        address paymentToken,
        uint112 amount,
        uint32 duration
    )
        external
        view
        override
        returns (
            uint112 interest,
            uint112 serviceFee,
            uint112 gcFee
        )
    {
        return _estimateLoanDetailed(paymentToken, amount, duration);
    }

    function _estimateLoanDetailed(
        address paymentToken,
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
        uint256 loanCost = getEnterprise().getConverter().estimateConvert(
            _baseToken,
            loanBaseCost,
            IERC20(paymentToken)
        );

        serviceFee = uint112((loanCost * _serviceFeePercent) / 10_000);
        interest = uint112(loanCost - serviceFee);
        gcFee = _estimateGCFee(paymentToken, loanCost);
    }

    function _estimateGCFee(address paymentToken, uint256 amount) internal view returns (uint112) {
        uint112 gcFeeAmount = uint112((amount * getEnterprise().getGCFeePercent()) / 10_000);
        uint112 minGcFee = uint112(
            getEnterprise().getConverter().estimateConvert(_baseToken, _minGCFee, IERC20(paymentToken))
        );
        return gcFeeAmount < minGcFee ? minGcFee : gcFeeAmount;
    }

    function notifyNewLoan(uint256 borrowTokenId) external override {}

    /**
     * @dev
     * f(x) = ((1 - t) * k) / (x - t) + (1 - k)
     * h(x) = x * f((T - x) / T)
     * g(x) = h(U + x) - h(U)
     */
    function estimateCost(uint112 amount, uint32 duration) internal view returns (uint112) {
        uint256 availableReserve = getEnterprise().getAvailableReserve();
        if (availableReserve <= amount) return type(uint112).max;

        int8 decimalsDiff = int8(getEnterprise().getLiquidityToken().decimals()) - int8(_baseToken.decimals());

        (uint256 pole, uint256 slope) = getEnterprise().getBondingCurve();

        uint256 basePrice = g(amount, pole, slope) * duration;

        if (decimalsDiff > 0) {
            basePrice = ((basePrice * _baseRate) / 10**uint8(decimalsDiff)) >> 64;
        } else if (decimalsDiff < 0) {
            basePrice = ((basePrice * _baseRate) * 10**(uint8(-decimalsDiff))) >> 64;
        } else {
            basePrice = (basePrice * _baseRate) >> 64;
        }
        return uint112(basePrice);
    }

    function g(
        uint128 x,
        uint256 pole,
        uint256 slope
    ) internal view returns (uint256) {
        uint256 usedReserve = getEnterprise().getUsedReserve();
        uint256 reserve = getEnterprise().getReserve();

        return h(usedReserve + x, pole, slope, reserve) - h(usedReserve, pole, slope, reserve);
    }

    function h(
        uint256 x,
        uint256 pole,
        uint256 slope,
        uint256 reserve
    ) internal pure returns (uint256) {
        return (x * f(uint128(((reserve - x) << 64) / reserve), pole, slope)) >> 64;
    }

    function f(
        uint256 x,
        uint256 pole,
        uint256 slope
    ) internal pure returns (uint256) {
        if (x <= pole) return type(uint128).max;
        return (((ONE - pole) * slope)) / (x - pole) + (ONE - slope);
    }
}
