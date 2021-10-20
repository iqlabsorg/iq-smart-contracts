// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "./libs/Errors.sol";
import "./interfaces/IInitializableOwnable.sol";

/**
 * @dev Ownable contract with `initialize` function instead of constructor. Primary usage is for proxies like ERC-1167 with no constructor.
 */
abstract contract InitializableOwnable is IInitializableOwnable {
    // This is the keccak-256 hash of "iq.protocol.owner" subtracted by 1
    bytes32 private constant _OWNER_SLOT = 0x4f471908b72bb76dae5bd24599026e7bf3ddb256497722888ffa422f83729ede;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the owner of the contract. The inheritor of this contract *MUST* ensure this method is not called twice.
     */
    function initialize(address initialOwner) public {
        require(owner() == address(0), Errors.ALREADY_INITIALIZED);
        require(initialOwner != address(0), Errors.IO_INVALID_OWNER_ADDRESS);
        StorageSlot.getAddressSlot(_OWNER_SLOT).value = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view override returns (address) {
        return StorageSlot.getAddressSlot(_OWNER_SLOT).value;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, Errors.CALLER_NOT_OWNER);
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), Errors.IO_INVALID_OWNER_ADDRESS);
        emit OwnershipTransferred(owner(), newOwner);
        StorageSlot.getAddressSlot(_OWNER_SLOT).value = newOwner;
    }
}
