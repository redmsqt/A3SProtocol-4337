//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../UserOperation.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract testHelper {
    enum PaymasterMode {
        FULL,
        FEE_ONLY,
        GAS_ONLY,
        FREE
    }

    struct PaymasterData {
        uint256 fee;
        PaymasterMode mode;
        IERC20Metadata token;
        AggregatorV3Interface feed;
        bytes signature;
    }

    struct PaymasterContext {
        address sender;
        PaymasterMode mode;
        IERC20Metadata token;
        uint256 rate;
        uint256 fee;
    }

    function testEncodePaymasterRequest(
        UserOperation calldata op,
        address paymasterAddr,
        uint256 fee,
        IERC20Metadata token,
        AggregatorV3Interface feed
    ) public pure returns (bytes32) {
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
                    paymasterAddr,
                    keccak256(
                        abi.encodePacked(
                            fee,
                            PaymasterMode.GAS_ONLY,
                            token,
                            feed
                        )
                    )
                )
            );
    }

    function testPaymasterData(
        uint256 fee,
        IERC20Metadata token,
        AggregatorV3Interface feed,
        bytes memory signature
    ) public pure returns (bytes memory) {
        return abi.encode(fee, PaymasterMode.GAS_ONLY, token, feed, signature);
    }

    function testPaymasterContext(
        UserOperation calldata op,
        PaymasterData memory data,
        uint256 rate
    ) public pure returns (bytes memory context) {
        return abi.encode(op.sender, data.mode, data.token, rate, data.fee);
    }

    function testRequestId(UserOperation calldata op, address targetAddress)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(testHash(op), targetAddress, block.chainid)
            );
    }

    function testHash(UserOperation calldata op) public pure returns (bytes32) {
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

    function testCalcTotalTokenFee(
        PaymasterMode mode,
        uint256 rate,
        uint256 cost,
        uint256 fee
    ) public pure returns (uint256) {
        if (mode == PaymasterMode.FREE) {
            return 0;
        }
        if (mode == PaymasterMode.FEE_ONLY) {
            return fee;
        }
        if (mode == PaymasterMode.GAS_ONLY) {
            return (cost * rate) / 1e18;
        }
        return ((cost * rate) / 1e18) + fee;
    }
}
