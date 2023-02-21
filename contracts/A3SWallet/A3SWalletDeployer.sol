//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./A3SWalletProxy.sol";

contract A3SWalletDeployer is Ownable {
    address private _logicAddress;
    bytes private _data;

    function logicAddress() public view returns (address) {
        return _logicAddress;
    }

    function data() public view returns (bytes memory) {
        return _data;
    }

    function setLogicAddress(address newLogicAddress) public onlyOwner {
        _logicAddress = newLogicAddress;
    }
    /**
     * @notice Use create2 to create a new A3SwalletProxy
     * @param salt The only influence result address from outside
     */
    function _createWallet(bytes32 salt) internal returns (address) {
        return Create2.deploy(0, salt, walletInitBytecode());
    }

    /**
     * @notice Return the wallet init bytecode with current address as parameter
     */
    function walletInitBytecode() public view returns (bytes memory) {
        bytes memory bytecode = type(A3SWalletProxy).creationCode;
        return abi.encodePacked(bytecode, abi.encode(_logicAddress, _data));
    }

    /**
     * @notice Return the calculated address if the owner create with the given salt
     */
    function predictWalletAddress(address owner, bytes32 salt)
        external
        view
        returns (address)
    {
        bytes32 mutantSalt = keccak256(abi.encodePacked(owner, salt));
        return
            Create2.computeAddress(mutantSalt, keccak256(walletInitBytecode()));
    }
}