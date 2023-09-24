// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {SafeProtocolRegistry} from "@safe/SafeProtocolRegistry.sol";
import {SafeProtocolManager} from "@safe/SafeProtocolManager.sol";
import {Plugin} from "../../src/Plugin.sol";

contract DeployContracts is Script {
    /*
    function run(address owner) public returns (Plugin, SafeProtocolManager, SafeProtocolRegistry) {
        SafeProtocolRegistry registry = new SafeProtocolRegistry(owner);
        SafeProtocolManager manager = new SafeProtocolManager(owner, address(registry));
        Plugin plugin = new Plugin(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951); //set this in env
        return (plugin, manager, registry);
    }

    */
}
