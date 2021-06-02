// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/**
 * @dev Ownable contract with `initialize` function instead of constructor. Primary usage is for proxies like ERC-1167 with no constructor.
 */
abstract contract InitializableOwnable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the owner of the contract. The inheritor of this contract *MUST* ensure this method is not called twice.
     */
    function initialize(address initialOwner) public {
        require(_owner == address(0), "InitializableOwnable: already initialized");
        require(initialOwner != address(0), "InitializableOwnable: invalid initial owner");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}