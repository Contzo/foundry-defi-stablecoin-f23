// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol"; 
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol"; 
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test{
    DSCEngine engine ; 
    DecentralizedStableCoin coin ; 
    ERC20Mock weth ; 
    ERC20Mock wbtc; 
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant HF_THRESHOLD = 1e18 ; 
    MockV3Aggregator ethPriceFeed ; 

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _coin){
        engine = _dscEngine; 
        coin = _coin;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]); 
        wbtc = ERC20Mock(collateralTokens[1]);
        ethPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth))); 
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE); 
        console.log("collateral amount to deposit:", amountCollateral); 
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral); 
        console.log("Minted collateral:", amountCollateral);
        collateral.approve(address(engine), amountCollateral);

        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    // bound the amount collateral to redeem to the amount that the user deposited in other sessions
    uint256 depositedCollateralToken = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
    amountCollateral = bound(amountCollateral, 0, depositedCollateralToken);
    if(amountCollateral == 0) return ; 
    // Determine the HF after the user redeemed the collateral
    (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = engine.getAccountInformation(msg.sender);
    uint256 amountCollateralUsdValue = engine.getUSDValue(address(collateral), amountCollateral);
    uint256 remainingCollateralValue = totalCollateralValueInUsd - amountCollateralUsdValue; 
    uint256 HFAfterRedeem = engine.calculateHealthFactor(remainingCollateralValue, totalDscMinted);
    if(HFAfterRedeem < HF_THRESHOLD) return ; // return if hte resulting HF is lower then 1. 
    // Send the redeem transaction
    vm.prank(msg.sender);
    engine.redeemCollateral(address(collateral), amountCollateral);
}

    function mintDsc(uint256 amount) public{
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(msg.sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted); // max DSC the sender can mint
        if(maxDscToMint <= 0) return ; 
        amount = bound(amount, 1, uint256(maxDscToMint)) ;
        vm.startPrank(msg.sender);
        engine.mintDsc(amount);
        vm.stopPrank();
    }

    //This breaks the invariant test suite !!!
    function updateCollateralPrice(uint96 priceUpdate) public {
        int256 newPrice = int256(uint256(priceUpdate)); 
        ethPriceFeed.updateAnswer(newPrice) ;
    }


    //Helper functions  
    function _getCollateralFromSeed(uint256 collateralSeed) public view returns(ERC20Mock){
        if(collateralSeed %2 == 0) {
            return weth; 
        }
        return  wbtc ;
    }
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
}
}