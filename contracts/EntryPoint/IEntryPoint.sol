//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../UserOperation.sol";

interface IEntryPoint {
    struct UserOpVerification {
        bytes context;
        uint256 prefund;
        uint256 gasUsed;
        bytes32 requestId;
    }

    event UserOperationExecuted(
        address indexed sender,
        address indexed paymaster,
        bytes32 requestId,
        bool success,
        bytes result
    );

    function handleOps(
        UserOperation[] calldata ops,
        address payable beneficiary
    ) external;

    function simulateValidation(UserOperation calldata userOp)
        external
        returns (uint256 preOpGas, uint256 prefund);
}