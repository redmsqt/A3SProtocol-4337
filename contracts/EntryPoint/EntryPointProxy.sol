// SPDX-License-Identifier: MIT
pragma solidity  ^0.8.0;
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EntryPointProxy is ERC1967Proxy {
  constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) {
    // solhint-disable-previous-line no-empty-blocks
  }
}