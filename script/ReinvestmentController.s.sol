// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {ReinvestmentController} from "../src/ReinvestmentController.sol";

contract DeployScript is Script {
    ReinvestmentController public controller;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        controller = new ReinvestmentController();

        vm.stopBroadcast();
    }
}
