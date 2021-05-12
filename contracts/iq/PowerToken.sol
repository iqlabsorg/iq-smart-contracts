// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "./ERC1155Base.sol";
import "./interfaces/IPowerToken.sol";

contract PowerToken is ERC1155Base, IPowerToken {
    struct State {
        uint112 balance;
        uint112 energy;
        uint32 timestamp;
    }

    uint32 public halfLife;

    mapping(address => State) public states;

    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _baseUri,
        uint32 _halfLife
    ) external override {
        halfLife = _halfLife;
        initialize(_name, _symbol, _baseUri);
    }

    function mint(
        address _to,
        uint256 _id,
        uint256 _value,
        bytes memory _data
    ) external override onlyOwner {
        //TODO: checks
        _mint(_to, _id, uint112(_value), _data);
    }

    function burn(
        address _account,
        uint256 _id,
        uint256 _value
    ) external override onlyOwner {
        _burn(_account, _id, _value);
    }

    function energyAt(address who, uint32 timestamp) public view returns (uint112) {
        State memory state = states[who];
        return _getEnergy(state, timestamp);
    }

    /////////////////////////////////////////// Internal //////////////////////////////////////////////

    function _burn(
        address _from,
        uint256 _id,
        uint256 _value
    ) internal {
        _onBeforeTransfer(_from, address(0), _id, _value);

        balances[_id][_from] -= _value;

        emit TransferSingle(msg.sender, _from, address(0), _id, _value);

        _doSafeTransferAcceptanceCheck(msg.sender, _from, address(0), _id, _value, "");
    }

    function _getEnergy(State memory state, uint32 timestamp) internal view returns (uint112) {
        if (state.balance > state.energy) {
            return state.balance - ExpMath.halfLife(state.timestamp, state.balance - state.energy, halfLife, timestamp);
        } else {
            return state.balance + ExpMath.halfLife(state.timestamp, state.energy - state.balance, halfLife, timestamp);
        }
    }

    function _onBeforeTransfer(
        address _from,
        address _to,
        uint256,
        uint256 _value
    ) internal override {
        uint32 timestamp = uint32(block.timestamp);

        if (_from != address(0)) {
            State memory fromState = states[_from];
            fromState.energy = _getEnergy(fromState, timestamp);
            fromState.timestamp = timestamp;
            fromState.balance -= uint112(_value);
            states[_from] = fromState;
        }

        if (_to != address(0)) {
            State memory toState = states[_to];
            toState.energy = _getEnergy(toState, timestamp);
            toState.timestamp = timestamp;
            toState.balance += uint112(_value);
            states[_to] = toState;
        }
    }
}
