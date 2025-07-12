// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol"; 
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol"; 
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test{
    DSCEngine engine ; 
    DecentralizedStableCoin coin ; 
    ERC20Mock weth ; 
    ERC20Mock wbtc; 
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _coin){
        engine = _dscEngine; 
        coin = _coin;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]); 
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE); 
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral); 
        collateral.approve(address(engine), amountCollateral);

        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public{
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        console.log("Max collateral:", maxCollateralToRedeem);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem); 
        if(amountCollateral == 0) return ;

        vm.prank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral); 
    }


    //Helper functions  
    function _getCollateralFromSeed(uint256 collateralSeed) public view returns(ERC20Mock){
        if(collateralSeed %2 == 0) {
            return weth; 
        }
        return  wbtc ;
    }
}  