// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./ERC1155Base.sol";

contract InterestToken is ERC1155Base {
    ERC20 public liquidityToken;

    constructor(
        ERC20 _liquidityToken,
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) ERC1155Base(_name, _symbol, _baseUri) {
        liquidityToken = _liquidityToken;
    }

    function mint(address _to, uint256 _amount) public {}

    function lend(address _to, uint256 _amount) public {}

    function getRate() public view returns (uint256) {}
}
