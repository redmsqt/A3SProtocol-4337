//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../UserOperation.sol";

enum PostOpMode {
    opSucceeded,
    opReverted,
    postOpReverted
}

interface IPaymaster {
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 requestId,
        uint256 maxCost
    ) external returns (bytes memory context);

    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external;
}
