// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "./Enterprise.sol";

/**
 * @dev Ownable contract with `initialize` function instead of constructor. Primary usage is for proxies like ERC-1167 with no constructor.
 */
abstract contract EnterpriseOwnable {
    Enterprise private _enterprise;

    /**
     * @dev Initializes the enterprise of the contract. The inheritor of this contract *MUST* ensure this method is not called twice.
     */
    function initialize(Enterprise enterprise) public {
        require(address(_enterprise) == address(0), "EnterpriseOwnable: already initialized");
        require(address(enterprise) != address(0), "EnterpriseOwnable: invalid enterprise");
        _enterprise = enterprise;
    }

    /**
     * @dev Returns the address of the current enterprise.
     */
    function getEnterprise() public view returns (Enterprise) {
        return _enterprise;
    }

    /**
     * @dev Throws if called by any account other than the enterprise.
     */
    modifier onlyEnterprise() {
        require(address(_enterprise) == msg.sender, "EnterpriseOwnable: caller is not Enterprise");
        _;
    }
}
