// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import './ExpMath.sol';

/* is ERC1155 */
contract PowerToken {
    struct State {
        uint256 balance;
        uint256 energy;
        uint256 timestamp;
    }

    uint256 public halfLife;
    mapping(uint256 => mapping(address => uint256)) private balances;
    mapping(address => State) private states;

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external {
        require(_to != address(0x0), '_to must be non-zero.');
        require(
            _from == msg.sender, //TODO: || ds.operatorApproval[_from][msg.sender] == true,
            'Need operator approval for 3rd party transfers.'
        );

        State storage fromState = states[_from];
        State storage toState = states[_to];

        fromState.energy = getEnergy(fromState, block.timestamp);
        toState.energy = getEnergy(toState, block.timestamp);

        fromState.timestamp = toState.timestamp = block.timestamp;

        fromState.balance -= _value;
        toState.balance += _value;

        balances[_id][_from] -= _value;
        balances[_id][_to] += _value;
    }

    function energyAt(address who, uint256 timestamp) public view returns (uint256) {
        State storage state = states[who];
        return getEnergy(state, timestamp);
    }

    function getEnergy(State storage state, uint256 timestamp) internal view returns (uint256) {
        if (state.balance > state.energy) {
            return
                state.balance -
                ExpMath.halfLife(state.timestamp, state.balance - state.energy, halfLife, timestamp);
        } else {
            return
                state.balance +
                ExpMath.halfLife(state.timestamp, state.energy - state.balance, halfLife, timestamp);
        }
    }
}
