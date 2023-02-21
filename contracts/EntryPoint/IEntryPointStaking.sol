//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IEntryPointStaking {
    /**
     * @dev Struct of deposits information for each account
     * @param amount deposited for an account
     * @param unstakeDelaySec delay picked for the unstaking process, zero means the account hasn't staked yet
     * @param withdrawTime timestamp when the account will be allowed to withdraw their deposited funds, zero means anytime
     */
    struct Deposit {
        uint256 amount;
        uint32 unstakeDelaySec;
        uint64 withdrawTime;
    }

    event Deposited(address indexed account, uint256 deposited);
    event StakeLocked(
        address indexed account,
        uint256 deposited,
        uint256 unstakeDelaySec
    );
    event StakeUnlocked(address indexed account, uint64 withdrawTime);
    event Withdrawn(
        address indexed account,
        address recipient,
        uint256 deposited,
        uint256 amount
    );
    // return the deposit of an account
    function getBalanceOf(address account) external view returns (uint256);

    // add to the deposit of the given account
    function depositTo(address account) external payable;

    // add a paymaster stake (must be called by the paymaster)
    function addStake(uint32 _unstakeDelaySec, address testAccount) external payable;

    // unlock the stake (must wait unstakeDelay before can withdraw)
    function unlockStake() external;

    // withdraw the unlocked stake
    function withdrawStake(address payable withdrawAddress) external;

    // withdraw from the deposit
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;
}
