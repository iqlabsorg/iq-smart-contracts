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

    function notifyNewRental(uint256 rentalTokenId) external;

    function estimateRentalFee(
        address paymentToken,
        uint112 rentalAmount,
        uint32 rentalPeriod
    )
        external
        view
        returns (
            uint112 poolFee,
            uint112 serviceFee,
            uint112 gcFee
        );
}
