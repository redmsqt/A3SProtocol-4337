//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../UserOperation.sol";

interface IA3SWallet {
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 requestId,
        uint256 missingWalletFunds
    ) external;

    function executeUserOp(
        address to,
        uint256 value,
        bytes calldata data
    ) external;

    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);
}