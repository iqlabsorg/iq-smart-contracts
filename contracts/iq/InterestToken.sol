// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "./ERC1155Base.sol";
import "./Enterprise.sol";

contract InterestToken is ERC1155Base {
    Enterprise public enterprise;

    constructor(
        Enterprise _enterprise,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) ERC1155Base(_name, _symbol, _baseUri) {
        enterprise = _enterprise;
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
