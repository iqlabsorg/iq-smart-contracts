// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./ERC1155Base.sol";
import "./RentingPool.sol";

contract InterestToken is ERC1155Base {
    RentingPool public rentingPool;

    constructor(
        RentingPool _rentingPool,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) ERC1155Base(_name, _symbol, _baseUri) {
        rentingPool = _rentingPool;
    }

    function mint(
        address _to,
        uint256 _id,
        uint256 _amount
    ) public {
        //TODO: checks
        _mint(_to, _id, uint112(_amount), "");
    }

    function lend(
        address _to,
        uint256 _id,
        uint256 _amount
    ) public {}

    function getRate() public view returns (uint256) {}
}
