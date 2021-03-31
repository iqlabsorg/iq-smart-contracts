// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

import "@openzeppelin/contracts/utils/Address.sol";
import "./ExpMath.sol";
import "../erc1155/IERC1155.sol";
import "../erc1155/IERC1155Metadata.sol";
import "../erc1155/IERC1155TokenReceiver.sol";
import "../erc1155/Common.sol";

contract ERC1155Base is IERC1155, CommonConstants, ERC1155Metadata_URI {
    using Address for address;

    string public name;
    string public symbol;
    string private baseUri;
    address public owner;
    mapping(uint256 => mapping(address => uint256)) internal balances;
    mapping(address => mapping(address => bool)) private operatorApprovals;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseUri
    ) {
        name = _name;
        symbol = _symbol;
        baseUri = _baseUri;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not an owner");
        _;
    }

    function uri(uint256) public view override returns (string memory) {
        return baseUri;
    }

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external override {
        require(_value < type(uint112).max, "Value out of bounds");
        require(_to != address(0x0), "_to must be non-zero.");
        require(
            _from == msg.sender || operatorApprovals[_from][msg.sender] == true,
            "Need operator approval for 3rd party transfers."
        );

        _transfer(_from, _to, _id, _value);

        emit TransferSingle(msg.sender, _from, _to, _id, _value);

        _doSafeTransferAcceptanceCheck(msg.sender, _from, _to, _id, _value, _data);
    }

    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external override {
        // MUST Throw on errors
        require(_to != address(0x0), "destination address must be non-zero.");
        require(_ids.length == _values.length, "_ids and _values array length must match.");
        require(
            _from == msg.sender || operatorApprovals[_from][msg.sender] == true,
            "Need operator approval for 3rd party transfers."
        );

        for (uint256 i = 0; i < _ids.length; ++i) {
            _transfer(_from, _to, _ids[i], _values[i]);
        }

        // Note: instead of the below batch versions of event and acceptance check you MAY have emitted a TransferSingle
        // event and a subsequent call to _doSafeTransferAcceptanceCheck in above loop for each balance change instead.
        // Or emitted a TransferSingle event for each in the loop and then the single _doSafeBatchTransferAcceptanceCheck below.
        // However it is implemented the balance changes and events MUST match when a check (i.e. calling an external contract) is done.

        // MUST emit event
        emit TransferBatch(msg.sender, _from, _to, _ids, _values);

        // Now that the balances are updated and the events are emitted,
        // call onERC1155BatchReceived if the destination is a contract.
        _doSafeBatchTransferAcceptanceCheck(msg.sender, _from, _to, _ids, _values, _data);
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");
        return balances[id][account];
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");

        uint256[] memory batchBalances = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(msg.sender != operator, "ERC1155: setting approval status for self");

        operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator) public view virtual override returns (bool) {
        return operatorApprovals[account][operator];
    }

    /////////////////////////////////////////// Internal //////////////////////////////////////////////

    function _mint(
        address _to,
        uint256 _id,
        uint256 _value,
        bytes memory _data
    ) internal {
        _onBeforeTransfer(address(0), _to, _id, _value);

        balances[_id][_to] += _value;

        emit TransferSingle(msg.sender, address(0), _to, _id, _value);

        _doSafeTransferAcceptanceCheck(msg.sender, address(0), _to, _id, _value, _data);
    }

    function _onBeforeTransfer(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value
    ) internal virtual {}

    function _transfer(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value
    ) internal virtual {
        _onBeforeTransfer(_from, _to, _id, _value);

        balances[_id][_from] -= _value;
        balances[_id][_to] += _value;
    }

    function _doSafeTransferAcceptanceCheck(
        address _operator,
        address _from,
        address _to,
        uint256 _id,
        uint256 _value,
        bytes memory _data
    ) internal {
        // If this was a hybrid standards solution you would have to check ERC165(_to).supportsInterface(0x4e2312e0) here but as this is a pure implementation of an ERC-1155 token set as recommended by
        // the standard, it is not necessary. The below should revert in all failure cases i.e. _to isn't a receiver, or it is and either returns an unknown value or it reverts in the call to indicate non-acceptance.

        // Note: if the below reverts in the onERC1155Received function of the _to address you will have an undefined revert reason returned rather than the one in the require test.
        // If you want predictable revert reasons consider using low level _to.call() style instead so the revert does not bubble up and you can revert yourself on the ERC1155_ACCEPTED test.
        if (_to.isContract()) {
            require(
                ERC1155TokenReceiver(_to).onERC1155Received(_operator, _from, _id, _value, _data) == ERC1155_ACCEPTED,
                "contract returned an unknown value from onERC1155Received"
            );
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address _operator,
        address _from,
        address _to,
        uint256[] memory _ids,
        uint256[] memory _values,
        bytes memory _data
    ) internal {
        // If this was a hybrid standards solution you would have to check ERC165(_to).supportsInterface(0x4e2312e0) here but as this is a pure implementation of an ERC-1155 token set as recommended by
        // the standard, it is not necessary. The below should revert in all failure cases i.e. _to isn't a receiver, or it is and either returns an unknown value or it reverts in the call to indicate non-acceptance.

        // Note: if the below reverts in the onERC1155BatchReceived function of the _to address you will have an undefined revert reason returned rather than the one in the require test.
        // If you want predictable revert reasons consider using low level _to.call() style instead so the revert does not bubble up and you can revert yourself on the ERC1155_BATCH_ACCEPTED test.
        if (_to.isContract()) {
            require(
                ERC1155TokenReceiver(_to).onERC1155BatchReceived(_operator, _from, _ids, _values, _data) ==
                    ERC1155_BATCH_ACCEPTED,
                "contract returned an unknown value from onERC1155BatchReceived"
            );
        }
    }
}
