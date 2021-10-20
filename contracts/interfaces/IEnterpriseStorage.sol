// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./IInitializableOwnable.sol";
import "./IInterestToken.sol";
import "./IBorrowToken.sol";
import "./IConverter.sol";

interface IEnterpriseStorage is IInitializableOwnable {
    struct LoanInfo {
        // slot 1, 0 bytes left
        uint112 amount; // 14 bytes
        uint16 powerTokenIndex; // 2 bytes, index in powerToken array
        uint32 borrowingTime; // 4 bytes
        uint32 maturityTime; // 4 bytes
        uint32 borrowerReturnGraceTime; // 4 bytes
        uint32 enterpriseCollectGraceTime; // 4 bytes
        // slot 2, 16 bytes left
        uint112 gcFee; // 14 bytes, loan return reward
        uint16 gcFeeTokenIndex; // 2 bytes, index in `_paymentTokens` array
    }

    function initialize(
        string memory enterpriseName,
        string calldata baseUri,
        uint16 gcFeePercent,
        IConverter converter,
        ProxyAdmin proxyAdmin,
        address initialOwner
    ) external;

    function initializeTokens(
        IERC20Metadata liquidityToken,
        IInterestToken interestToken,
        IBorrowToken borrowToken
    ) external;

    function getBaseUri() external view returns (string memory);

    function getConverter() external view returns (IConverter);

    function getLiquidityToken() external view returns (IERC20Metadata);

    function isSupportedPaymentToken(address token) external view returns (bool);

    function getGCFeePercent() external view returns (uint16);

    function getAvailableReserve() external view returns (uint256);

    function getUsedReserve() external view returns (uint256);

    function getReserve() external view returns (uint256);

    function getBondingCurve() external view returns (uint256 pole, uint256 slope);

    function getLoanInfo(uint256 borrowTokenId) external view returns (LoanInfo memory);

    function getPaymentToken(uint256 index) external view returns (address);
}
