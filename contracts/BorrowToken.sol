// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IEnterprise.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IPowerToken.sol";
import "./InitializableOwnable.sol";
import "./token/ERC721.sol";

contract BorrowToken is IBorrowToken, InitializableOwnable, ERC721 {
    using SafeERC20 for IERC20;
    IEnterprise private _enterprise;
    uint256 private _counter = 1;

    function initialize(
        string memory name,
        string memory symbol,
        string memory baseUri
    ) external override {
        InitializableOwnable.initialize(msg.sender);
        ERC721.initialize(name, symbol);
        _setBaseURI(baseUri);
        _enterprise = IEnterprise(msg.sender);
    }

    function getCounter() external view override returns (uint256) {
        return _counter;
    }

    function mint(address to) external override onlyOwner returns (uint256) {
        uint256 tokenId = _counter;
        _safeMint(to, tokenId);
        _counter++;
        return tokenId;
    }

    function burn(uint256 tokenId, address burner) external override onlyOwner {
        _burn(tokenId);
        IEnterprise.LoanInfo memory loan = _enterprise.getLoanInfo(tokenId);
        IERC20 lienToken = IERC20(_enterprise.supportedInterestTokens(loan.lienTokenIndex));

        lienToken.safeTransfer(burner, loan.lien);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        _enterprise.loanTransfer(from, to, tokenId);
    }
}
