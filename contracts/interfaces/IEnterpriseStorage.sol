// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./IInitializableOwnable.sol";
import "./IStakeToken.sol";
import "./IRentalToken.sol";
import "./IConverter.sol";

interface IEnterpriseStorage is IInitializableOwnable {
    struct RentalAgreement {
        // slot 1, 0 bytes left
        uint112 rentalAmount; // 14 bytes
        uint16 powerTokenIndex; // 2 bytes
        uint32 startTime; // 4 bytes
        uint32 endTime; // 4 bytes
        uint32 renterOnlyReturnTime; // 4 bytes
        uint32 enterpriseOnlyCollectionTime; // 4 bytes
        // slot 2, 16 bytes left
        uint112 gcRewardAmount; // 14 bytes
        uint16 gcRewardTokenIndex; // 2 bytes
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
        IERC20Metadata enterpriseToken,
        IStakeToken stakeToken,
        IRentalToken rentalToken
    ) external;

    function getBaseUri() external view returns (string memory);

    function getConverter() external view returns (IConverter);

    function getEnterpriseToken() external view returns (IERC20Metadata);

    function isSupportedPaymentToken(address token) external view returns (bool);

    function getGCFeePercent() external view returns (uint16);

    function getAvailableReserve() external view returns (uint256);

    function getUsedReserve() external view returns (uint256);

    function getReserve() external view returns (uint256);

    function getBondingCurve() external view returns (uint256 pole, uint256 slope);

    function getRentalAgreement(uint256 rentalTokenId) external view returns (RentalAgreement memory);

    function getPaymentToken(uint256 index) external view returns (address);
}
