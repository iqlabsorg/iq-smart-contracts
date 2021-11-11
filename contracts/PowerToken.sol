// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility renting
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Stake strong!

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./math/ExpMath.sol";
import "./token/ERC20.sol";
import "./interfaces/IPowerToken.sol";
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
            return
                balance - ExpMath.halfLife(state.timestamp, balance - state.energy, _energyGapHalvingPeriod, timestamp);
        } else {
            return
                balance + ExpMath.halfLife(state.timestamp, state.energy - balance, _energyGapHalvingPeriod, timestamp);
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
        bool isRentedTokenTransfer
    ) internal override {
        bool isMinting = (from == address(0));
        bool isBurning = (to == address(0));
        require(isMinting || isBurning || _transferEnabled, Errors.PT_TRANSFER_DISABLED);

        uint32 timestamp = uint32(block.timestamp);
        if (!isMinting) {
            State memory fromState = _states[from];
            fromState.energy = _getEnergy(fromState, from, timestamp);
            fromState.timestamp = timestamp;
            if (!isRentedTokenTransfer) {
                require(balanceOf(from) - value >= fromState.lockedBalance, Errors.PT_INSUFFICIENT_AVAILABLE_BALANCE);
            } else {
                fromState.lockedBalance -= uint112(value);
            }
            _states[from] = fromState;
        }

        if (!isBurning) {
            State memory toState = _states[to];
            toState.energy = _getEnergy(toState, to, timestamp);
            toState.timestamp = timestamp;
            if (isRentedTokenTransfer) {
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
            IERC20Metadata baseToken,
            uint112 baseRate,
            uint96 minGCFee,
            uint16 serviceFeePercent,
            uint32 energyGapHalvingPeriod,
            uint16 index,
            uint32 minRentalPeriod,
            uint32 maxRentalPeriod,
            bool swappingEnabled,
            bool transferEnabled
        )
    {
        return (
            this.name(),
            this.symbol(),
            _baseToken,
            _baseRate,
            _minGCFee,
            _serviceFeePercent,
            _energyGapHalvingPeriod,
            _index,
            _minRentalPeriod,
            _maxRentalPeriod,
            _swappingEnabled,
            _transferEnabled
        );
    }

    /**
     * @dev Swaps enterprise tokens to power tokens
     *
     * One must approve sufficient amount of enterprise tokens to
     * corresponding PowerToken address before calling this function
     */
    function swapIn(uint256 amount) external returns (bool) {
        require(_swappingEnabled, Errors.E_SWAPPING_DISABLED);

        getEnterprise().getEnterpriseToken().safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount, false);
        return true;
    }

    /**
     * @dev Swaps power tokens back to enterprise tokens
     */
    function swapOut(uint256 amount) external returns (bool) {
        _burn(msg.sender, amount, false);
        getEnterprise().getEnterpriseToken().safeTransfer(msg.sender, amount);
        return true;
    }

    function estimateRentalFee(
        address paymentToken,
        uint112 rentalAmount,
        uint32 rentalPeriod
    )
        external
        view
        override
        returns (
            uint112 poolFee,
            uint112 serviceFee,
            uint112 gcFee
        )
    {
        require(getEnterprise().isSupportedPaymentToken(paymentToken), Errors.E_UNSUPPORTED_PAYMENT_TOKEN);
        require(isAllowedRentalPeriod(rentalPeriod), Errors.E_RENTAL_PERIOD_OUT_OF_RANGE);

        uint112 rentalBaseFeeInBaseTokens = estimateRentalBaseFee(rentalAmount, rentalPeriod);
        uint256 rentalBaseFee = getEnterprise().getConverter().estimateConvert(
            _baseToken,
            rentalBaseFeeInBaseTokens,
            IERC20(paymentToken)
        );

        serviceFee = uint112((rentalBaseFee * _serviceFeePercent) / 10_000);
        poolFee = uint112(rentalBaseFee - serviceFee);
        gcFee = _estimateGCFee(paymentToken, rentalBaseFee);
    }

    function _estimateGCFee(address paymentToken, uint256 amount) internal view returns (uint112) {
        uint112 gcFeeAmount = uint112((amount * getEnterprise().getGCFeePercent()) / 10_000);
        uint112 minGcFee = uint112(
            getEnterprise().getConverter().estimateConvert(_baseToken, _minGCFee, IERC20(paymentToken))
        );
        return gcFeeAmount < minGcFee ? minGcFee : gcFeeAmount;
    }

    function notifyNewRental(uint256 rentalTokenId) external override {}

    /**
     * @dev
     * f(x) = ((1 - t) * k) / (x - t) + (1 - k)
     * h(x) = x * f((T - x) / T)
     * g(x) = h(U + x) - h(U)
     */
    function estimateRentalBaseFee(uint112 rentalAmount, uint32 rentalPeriod) internal view returns (uint112) {
        IEnterprise enterprise = getEnterprise();
        uint256 reserve = enterprise.getReserve();
        uint256 usedReserve = enterprise.getUsedReserve();
        uint256 availableReserve = reserve - usedReserve;
        if (availableReserve <= rentalAmount) return type(uint112).max;

        int8 decimalsDiff = int8(enterprise.getEnterpriseToken().decimals()) - int8(_baseToken.decimals());

        (uint256 pole, uint256 slope) = enterprise.getBondingCurve();

        uint256 baseFee = g(rentalAmount, pole, slope, reserve, usedReserve) * rentalPeriod;

        if (decimalsDiff > 0) {
            baseFee = ((baseFee * _baseRate) / 10**uint8(decimalsDiff)) >> 64;
        } else if (decimalsDiff < 0) {
            baseFee = ((baseFee * _baseRate) * 10**(uint8(-decimalsDiff))) >> 64;
        } else {
            baseFee = (baseFee * _baseRate) >> 64;
        }
        return uint112(baseFee);
    }

    function g(
        uint128 x,
        uint256 pole,
        uint256 slope,
        uint256 reserve,
        uint256 usedReserve
    ) internal pure returns (uint256) {
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
