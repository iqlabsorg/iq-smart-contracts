// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;
import "./interfaces/ILoanCostEstimator.sol";
import "./interfaces/IEnterprise.sol";

contract DefaultLoanCostEstimator is ILoanCostEstimator {
    IEnterprise private _enterprise;

    function initialize(IEnterprise enterprise) external override {
        require(address(enterprise) != address(0), "Zero address");
        require(address(_enterprise) == address(0), "Already initialized");

        _enterprise = enterprise;
    }

    function estimateCost(
        IPowerToken powerToken,
        uint112 amount,
        uint32 duration
    ) external view override returns (uint112) {
        EnterpriseConfigurator configurator = _enterprise.getConfigurator();

        uint256 totalCost = uint112((uint256(amount) * duration * configurator.getFactor(powerToken)));

        // loanReturnLien = totalCost * 0.05;

        // enterpriseFee = totalCost * _enterpriseFee;

        // interest = totalCost - enterpriseFee;

        // uint112 interestInLiquidityTokens = interest > type(uint112).max ? type(uint112).max : uint112(interest);

        // uint256 uintInterestInLiquidityTokens = _reserve / (_availableReserve - amount); BONDING

        // convertTo(interestInLiquidityTokens, interestPaymentToken),

        return uint112(totalCost);
    }

    function estimateLien(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    ) external view override returns (uint112) {}

    function notifyNewLoan(uint256 tokenId) external override {}
}
