// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "../../erc1155/IERC1155.sol";

interface IInterestToken is IERC1155 {
    function initialize(
        address _enterprise,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) external;

    function mint(
        address _to,
        uint256 _id,
        uint256 _amount
    ) external;
}
