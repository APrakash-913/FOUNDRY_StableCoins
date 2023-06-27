// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Abhinav Prakash
 * @notice This Library is used to check the Chainlink Oracle for stale data
 *         👉 If a price is stale, the function will revert, and render the DSCEngine unusuable - is is by design
 *         👉 I want the DSCEngine to freeze if price becomes stale.
 *         👉 So, if the Chainlink network explodes and SOMEONE has lot of money in locked in DSCEngine -> Sed lif for u!!!
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 sec

    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // ⌛seconds since it was last updated.
        uint256 secoundsSince = block.timestamp - updatedAt;
        if (secoundsSince > TIMEOUT) revert OracleLib__StalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
