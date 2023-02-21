//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../A3SWallet/IA3SWallet.sol";

contract executeCase {
    using SafeMath for uint256;
    uint256 private data = 0;
    receive() external payable {}
    function getData() external view returns(uint256) {
        return data;
    }
    function getMsgSender() external view returns(address) {
        return msg.sender;
    }
    function subData(uint256 _x) external returns(uint256) {
        data = data.sub(_x);
        return data;
    }
    function addData(uint256 _x) external returns(uint256) {
        data = data.add(_x);
        return data;
    }
    function setData(uint256 _x) external returns(uint256) {
        data = _x;
        return data;
    }

    function callERC1271isValidSignature(address targetAddr, bytes32 hash, bytes calldata signature) external view {
        bytes4 result = IA3SWallet(targetAddr).isValidSignature(hash, signature);
        require(result == 0x1626ba7e, "Invalid ERC1271 signature");
    }
}