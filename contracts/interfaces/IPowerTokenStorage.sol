// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IEnterprise.sol";

interface IPowerTokenStorage {
    function initialize(
        IEnterprise enterprise,
        uint112 baseRate,
        uint96 minGCFee,
        uint32 gapHalvingPeriod,
        uint16 index,
        IERC20Metadata baseToken
    ) external;

    function initialize2(
        uint32 minLoanDuration,
        uint32 maxLoanDuration,
        uint16 serviceFeePercent,
        bool wrappingEnabled
    ) external;

    function isAllowedLoanDuration(uint32 duration) external view returns (bool);

    function getIndex() external view returns (uint16);

    function isWrappingEnabled() external view returns (bool);

    function isTransfersEnabled() external view returns (bool);
}
