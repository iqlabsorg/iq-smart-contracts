// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "./ERC1155Base.sol";
import "./interfaces/IEnterprise.sol";

contract InterestToken is ERC1155Base {
    IEnterprise public enterprise;

    function initialize(
        address _enterprise,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) public {
        enterprise = IEnterprise(_enterprise);
        initialize(_name, _symbol, _baseUri);
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
