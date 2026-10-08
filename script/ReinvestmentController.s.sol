// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from 'forge-std/Script.sol';
import {ReinvestmentController} from '../src/ReinvestmentController.sol';

contract DeployScript is Script {
  // https://etherscan.io/address/0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE
  address public constant GATEWAY_WALLET = 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;

  // https://etherscan.io/address/0x2222222d7164433c4C09B0b0D809a9b52C04C205
  address public constant GATEWAY_MINTER = 0x2222222d7164433c4C09B0b0D809a9b52C04C205;

  // https://etherscan.io/address/0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9
  address public constant HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;

  // https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  ReinvestmentController public controller;

  function setUp() public {}

  function run() public {
    vm.startBroadcast();

    controller = new ReinvestmentController(GATEWAY_WALLET, GATEWAY_MINTER, HUB, USDC);

    vm.stopBroadcast();
  }
}
