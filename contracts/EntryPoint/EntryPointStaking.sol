//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./IEntryPointStaking.sol";
import "../helper/Calls.sol";

contract EntryPointStaking is IEntryPointStaking {
    using SafeCast for uint256;
    using Calls for address payable;
    // unstaking delay that will be forced to each account
    uint32 private immutable _unstakeDelaySec;

    // deposits list indexed by account address
    mapping(address => Deposit) private _deposits;

    /**
     * @dev Staking constructor
     * @param unstakeDelaySec_ unstaking delay that will be forced to each account
     */

    constructor(uint32 unstakeDelaySec_) {
        _unstakeDelaySec = unstakeDelaySec_;
    }

    /**
     * @dev Allows receiving ETH transfers
     */
    receive() external payable {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getUnstakeDelaySec() external view returns(uint32){
        return _unstakeDelaySec;
    }

    /**
     * @dev Tells the entire deposit information for an account
     */
    function getDeposit(address account)
        external
        view
        returns (Deposit memory)
    {
        return _deposits[account];
    }

    /**
     * @dev Tells the total amount deposited for an account
     */
    function getBalanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _deposits[account].amount;
    }

    /**
     * @dev Tells is account has deposited balance or not
     */
    function hasDeposited(address account, uint256 amount)
        public
        view
        returns (bool)
    {
        return _deposits[account].amount >= amount;
    }

    /**
     * @dev Tells if an account has it's deposited balance staked or not
     */
    function isStaked(address account) public view returns (bool) {
        Deposit storage deposit = _deposits[account];
        return deposit.unstakeDelaySec > 0 && deposit.withdrawTime == 0;
    }

    /**
     * @dev Tells if an account has started it's unstaking process or not
     */
    function isUnstaking(address account) public view returns (bool) {
        Deposit storage deposit = _deposits[account];
        return deposit.unstakeDelaySec > 0 && deposit.withdrawTime > 0;
    }

    /**
     * @dev Tells if an account is allowed to withdraw its deposits or not
     */
    function canWithdraw(address account) public view returns (bool) {
        Deposit storage deposit = _deposits[account];
        // solhint-disable-next-line not-rely-on-time
        return
            deposit.unstakeDelaySec == 0 ||
            (isUnstaking(account) && deposit.withdrawTime <= block.timestamp);
    }

    /**
     * @dev Deposits value to an account. It will deposit the entire msg.value sent to the function.
     * @param account willing to deposit the value to
     */
    function depositTo(address account) external payable override {
        Deposit storage deposit = _deposits[account];
        deposit.amount = deposit.amount + msg.value;
        emit Deposited(account, deposit.amount);
    }

    /**
     * @dev Stakes the sender's deposits. It will deposit the entire msg.value sent to the function and mark it as staked.
     * @param unstakeDelaySec unstaking delay that will be forced to the account, it can only be greater than or
     * equal to the one set in the contract
     */
    function addStake(uint32 unstakeDelaySec, address account) external payable override {
        Deposit storage deposit = _deposits[account];
        require(
            unstakeDelaySec >= _unstakeDelaySec,
            "Staking: Low unstake delay"
        );
        require(
            unstakeDelaySec >= deposit.unstakeDelaySec,
            "Staking: Decreasing unstake time"
        );

        uint256 deposited = deposit.amount + msg.value;
        deposit.amount = deposited;
        deposit.unstakeDelaySec = unstakeDelaySec;
        deposit.withdrawTime = 0;
        emit StakeLocked(account, deposited, _unstakeDelaySec);
    }

    /**
     * @dev Starts the unlocking process for the sender.
     * It sets the withdraw time based on the unstaking delay previously set for the account.
     */
    function unlockStake() external override {
        require(!isUnstaking(msg.sender), "Staking: Unstaking in progress");
        require(isStaked(msg.sender), "Staking: Deposit not staked yet");

        Deposit storage deposit = _deposits[msg.sender];
        // solhint-disable-next-line not-rely-on-time
        deposit.withdrawTime = (block.timestamp + deposit.unstakeDelaySec).toUint64();
        emit StakeUnlocked(msg.sender, deposit.withdrawTime);
    }

    /**
     * @dev Withdraws the entire deposited balance of the sender to a recipient.
     * Essentially, the withdraw time must be zero or in the past.
     */
    function withdrawStake(address payable recipient) external override {
        withdrawTo(recipient, _deposits[msg.sender].amount);
    }

    /**
     * @dev Withdraws the part of the deposited balance of the sender to a recipient.
     * Essentially, the withdraw time must be zero or in the past.
     */
    function withdrawTo(address payable recipient, uint256 amount)
        public
        override
    {
        require(amount > 0, "Staking: Withdraw amount zero");
        require(canWithdraw(msg.sender), "Staking: Cannot withdraw");

        Deposit storage deposit = _deposits[msg.sender];
        require(deposit.amount >= amount, "Staking: Insufficient deposit");
        uint256 deposited = deposit.amount - amount;

        deposit.unstakeDelaySec = 0;
        deposit.withdrawTime = 0;
        deposit.amount = deposited;

        recipient.sendValue(amount, "Staking: Withdraw failed");
        emit Withdrawn(msg.sender, recipient, deposited, amount);
    }

    /**
     * @dev Internal function to increase an account's staked balance
     */
    function _increaseStake(address account, uint256 amount) internal {
        Deposit storage deposit = _deposits[account];
        deposit.amount = deposit.amount + amount;
    }

    /**
     * @dev Internal function to decrease an account's staked balance
     */
    function _decreaseStake(address account, uint256 amount) internal {
        Deposit storage deposit = _deposits[account];
        require(deposit.amount >= amount, "Staking: Insufficient stake");
        deposit.amount = deposit.amount - amount;
    }
}