//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./IEntryPoint.sol";
import "./EntryPointStaking.sol";
import "./EntryPointHelpers.sol";
import "../UserOperation.sol";
import "../helper/Calls.sol";
import "../Paymaster/IPaymaster.sol";
import "../A3SWallet/IA3SWallet.sol";
import "../A3SWallet/IA3SWalletFactory.sol";

contract EntryPoint is IEntryPoint, EntryPointStaking {
    using ECDSA for bytes32;
    using Calls for address;
    using Calls for address payable;
    using EntryPointHelpers for uint256;
    using EntryPointHelpers for address;
    using EntryPointHelpers for UserOperation;

    address private immutable _walletFactory;

    constructor(uint32 unstakeDelaySec_, address walletFactory_)
        EntryPointStaking(unstakeDelaySec_)
    {
        _walletFactory = walletFactory_;
    }

    function simulateValidation(UserOperation calldata userOp)
        external
        returns (uint256 preOpGas, uint256 prefund)
    {
        require(msg.sender == address(0), "A3SEntryPoint: Caller not be zero.");

        uint256 preGas = gasleft();
        UserOpVerification memory verification = _verifyOp(userOp);
        preOpGas = preGas - gasleft() + userOp.preVerificationGas;

        prefund = verification.prefund;
    }

    function handleOps(
        UserOperation[] calldata ops,
        address payable beneficiary
    ) external {
        UserOpVerification[] memory verifications = new UserOpVerification[](
            ops.length
        );
        for (uint256 i = 0; i < ops.length; i++) {
            verifications[i] = _verifyOp(ops[i]);
        }
        uint256 totalGasCost;
        for (uint256 i = 0; i < ops.length; i++) {
            totalGasCost += _executeOp(ops[i], verifications[i]);
        }

        beneficiary.sendValue(totalGasCost, "A3SEntryPoint: Failed to redeem.");
    }

    function _verifyOp(UserOperation calldata op)
        internal
        returns (UserOpVerification memory verification)
    {
        uint256 gasLeftBeforeVerify = gasleft();

        bytes32 requestId = op._requestId();
        _createWalletIfNecessary(op, requestId);

        uint256 prefund = op._requiredPrefund();
        _validateWallet(op, requestId, prefund);

        uint256 walletVerifyGasUsed = gasLeftBeforeVerify - gasleft();

        require(
            op.verificationGasLimit >= walletVerifyGasUsed,
            "A3SEntryPoint: verify Gas is not enough."
        );
        uint256 verificationPaymasterGasLimit = op.verificationGasLimit -
            walletVerifyGasUsed;

        verification.prefund = prefund;
        verification.requestId = requestId;

        if (op._hasPaymaster()) {
            verification.context = _validatePaymaster(
                op,
                requestId,
                prefund,
                verificationPaymasterGasLimit
            );
        } else {
            verification.context = new bytes(0);
        }

        uint256 verificationGasUsed = gasLeftBeforeVerify - gasleft();
        verification.gasUsed = verificationGasUsed;
    }

    function _executeOp(
        UserOperation calldata op,
        UserOpVerification memory verification
    ) internal returns (uint256) {
        uint256 gasLeftBeforeExecution = gasleft();

        (bool executeSuccess, bytes memory result) = op.sender.call{
            gas: op.callGasLimit
        }(op.callData);

        address paymasterAddr = op._hasPaymaster()
            ? op._getPaymasterAddress()
            : address(0);

        emit UserOperationExecuted(
            op.sender,
            paymasterAddr,
            verification.requestId,
            executeSuccess,
            result
        );

        uint256 executionGasUsed = gasLeftBeforeExecution - gasleft();

        uint256 totalGasUsed = verification.gasUsed + executionGasUsed;
        uint256 totalGasCost = totalGasUsed * op._gasPrice();

        if (op._hasPaymaster()) {
            totalGasCost = _executePostOp(
                op,
                verification,
                gasLeftBeforeExecution,
                totalGasCost,
                executeSuccess
            );
        } else {
            require(
                verification.prefund >= totalGasCost,
                "A3SEntryPoint: Insufficient refund"
            );
            uint256 refund = verification.prefund - totalGasCost;

            payable(op.sender).sendValue(
                refund,
                "A3SEntryPoint: Failed to refund."
            );
        }
        return totalGasCost;
    }

    /**
     *@notice Get salt for create A3SWallet from op.initCode in the current version.
    */
    function _createWalletIfNecessary(
        UserOperation calldata op,
        bytes32 requestId
    ) internal {
        bool hasInitCode = op._hasInitCode();
        bool isAlreadyDeployed = op._isAlreadyDeployed();
        bool isProperlyFormed = (isAlreadyDeployed && !hasInitCode) ||
            (!isAlreadyDeployed && hasInitCode);
        require(isProperlyFormed, "A3SEntryPoint: Incorrect initCode.");

        if (!isAlreadyDeployed) {
            bytes32 hash = requestId.toEthSignedMessageHash();
            address user = hash.recover(op.signature);
            bytes32 salt = op._getSaltIfHasInitCode();
            IA3SWalletFactory(_walletFactory).safeMint(user, salt);
        }
    }

    function _validateWallet(
        UserOperation calldata op,
        bytes32 requestId,
        uint256 prefund
    ) internal {
        uint256 requiredPrefund = op._hasPaymaster() ? 0 : prefund;
        uint256 initBalance = address(this).balance;

        bytes32 hash = requestId.toEthSignedMessageHash();
        require(
            IA3SWalletFactory(_walletFactory).getWalletOwnerOf(op.sender) ==
                hash.recover(op.signature),
            "A3SEntryPoint: Invalid signature"
        );

        IA3SWallet(op.sender).validateUserOp{gas: op.verificationGasLimit}(
            op,
            requestId,
            requiredPrefund
        );
        uint256 actualPrefund = address(this).balance - initBalance;

        require(
            actualPrefund >= requiredPrefund,
            "A3SEntryPoint: Incorrect prefund."
        );
    }

    function _validatePaymaster(
        UserOperation calldata op,
        bytes32 requestId,
        uint256 prefund,
        uint256 verificationPaymasterGasLimit
    ) internal returns (bytes memory result) {
        address paymaster = op._getPaymasterAddress();

        require(isStaked(paymaster), "A3SEntryPoint: Not staked.");
        _decreaseStake(paymaster, prefund);

        result = IPaymaster(paymaster).validatePaymasterUserOp{
            gas: verificationPaymasterGasLimit
        }(op, requestId, prefund);
    }

    function _executePostOp(
        UserOperation calldata op,
        UserOpVerification memory verification,
        uint256 gasLeftBeforeExecution,
        uint256 gasCost,
        bool success
    ) internal returns (uint256) {
        uint256 gasPrice = op._gasPrice();
        uint256 actualGasCost;

        PostOpMode mode = success
            ? PostOpMode.opSucceeded
            : PostOpMode.opReverted;

        try
            IPaymaster(op._getPaymasterAddress()).postOp(
                mode,
                verification.context,
                gasCost
            )
        {
            uint256 totalGasUsed = verification.gasUsed +
                (gasLeftBeforeExecution - gasleft());
            actualGasCost = totalGasUsed * gasPrice;
        } catch {
            uint256 gasUsedIncludingPostOp = verification.gasUsed +
                (gasLeftBeforeExecution - gasleft());
            uint256 gasCostIncludingPostOp = gasUsedIncludingPostOp * gasPrice;

            IPaymaster(op._getPaymasterAddress()).postOp(
                PostOpMode.postOpReverted,
                verification.context,
                gasCostIncludingPostOp
            );

            uint256 totalGasUsed = verification.gasUsed +
                (gasLeftBeforeExecution - gasleft());
            actualGasCost = totalGasUsed * gasPrice;
        }

        require(
            verification.prefund >= actualGasCost,
            "A3SEntryPoint: Insufficient refund"
        );
        uint256 refund = verification.prefund - actualGasCost;
        _increaseStake(op._getPaymasterAddress(), refund);
        return actualGasCost;
    }
}