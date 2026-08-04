// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {ReinvestmentController} from "../src/ReinvestmentController.sol";

contract DeployScript is Script {
    address public constant GATEWAY = address(0);
    address public constant HUB = address(0);
    address public constant USDC = address(0);

    ReinvestmentController public controller;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        controller = new ReinvestmentController(GATEWAY, HUB, USDC);

        vm.stopBroadcast();
    }
}
