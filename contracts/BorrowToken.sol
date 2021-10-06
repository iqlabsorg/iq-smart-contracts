// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBorrowToken.sol";
import "./Enterprise.sol";
import "./BorrowTokenStorage.sol";

contract BorrowToken is BorrowTokenStorage, IBorrowToken {
    using SafeERC20 for IERC20;

    event TransfersAllowed();

    function initialize(
        string memory name,
        string memory symbol,
        Enterprise enterprise
    ) external {
        EnterpriseOwnable.initialize(enterprise);
        ERC721.initialize(name, symbol);
        _allowsTransfer = false;
    }

    function getNextTokenId() public view override returns (uint256) {
        return uint256(keccak256(abi.encodePacked("b", address(this), _tokenIdTracker)));
    }

    function _baseURI() internal view override returns (string memory) {
        string memory baseURI = getEnterprise().getBaseUri();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, "borrow/")) : "";
    }

    function mint(address to) external override onlyEnterprise returns (uint256) {
        uint256 tokenId = getNextTokenId();
        _safeMint(to, tokenId);
        _tokenIdTracker++;
        return tokenId;
    }

    function burn(uint256 tokenId, address burner) external override onlyEnterprise {
        Enterprise enterprise = getEnterprise();
        Enterprise.LoanInfo memory loan = enterprise.getLoanInfo(tokenId);
        IERC20 paymentToken = IERC20(enterprise.getPaymentToken(loan.gcFeeTokenIndex));
        paymentToken.safeTransfer(burner, loan.gcFee);

        _burn(tokenId);
    }

    function allowTransferForever() external onlyEnterpriseOwner {
        require(!_allowsTransfer, Errors.BT_TRANSFER_ALREADY_ALLOWED);

        _allowsTransfer = true;
        emit TransfersAllowed();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(from == address(0) || to == address(0) || _allowsTransfer, Errors.BT_TRANSFER_NOT_ALLOWED);

        super._beforeTokenTransfer(from, to, tokenId);
        getEnterprise().loanTransfer(from, to, tokenId);
    }
}
