//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract feedMock is AggregatorV3Interface {
    uint8 private _decimals = 8;
    string private _description = "Hello World";
    uint256 private _version = 1;

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function version() external view returns (uint256) {
        return _version;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            roundId = 1;
            answer = 100;
            startedAt = 3;
            updatedAt = 4;
            answeredInRound = 5;
        }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            roundId = 1;
            answer = 100;
            startedAt = 3;
            updatedAt = 4;
            answeredInRound = 5;
        }
}
