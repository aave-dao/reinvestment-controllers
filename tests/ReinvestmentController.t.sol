// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ReinvestmentController} from "../src/ReinvestmentController.sol";

contract ReinvestmentControllerTest is Test {
    ReinvestmentController public controller;

    function setUp() public {
        controller = new ReinvestmentController();
    }
}

contract ConstructorTest is Test {}

contract InvestTest is ReinvestmentControllerTest {}

contract DivestTest is ReinvestmentControllerTest {}

contract InitiateWithdrawaltTest is ReinvestmentControllerTest {}

contract WithdrawTest is ReinvestmentControllerTest {}

contract SetGatewayTxLimitTest is ReinvestmentControllerTest {}

contract DeployableTest is ReinvestmentControllerTest {}

contract IsValidSignatureTest is ReinvestmentControllerTest {}
