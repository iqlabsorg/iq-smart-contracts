// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "./IPowerToken.sol";
import "../Enterprise.sol";

interface IEstimator {
    function initialize(Enterprise enterprise) external;

    function initializeService(IPowerToken powerToken) external;

    function estimateCost(
        IPowerToken powerToken,
        uint112 amount,
        uint32 duration
    ) external view returns (uint112);

    function notifyNewLoan(uint256 tokenId) external;
}
