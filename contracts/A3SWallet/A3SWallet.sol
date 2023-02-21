//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./IA3SWalletFactory.sol";
import "./IA3SWallet.sol";
import "../helper/Calls.sol";
import "../UserOperation.sol";

contract A3SWallet is IA3SWallet, ERC721Holder, ERC1155Holder {
    using ECDSA for bytes32;
    using Calls for address;
    using Calls for address payable;
    address private immutable _entryPoint;
    address private immutable _factory;
    uint256 private nonce;

    modifier onlyEntryPoint() {
        require(
            msg.sender == _entryPoint,
            "A3SWallet: Sender must be entrypoint"
        );
        _;
    }

    receive() external payable {}

    constructor (address entryPoint_, address factory_) {
        _entryPoint = entryPoint_;
        _factory = factory_;
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 requestId,
        uint256 missingWalletFunds
    ) external override onlyEntryPoint {
        require(nonce++ == userOp.nonce, "A3SWallet: Invalid nonce");

        bytes32 hash = requestId.toEthSignedMessageHash();
        require(IA3SWalletFactory(_factory).getWalletOwnerOf(userOp.sender) == hash.recover(userOp.signature),"A3SWallet: Invalid signature");

        if (missingWalletFunds != 0) {
            payable(msg.sender).sendValue(missingWalletFunds, "A3SWallet: failed to refund.");
        }
    }

    function executeUserOp(
        address to,
        uint256 value,
        bytes calldata data
    ) external override onlyEntryPoint {
        to.callWithValue(data, value, "A3SWallet: Execute UserOp failed.");
    }

    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4)
    {
        require(
            IA3SWalletFactory(_factory).getWalletOwnerOf(address(this)) ==
                hash.recover(signature),
            "A3SWallet: Invalid signature"
        );
        return IERC1271.isValidSignature.selector;
    }
}