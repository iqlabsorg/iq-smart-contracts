// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "./interfaces/IInitializableOwnable.sol";

/**
 * @dev Ownable contract with `initialize` function instead of contructor. Primary usage is for proxies like ERC-1167 with no constructor.
 */
abstract contract InitializableOwnable is IInitializableOwnable {
    mapping(address => bool) private _owners;
    uint256 private _ownerCount;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the owner of the contract. The inheritor of this contract *MUST* ensure this method is not called twice.
     */
    function initialize(address initialOwner) public virtual {
        require(_ownerCount == 0, "InitializableOwnable: already initialized");
        _owners[initialOwner] = true;
        _ownerCount = 1;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function isOwner(address account) public view virtual returns (bool) {
        return _owners[account];
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owners[msg.sender] == true, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address currentOwner, address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        require(isOwner(currentOwner), "Not an owner");
        emit OwnershipTransferred(currentOwner, newOwner);
        _owners[currentOwner] = false;
        _owners[newOwner] = true;
    }

    function addOwner(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(address(0), newOwner);
        _owners[newOwner] = true;
        _ownerCount++;
    }

    function renounceOwnership() public virtual onlyOwner {
        _ownerCount--;
        _owners[msg.sender] = false;
        emit OwnershipTransferred(msg.sender, address(0));
    }
}
