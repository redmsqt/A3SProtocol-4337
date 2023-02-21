//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract A3SFeeHandler is Ownable {
    // The only address can withdraw money
    address private _withdrawer;

    // The address of fiat token
    address private _fiatToken;

    // Number of fiat token to mint a wallet
    uint256 private _fiatTokenFee;

    // Number of platform token to mint a wallet
    uint256 private _platformTokenFee;

    modifier onlyWithdrawer() {
        require(_msgSender() == _withdrawer, "A3S: caller is not withdrawer");
        _;
    }

    modifier enoughtFee(uint256 units) {
        if (msg.value < units * _platformTokenFee) {
            require(
                IERC20(_fiatToken).balanceOf(_msgSender()) >=
                    units * _fiatTokenFee,
                "A3S: not enought fee"
            );
        }
        _;
    }

    /**
     * @notice Withdraw all the platform tokens in this contract
     * @dev Only the withdrawer can withdraw platform tokens
     */
    function withdrawPlatformToken() external onlyWithdrawer {
        payable(_withdrawer).transfer(address(this).balance);
    }

    /**
     * @notice Withdraw all the fiat tokens in this contract
     * @dev Only the withdrawer can withdraw platform tokens
     */
    function withdrawFiatToken() external onlyWithdrawer {
        uint256 balance = IERC20(_fiatToken).balanceOf(address(this));
        IERC20(_fiatToken).transfer(_withdrawer, balance);
    }

    /**
     * @notice Set withdrawer with the given new address
     * @dev newWithdrawer can not be address 0
     */
    function setWithdrawer(address newWithdrawer) external onlyOwner {
        require(
            newWithdrawer != address(0),
            "A3S: withdrawer can not be address 0"
        );
        _withdrawer = newWithdrawer;
    }

    /**
     * @notice Set fiat token with the given new address
     * @dev newToken can not be address 0
     */
    function setFiatToken(address newToken) external onlyOwner {
        require(newToken != address(0), "A3S: withdrawer can not be address 0");
        _fiatToken = newToken;
    }

    /**
     * @notice Set fiat token fee with the given new fee number
     */
    function setFiatTokenFee(uint256 newFiatTokenFee) external onlyOwner {
        _fiatTokenFee = newFiatTokenFee;
    }

    /**
     * @notice Set platform token fee with the given new fee number
     */
    function setPlatfromTokenFee(uint256 newFee) external onlyOwner {
        _platformTokenFee = newFee;
    }

    /**
     * @notice Return current valid withdrawer
     */
    function withdrawer() public view returns (address) {
        return _withdrawer;
    }

    /**
     * @notice Return current fiat token address
     */
    function fiatToken() public view returns (address) {
        return _fiatToken;
    }

    /**
     * @notice Return current fiat token fee
     */
    function fiatTokenFee() public view returns (uint256) {
        return _fiatTokenFee;
    }

    /**
     * @notice Return current platdorm token fee
     */
    function platformTokenFee() public view returns (uint256) {
        return _platformTokenFee;
    }
}
