// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoins} from "../src/DecentralizedStableCoins.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSCEngine is Script {
    DSCEngine dSCEngine;
    DecentralizedStableCoins dsc;
    address[] private tokenAddress;
    address[] private priceFeedAddress;

    function run() external returns (DSCEngine, DecentralizedStableCoins, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        dsc = new DecentralizedStableCoins();
        dSCEngine = new DSCEngine(tokenAddress,priceFeedAddress,address(dsc));

        // 👑 -> Making DSCEngine owner.
        dsc.transferOwnership(address(dSCEngine));
        vm.stopBroadcast();
        return (dSCEngine, dsc, helperConfig);
    }
}
