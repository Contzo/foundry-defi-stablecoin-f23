// SPDX-License-Identifier: MIT
// Our invariants aka properties
// what are our invariants

// 1. The total supply of DSC should be less then the total value of the collateral. 
// 2. Getter view function should never revert <- evergreen invariant, every contract should have this invariant. 

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol"
import {StdInvariant} from "forge-std/StdInvariant.sol"
import {DeployDSC} from "../../script/scriptDeployDSC.s.sol"
import {DSCEngine} from "../../DSCEngine.sol"
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol"
import {HelperConfig} from "../../script/HelperConfig.s.sol"

contract InvariantsTest is Test, StdInvariant{
    DeployDSC deployer ; 
    DSCEngine  engine; 
    DecentralizesStableCoin coin ; 
    HelperConfig helperConfig ;

    function setUp() external{
        deployer = new DeployDSC() ; 
        (coin, engine, helperConfig)= deployer.run() ; 
        targetContract(address(engine)) ;  // setup our target contract 
    }    
}
