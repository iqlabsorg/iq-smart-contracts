// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "./ExpMath.sol";
import "../token/ERC20.sol";
import "./interfaces/IPowerToken.sol";
import "./InitializableOwnable.sol";

contract PowerToken is IPowerToken, ERC20, InitializableOwnable {
    struct State {
        uint112 lockedBalance;
        uint112 energy;
        uint32 timestamp;
    }

    uint32 private _halfLife;
    mapping(address => State) private _states;
    uint32[] private _allowedLoanDurations;
    uint112 private _factor;
    uint32 private _lastDeal;
    uint32 private _interestRateHalvingPeriod;

    function initialize(
        string memory name,
        string memory symbol,
        uint32 halfLife,
        uint32[] memory allowedLoanDurations,
        uint112 factor,
        uint32 interestRateHalvingPeriod,
        address owner
    ) external override {
        require(_lastDeal == 0, "Already initialized");
        _halfLife = halfLife;
        _allowedLoanDurations = allowedLoanDurations;
        _lastDeal = uint32(block.timestamp);
        _factor = factor;
        _interestRateHalvingPeriod = interestRateHalvingPeriod;
        initialize(owner);
        initialize(name, symbol);
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

    function getInterestRateHalvingPeriod() external view override returns (uint32) {
        return _interestRateHalvingPeriod;
    }

    function isAllowedLoanDuration(uint32 duration) public view override returns (bool allowed) {
        uint256 n = _allowedLoanDurations.length;
        for (uint256 i = 0; i < n; i++) {
            if (_allowedLoanDurations[i] == duration) return true;
        }
        return false;
    }

    function mint(
        address to,
        uint256 value,
        bool withLocks
    ) external override onlyOwner {
        //TODO: checks
        _mint(to, uint112(value), withLocks);
    }

    function burnFrom(
        address account,
        uint256 value,
        bool withLocks
    ) external override onlyOwner {
        _burn(account, value, withLocks);
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

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external override onlyOwner returns (bool) {
        _transfer(from, to, amount);
        return true;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 value,
        bool withLocks
    ) internal override {
        uint32 timestamp = uint32(block.timestamp);

        if (from != address(0)) {
            State memory fromState = _states[from];
            fromState.energy = _getEnergy(fromState, from, timestamp);
            fromState.timestamp = timestamp;
            if (withLocks) {
                fromState.lockedBalance -= uint112(value);
            }
            _states[from] = fromState;
        }

        if (to != address(0)) {
            State memory toState = _states[to];
            toState.energy = _getEnergy(toState, to, timestamp);
            toState.timestamp = timestamp;
            if (withLocks) {
                toState.lockedBalance += uint112(value);
            }
            _states[to] = toState;
        }
    }
}
