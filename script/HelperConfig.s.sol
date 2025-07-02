// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;
    uint8 public constant PRICE_FEED_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 200e8; // 200 USD
    int256 public constant BTC_USD_PRICE = 20_000e8; // 20,000 USD
    uint256 public constant INITIAL_BALANCE = 1000e18; // 1000 ETH

    constructor() {
        if (block.chainid == 11155111) activeNetworkConfig = getSepoliaEthConfig();
        else activeNetworkConfig = getOrCreateAnvilConfig();
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) return activeNetworkConfig;

        vm.startBroadcast();
        // ETH USD price feed and WETH setup
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethToken = new ERC20Mock("WETH", "WETH", msg.sender, INITIAL_BALANCE);
        // BTC USD price feed and WBTC setup
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcToken = new ERC20Mock("WBTC", "WBTC", msg.sender, INITIAL_BALANCE);
        vm.stopBroadcast();
        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethToken),
            wbtc: address(wbtcToken),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }
}
