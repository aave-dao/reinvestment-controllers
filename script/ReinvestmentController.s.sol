// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {ReinvestmentController} from "../src/ReinvestmentController.sol";

contract DeployScript is Script {
    address public constant GATEWAY_WALLET =
        0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;
    address public constant GATEWAY_MINTER = address(0);
    address public constant HUB = address(0);
    address public constant USDC = address(0);

    ReinvestmentController public controller;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        controller = new ReinvestmentController(
            GATEWAY_WALLET,
            GATEWAY_MINTER,
            HUB,
            USDC
        );

        vm.stopBroadcast();
    }
}
