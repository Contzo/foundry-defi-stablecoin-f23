// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


library OracleLib {
    error OracleLib__StalePrice() ; 
    error OracleLib__PriceIsZero() ; 
    error OracleLib__PriceDropTooLarge(); 
    uint256 private constant TIMEOUT = 3 hours; 
    int256 private constant ALLOWED_PRICE_DROP = 20e16;
    int256 private constant PRECISION = 1e18; 
    uint256 private constant CIRCUIT_BRAKE_COOLDOWN = 1 hours; 

    function updatePrice(AggregatorV3Interface priceFeed, int256 lastGoodPrice, uint256 circuitBrakeTimeStamp) internal view returns(int256){
        (,int256 newPrice,,,)= stalePriceCheck(priceFeed);
         if(lastGoodPrice == type(int256).min && block.timestamp > circuitBrakeTimeStamp +  CIRCUIT_BRAKE_COOLDOWN){
            circuitBrakeTimeStamp = block.timestamp; 
            return newPrice; 
         }
        bool paused = checkCircuitBreaker(lastGoodPrice, newPrice);
        if(paused) return type(int256).min ;
        return newPrice; 
    }
    function stalePriceCheck(AggregatorV3Interface priceFeed) public view returns(uint80, int256, uint256, uint256, uint80){
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt; 
        if(secondsSince > TIMEOUT) revert OracleLib__StalePrice() ; 
        return (roundId, answer, startedAt, updatedAt, answeredInRound) ;
    }

    /**
     * @param lastGoodPrice - the last price that was considered good
     * @param newPrice - the new price we want to compare 
     * @notice - both inputs are assumed to have an 18 digits precision
     */
    function checkCircuitBreaker(int256 lastGoodPrice, int256 newPrice) internal pure returns(bool){
        if(lastGoodPrice == 0) revert OracleLib__PriceIsZero() ; 
        int256 maxPriceDrop = lastGoodPrice * ALLOWED_PRICE_DROP / PRECISION; 
        int256 minThreshold = lastGoodPrice - maxPriceDrop ; 
        if(newPrice < minThreshold) return true ; 
        else return false ;
    }
}