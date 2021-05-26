// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./math/ExpMath.sol";
import "./math/SafeMath112.sol";
import "./token/ERC20.sol";
import "./interfaces/IPowerToken.sol";
import "./InitializableOwnable.sol";

contract PowerToken is IPowerToken, ERC20, InitializableOwnable {
    using SafeMath for uint256;
    using SafeMath112 for uint112;
    using SafeERC20 for IERC20;

    struct State {
        uint112 lockedBalance;
        uint112 energy;
        uint32 timestamp;
    }

    uint32 private _halfLife;
    mapping(address => State) private _states;
    uint112 private _factor;
    IERC20 private _factorCurrency;
    uint32 private _lastDeal;
    uint32 private _minLoanPeriod;
    uint32 private _maxLoanPeriod;

    function initialize(
        string memory name,
        string memory symbol,
        uint32 halfLife,
        uint112 factor,
        uint32 minLoanPeriod,
        uint32 maxLoanPeriod
    ) external override {
        require(_lastDeal == 0, "Already initialized");
        require(minLoanPeriod <= maxLoanPeriod, "Invalid min and max periods");
        _halfLife = halfLife;
        _lastDeal = uint32(block.timestamp);
        _factor = factor;
        _minLoanPeriod = minLoanPeriod;
        _maxLoanPeriod = maxLoanPeriod;
        InitializableOwnable.initialize(msg.sender);
        ERC20.initialize(name, symbol);
    }

    function getHalfLife() external view override returns (uint32) {
        return _halfLife;
    }

    function getLastDeal() external view override returns (uint32) {
        return _lastDeal;
    }

    function getFactor() external view override returns (uint112) {
        return _factor;
    }

    function getMinLoanPeriod() external view override returns (uint32) {
        return _minLoanPeriod;
    }

    function getMaxLoanPeriod() external view override returns (uint32) {
        return _maxLoanPeriod;
    }

    function isAllowedLoanDuration(uint32 duration) external view override returns (bool) {
        return _minLoanPeriod <= duration && duration <= _maxLoanPeriod;
    }

    function availableBalanceOf(address account) external view returns (uint256) {
        State storage state = _states[account];
        return balanceOf(account).sub(state.lockedBalance);
    }

    function mint(address to, uint256 value) external override onlyOwner {
        _mint(to, value, true);
    }

    function burnFrom(address account, uint256 value) external override onlyOwner {
        _burn(account, value, true);
    }

    function wrap(
        IERC20 liquidityToken,
        address from,
        address to,
        uint256 amount
    ) external override onlyOwner {
        liquidityToken.safeTransferFrom(from, address(this), amount);
        _mint(to, amount, false);
    }

    function unwrap(
        IERC20 liquidityToken,
        address account,
        uint256 amount
    ) external override onlyOwner {
        _burn(account, amount, false);
        liquidityToken.safeTransfer(account, amount);
    }

    function energyAt(address who, uint32 timestamp) public view returns (uint112) {
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
            return balance - ExpMath.halfLife(state.timestamp, balance - state.energy, _halfLife, timestamp);
        } else {
            return balance + ExpMath.halfLife(state.timestamp, state.energy - balance, _halfLife, timestamp);
        }
    }

    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external override onlyOwner returns (bool) {
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
            State memory fromState = _states[from];
            fromState.energy = _getEnergy(fromState, from, timestamp);
            fromState.timestamp = timestamp;
            if (!updateLockedBalance) {
                require(balanceOf(from).sub(value) >= fromState.lockedBalance, "Insuffucient available balance");
            } else {
                fromState.lockedBalance -= uint112(value);
            }
            _states[from] = fromState;
        }

        if (to != address(0)) {
            State memory toState = _states[to];
            toState.energy = _getEnergy(toState, to, timestamp);
            toState.timestamp = timestamp;
            if (updateLockedBalance) {
                toState.lockedBalance += uint112(value);
            }
            _states[to] = toState;
        }
    }
}
