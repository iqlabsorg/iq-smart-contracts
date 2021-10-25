// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IPowerTokenStorage.sol";

interface IPowerToken is IERC20Metadata, IPowerTokenStorage {
    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function mint(address account, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function estimateLoanDetailed(
        address paymentToken,
        uint112 amount,
        uint32 duration
    )
        external
        view
        returns (
            uint112 interest, // TODO: poolFee
            uint112 serviceFee,
            uint112 gcFee
        );

    function notifyNewLoan(uint256 borrowTokenId) external;

    function estimateLoan(
        address paymentToken,
        uint112 amount,
        uint32 duration
    ) external view returns (uint256);
}
