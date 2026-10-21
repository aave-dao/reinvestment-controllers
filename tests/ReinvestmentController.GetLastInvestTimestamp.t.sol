// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerGetLastInvestTimestampTest is ReinvestmentControllerTestBase {
  function test_getLastInvestTimestamp() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    assertEq(controller.getLastInvestTimestamp(), block.timestamp);
  }

  function test_getLastInvestTimestamp(uint256 elapsed) public {
    elapsed = bound(elapsed, INVEST_MIN_DELAY, 365 days);

    vm.warp(block.timestamp + elapsed);

    vm.prank(keeper);
    controller.invest(1_000e6);

    assertEq(controller.getLastInvestTimestamp(), block.timestamp);
  }

  function test_getLastInvestTimestamp_isZeroBeforeAnyInvest() public view {
    assertEq(controller.getLastInvestTimestamp(), 0);
  }

  function test_getLastInvestTimestamp_advancesOnEachInvest() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    uint256 first = controller.getLastInvestTimestamp();

    vm.warp(block.timestamp + INVEST_MIN_DELAY);

    vm.prank(keeper);
    controller.invest(1_000e6);

    assertEq(controller.getLastInvestTimestamp(), first + INVEST_MIN_DELAY);
  }

  function test_getLastInvestTimestamp_isUnchangedByDivest() public {
    vm.prank(keeper);
    controller.invest(100_000e6);

    uint256 invested = controller.getLastInvestTimestamp();

    vm.warp(block.timestamp + INVEST_MIN_DELAY);

    uint256 amount = 50_000e6;
    vm.prank(keeper);
    controller.divest(amount, _encodeAttestation(_defaultTransferSpec(amount)), hex'1234');

    assertEq(controller.getLastInvestTimestamp(), invested);
  }

  function test_getLastInvestTimestamp_marksWhenTheNextInvestUnlocks() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    uint256 unlocksAt = controller.getLastInvestTimestamp() + controller.getInvestMinDelay();

    vm.warp(unlocksAt - 1);
    vm.expectRevert(IReinvestmentController.InvestMinDelayNotElapsed.selector);
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.warp(unlocksAt);
    vm.prank(keeper);
    controller.invest(1_000e6);

    assertEq(controller.getLastInvestTimestamp(), unlocksAt);
  }
}
