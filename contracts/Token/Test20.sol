//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Test20 is ERC20 {
    uint constant _initial_supply = 1000 * (10**18);
    constructor() ERC20("Test20", "T20") {
        _mint(msg.sender, _initial_supply);
    }
}