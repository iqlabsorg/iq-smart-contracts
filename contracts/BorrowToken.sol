// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBorrowToken.sol";
import "./Enterprise.sol";
import "./InitializableOwnable.sol";
import "./token/ERC721Enumerable.sol";

contract BorrowToken is IBorrowToken, InitializableOwnable, ERC721Enumerable {
    using SafeERC20 for IERC20;
    Enterprise private _enterprise;
    uint256 private _counter = 1;

    function initialize(
        string memory name,
        string memory symbol,
        Enterprise enterprise
    ) external {
        InitializableOwnable.initialize(address(enterprise));
        ERC721.initialize(name, symbol);
        _enterprise = enterprise;
    }

    function getCounter() external view override returns (uint256) {
        return _counter;
    }

    function _baseURI() internal view override returns (string memory) {
        string memory baseURI = _enterprise.getBaseUri();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, "borrow/")) : "";
    }

    function mint(address to) external override onlyOwner returns (uint256) {
        uint256 tokenId = _counter;
        _safeMint(to, tokenId);
        _counter++;
        return tokenId;
    }

    function burn(uint256 tokenId, address burner) external override onlyOwner {
        _burn(tokenId);
        Enterprise.LoanInfo memory loan = _enterprise.getLoanInfo(tokenId);
        IERC20 paymentToken = IERC20(_enterprise.supportedPaymentTokens(loan.gcFeeTokenIndex));

        paymentToken.safeTransfer(burner, loan.gcFee);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId);
        _enterprise.loanTransfer(from, to, tokenId);
    }
}
