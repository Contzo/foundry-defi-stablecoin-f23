// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    function run() external returns(DecentralizedStableCoin ,DSCEngine)
    {
        vm.startBroadcast() ; 
        DSCEngine engine = new DSCEngine()
        // DecentralizedStableCoin coin = new DecentralizedStableCoin() ; 

        vm.stopBroadcast() ; 
    }
}
