// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./IEnterpriseStorage.sol";

interface IEnterprise is IEnterpriseStorage {
    function transferRental(
        address from,
        address to,
        uint256 rentalTokenId
    ) external;
}
