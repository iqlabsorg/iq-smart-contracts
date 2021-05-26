// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
pragma abicoder v2;

import "../EnterpriseConfigurator.sol";

interface IEnterprise {
    struct LoanInfo {
        uint112 amount; // 14 bytes
        uint16 powerTokenIndex; // 2 bytes, index in powerToken array
        uint32 borrowingTime; // 4 bytes
        uint32 maturityTime; // 4 bytes
        uint32 borrowerReturnGraceTime; // 4 bytes
        uint32 enterpriseCollectGraceTime; // 4 bytes
        // slot 1, 0 bytes left
        uint112 lien; // 14 bytes, loan return reward
        uint16 lienTokenIndex; // 2 bytes, index in supportedInterestTokens array
        // slot 2, 16 bytes left
    }

    function initialize(string memory enterpriseName, EnterpriseConfigurator configurator) external;

    function loanTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function getConfigurator() external view returns (EnterpriseConfigurator);

    function getLoanInfo(uint256 tokenId) external view returns (LoanInfo memory);

    function getReserve() external view returns (uint256);

    function getAvailableReserve() external view returns (uint256);
}
