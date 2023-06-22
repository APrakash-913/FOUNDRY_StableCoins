// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoins} from "../src/DecentralizedStableCoins.sol";

contract DeployDecentralizedStableCoins is Script {
    DecentralizedStableCoins decentralizedStableCoins;

    function run() external returns (DecentralizedStableCoins) {
        vm.startBroadcast();
        decentralizedStableCoins = new DecentralizedStableCoins();
        vm.stopBroadcast();
        return decentralizedStableCoins;
    }
}
