//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IPaymaster.sol";
import "./PaymasterHelper.sol";
import "../UserOperation.sol";

contract Paymaster is IPaymaster, Ownable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20Metadata;
    using PaymasterHelpers for bytes;
    using PaymasterHelpers for PaymasterData;
    using PaymasterHelpers for UserOperation;

    address private _entryPoint;
    address private _verifyingSigner;

    modifier onlyEntryPoint() {
        require(
            msg.sender == _entryPoint,
            "Paymaster: Sender must be entrypoint"
        );
        _;
    }

    constructor(address entryPoint_, address verifyingSigner_) {
        _entryPoint = entryPoint_;
        _verifyingSigner = verifyingSigner_;
    }

    receive() external payable {}

    mapping(IERC20Metadata => mapping(address => uint256)) public balances;
    mapping(address => uint256) public unlockBlock;

    function addDepositFor(
        IERC20Metadata token,
        address account,
        uint256 amount
    ) external {
        require(
            token.balanceOf(msg.sender) >= amount,
            "Paymaster: insufficient balance."
        );
        token.safeTransferFrom(msg.sender, address(this), amount);
        balances[token][account] += amount;
        if (msg.sender == account) {
            lockTokenDeposit();
        }
    }

    function withdrawTokensTo(
        IERC20Metadata token,
        address account,
        uint256 amount
    ) public {
        require(
            unlockBlock[msg.sender] != 0 &&
                unlockBlock[msg.sender] < block.number,
            "Paymaster: must unlockTokenDeposit."
        );
        require(
            balances[token][msg.sender] >= amount,
            "Paymaster: insufficient balance."
        );
        balances[token][msg.sender] -= amount;
        token.transfer(account, amount);
    }

    function lockTokenDeposit() public {
        unlockBlock[msg.sender] = 0;
    }

    function unlockTokenDeposit() public {
        unlockBlock[msg.sender] = block.number;
    }

    function getDepositInfo(IERC20Metadata token, address account)
        public
        view
        returns (uint256 amount, uint256 _unlockBlock)
    {
        amount = balances[token][account];
        _unlockBlock = unlockBlock[msg.sender];
    }

    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 requestId,
        uint256 maxCost
    ) external view returns (bytes memory context) {
        PaymasterData memory paymasterData = userOp.decodePaymasterData();

        require(
            _verifyingSigner ==
                userOp.encodePaymasterRequest().recover(
                    paymasterData.signature
                ),
            "Paymaster: Invalid signature"
        );
        uint8 decimals = paymasterData.token.decimals();
        uint256 rate = _getTokenExchangeRate(paymasterData.feed, decimals);
        uint256 totalTokenFee = _calcTotalTokenFee(
            paymasterData.mode,
            rate,
            maxCost,
            paymasterData.fee
        );
        require(unlockBlock[userOp.sender] == 0, "Paymaster: Deposit not locked");
        require(balances[paymasterData.token][userOp.sender] >= totalTokenFee, "Paymaster: Not enough deposit");
        return userOp.paymasterContext(paymasterData, rate);
    }

    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external onlyEntryPoint {
        PaymasterContext memory data = context.decodePaymasterContext();
        uint256 totalTokenFee = _calcTotalTokenFee(
            data.mode,
            data.rate,
            actualGasCost,
            data.fee
        );
        if (totalTokenFee > 0) {
            if (mode != PostOpMode.postOpReverted) {
                data.token.safeTransferFrom(
                    data.sender,
                    address(this),
                    totalTokenFee
                );
            } else {
                balances[data.token][data.sender] -= totalTokenFee;
            }
            balances[data.token][_verifyingSigner] += totalTokenFee;
        }
    }
    
    function _calcTotalTokenFee(
        PaymasterMode mode,
        uint256 rate,
        uint256 cost,
        uint256 fee
    ) internal pure returns (uint256) {
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

    function _getTokenExchangeRate(
        AggregatorV3Interface feed,
        uint8 tokenDecimals
    ) internal view returns (uint256) {
        (, int256 priceInt, , , ) = feed.latestRoundData();
        uint256 price = SafeCast.toUint256(priceInt);
        uint8 feedDecimals = feed.decimals();
        return
            tokenDecimals >= feedDecimals
                ? (price * 10**(tokenDecimals - feedDecimals))
                : (price / 10**(feedDecimals - tokenDecimals));
    }

    function setEntryPoint(address entryPoint) external onlyOwner {
        _entryPoint = entryPoint;
    }

    function setVerifyingSigner(address verifyingSigner) external onlyOwner {
        _verifyingSigner = verifyingSigner;
    }

    function getEntryPoint() external view returns(address){
        return _entryPoint;
    }

    function getVerifyingSigner() external view returns(address){
        return _verifyingSigner;
    }
}