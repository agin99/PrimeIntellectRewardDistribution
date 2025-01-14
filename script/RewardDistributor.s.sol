// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RewardDistributor} from "../src/RewardDistributor.sol";

contract RewardDistributorScript is Script {
    RewardDistributor public distributor;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        distributor = new RewardDistributor(
            100,
            10
        );

        vm.stopBroadcast();
    }
}
