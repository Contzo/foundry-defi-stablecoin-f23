// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


library OracleLib {
    error OracleLib__StalePrice() ; 
    error OracleLib__PriceIsZero() ; 
    error OracleLib__PriceDropTooLarge(); 
    uint256 private constant TIMEOUT = 3 hours; 
  
    function stalePriceCheck(AggregatorV3Interface priceFeed) public view returns(uint80, int256, uint256, uint256, uint80){
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt; 
        if(secondsSince > TIMEOUT) revert OracleLib__StalePrice() ; 
        return (roundId, answer, startedAt, updatedAt, answeredInRound) ;
    }


}