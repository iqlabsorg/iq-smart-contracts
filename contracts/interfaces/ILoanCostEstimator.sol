// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "./IPowerToken.sol";
import "./IEnterprise.sol";

interface ILoanCostEstimator {
    function initialize(IEnterprise enterprise) external;

    function estimateCost(
        IPowerToken powerToken,
        uint112 amount,
        uint32 duration
    ) external view returns (uint112);

    function notifyNewLoan(uint256 tokenId) external;
}
