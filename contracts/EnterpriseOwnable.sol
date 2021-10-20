// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./interfaces/IEnterprise.sol";
import "./libs/Errors.sol";

/**
 * @dev Ownable contract with `initialize` function instead of constructor. Primary usage is for proxies like ERC-1167 with no constructor.
 */
abstract contract EnterpriseOwnable {
    IEnterprise private _enterprise;

    /**
     * @dev Initializes the enterprise of the contract. The inheritor of this contract *MUST* ensure this method is not called twice.
     */
    function initialize(IEnterprise enterprise) public {
        require(address(_enterprise) == address(0), Errors.ALREADY_INITIALIZED);
        require(address(enterprise) != address(0), Errors.EO_INVALID_ENTERPRISE_ADDRESS);
        _enterprise = IEnterprise(enterprise);
    }

    /**
     * @dev Returns the address of the current enterprise.
     */
    function getEnterprise() public view returns (IEnterprise) {
        return _enterprise;
    }

    /**
     * @dev Throws if called by any account other than the enterprise.
     */
    modifier onlyEnterprise() {
        require(address(_enterprise) == msg.sender, Errors.CALLER_NOT_ENTERPRISE);
        _;
    }

    modifier onlyEnterpriseOwner() {
        require(_enterprise.owner() == msg.sender, Errors.CALLER_NOT_OWNER);
        _;
    }
}
