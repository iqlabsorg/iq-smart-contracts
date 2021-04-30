// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "../../erc1155/IERC1155.sol";

interface IPowerToken is IERC1155 {
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _baseUri,
        uint32 _halfLife
    ) external;

    function mint(
        address _to,
        uint256 _id,
        uint256 _value,
        bytes memory _data
    ) external;

    function burn(
        address _account,
        uint256 _id,
        uint256 _value
    ) external;
}
