// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBorrowToken.sol";
import "./Enterprise.sol";
import "./BorrowTokenStorage.sol";

contract BorrowToken is BorrowTokenStorage, IBorrowToken {
    using SafeERC20 for IERC20;

    event TransfersAllowed();

    function mint(address to) external override onlyEnterprise returns (uint256) {
        uint256 tokenId = getNextTokenId();
        _safeMint(to, tokenId);
        _tokenIdTracker++;
        return tokenId;
    }

    function burn(uint256 tokenId, address burner) external override onlyEnterprise {
        IEnterprise enterprise = getEnterprise();
        Enterprise.LoanInfo memory loan = enterprise.getLoanInfo(tokenId);
        IERC20 paymentToken = IERC20(enterprise.getPaymentToken(loan.gcFeeTokenIndex));
        paymentToken.safeTransfer(burner, loan.gcFee);

        _burn(tokenId);
    }

    function enableTransfersForever() external onlyEnterpriseOwner {
        require(!_transfersEnabled, Errors.BT_TRANSFERS_ALREADY_ENABLED);

        _transfersEnabled = true;
        emit TransfersAllowed();
    }

    function getNextTokenId() public view override returns (uint256) {
        return uint256(keccak256(abi.encodePacked("b", address(this), _tokenIdTracker)));
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(from == address(0) || to == address(0) || _transfersEnabled, Errors.BT_TRANSFERS_DISABLED);

        super._beforeTokenTransfer(from, to, tokenId);
        getEnterprise().loanTransfer(from, to, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        string memory baseURI = getEnterprise().getBaseUri();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, "borrow/")) : "";
    }
}
