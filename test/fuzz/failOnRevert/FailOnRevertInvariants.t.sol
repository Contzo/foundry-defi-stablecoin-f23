// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol"; 
import {DSCEngine} from "../../../src/DSCEngine.sol"; 
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol"; 
import {HelperConfig} from "../../../script/HelperConfig.s.sol"; 
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
import {Handler} from "./FailOnRevertHandler.t.sol" ;


contract Invariants is StdInvariant{
    DeployDSC deployer ; 
    DSCEngine  engine; 
    DecentralizedStableCoin coin ; 
    HelperConfig helperConfig ;
    Handler handler ; 
    address weth; 
    address wbtc ; 

    function setUp() external{
        deployer = new DeployDSC() ; 
        (coin, engine, helperConfig)= deployer.run() ; 
        (,,weth, wbtc, )=helperConfig.activeNetworkConfig(); 
        handler = new Handler(engine, coin); 
        // targetContract(address(engine)) ;  // setup our target contract 
        targetContract(address(handler));
    }

    function invariant_protocolMustBeOverCollateralized_failOnRevert() public view {
        // get the total 
        uint256 totalSupply = coin.totalSupply(); // get the total supply of DSC 
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine)); // get the total weth stored in the engine
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine)); // get the total wbtc stored in the engine
        uint256 wethValue = engine.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUSDValue(wbtc, totalWbtcDeposited);

        console.log("Weth value: ", wethValue); 
        console.log("Wbtc value: ", wbtcValue); 
        console.log("Total DSC supply: ", totalSupply); 

        assert(wethValue + wbtcValue >= totalSupply); 
    }
}