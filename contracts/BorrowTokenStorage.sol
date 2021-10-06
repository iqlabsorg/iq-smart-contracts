// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBorrowToken.sol";
import "./Enterprise.sol";
import "./EnterpriseOwnable.sol";
import "./token/ERC721Enumerable.sol";

contract BorrowTokenStorage is EnterpriseOwnable, ERC721Enumerable {
    uint256 internal _tokenIdTracker;
    bool internal _allowsTransfer;
}
