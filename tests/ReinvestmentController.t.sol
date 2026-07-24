// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ReinvestmentController} from "../src/ReinvestmentController.sol";

contract ReinvestmentControllerTest is Test {
    ReinvestmentController public controller;

    function setUp() public {
        controller = new ReinvestmentController();
    }
}
