// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "../../token/IERC20Detailed.sol";
import "../interfaces/IInitializableOwnable.sol";

interface IPowerToken is IERC20Detailed, IInitializableOwnable {
    function initialize(
        string memory name,
        string memory symbol,
        uint32 halfLife,
        uint32[] memory allowedLoanDurations,
        uint112 factor,
        uint32 interestRateHalvingPeriod,
        address owner
    ) external;

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function mint(
        address account,
        uint256 amount,
        bool withLocks
    ) external;

    function burnFrom(
        address account,
        uint256 amount,
        bool withLocks
    ) external;

    function getHalfLife() external view returns (uint32);

    function getLastDeal() external view returns (uint32);

    function getFactor() external view returns (uint112);

    function getInterestRateHalvingPeriod() external view returns (uint32);

    function isAllowedLoanDuration(uint32 duration) external view returns (bool);
}
