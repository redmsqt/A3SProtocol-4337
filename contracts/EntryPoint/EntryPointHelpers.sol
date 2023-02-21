//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../UserOperation.sol";

library EntryPointHelpers {
    using Address for address;

    function _hasPaymaster(UserOperation calldata op)
        internal
        pure
        returns (bool)
    {
        if (op.paymasterAndData.length >= 20) {
            require(
                address(bytes20(op.paymasterAndData[:20])) != address(0),
                "A3SEntryPoint: invalid paymasterAndData."
            );
            return true;
        } else {
            return false;
        }
    }

    function _requestId(UserOperation calldata op)
        internal
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(_hash(op), address(this), block.chainid)
            );
    }

    function _requiredPrefund(UserOperation calldata op)
        internal
        view
        returns (uint256)
    {
        uint256 totalGas = op.callGasLimit +
            op.verificationGasLimit +
            op.preVerificationGas;
        return totalGas * _gasPrice(op);
    }

    function _gasPrice(UserOperation calldata op)
        internal
        view
        returns (uint256)
    {
        return
            op.maxFeePerGas == op.maxPriorityFeePerGas
                ? op.maxFeePerGas
                : Math.min(
                    op.maxFeePerGas,
                    op.maxPriorityFeePerGas + block.basefee
                );
    }

    function _hasInitCode(UserOperation calldata op)
        internal
        pure
        returns (bool)
    {
        return op.initCode.length != 0;
    }

    function _isAlreadyDeployed(UserOperation calldata op)
        internal
        view
        returns (bool)
    {
        return op.sender.isContract();
    }
    
    /**
     *@notice Get salt for create A3SWallet from op.initCode in the current version.
    */
    function _getSaltIfHasInitCode(UserOperation calldata op)
        internal
        pure
        returns (bytes32)
    {
        require(_hasInitCode(op), "A3SEntryPoint: no initCode.");
        require(op.initCode.length == 32, "A3SEntryPoint: initCode must be bytes32.");
        return bytes32(op.initCode);
    }

    function _getPaymasterAddress(UserOperation calldata op)
        internal
        pure
        returns (address paymaster)
    {
        require(
            op.paymasterAndData.length >= 20,
            "A3SEntryPoint: invalid paymasterAndData."
        );
        paymaster = address(bytes20(op.paymasterAndData[:20]));
    }

    function _hash(UserOperation calldata op) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    op.sender,
                    op.nonce,
                    keccak256(op.initCode),
                    keccak256(op.callData),
                    op.callGasLimit,
                    op.verificationGasLimit,
                    op.preVerificationGas,
                    op.maxFeePerGas,
                    op.maxPriorityFeePerGas,
                    keccak256(op.paymasterAndData)
                )
            );
    }
}