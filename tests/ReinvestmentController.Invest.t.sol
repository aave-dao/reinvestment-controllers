// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {IReinvestmentController} from '../src/ReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerInvestTest is ReinvestmentControllerTestBase {
  function test_invest_revertsWith_AccessControlUnauthorizedAccount_beforeAmountCheck() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.INVESTOR_ROLE()
      )
    );
    controller.invest(0);
  }

  function test_invest_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.INVESTOR_ROLE()
      )
    );
    controller.invest(1e6);
  }

  function test_invest_revertsWith_EnforcedPause() public {
    vm.prank(admin);
    controller.pause();

    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    controller.invest(INVESTABLE);
  }

  function test_invest_revertsWith_DepositTimelock() public {
    _invest(1_000e6);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.DepositTimelock.selector);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_DepositTimelock_atExactBoundary() public {
    _invest(1_000e6);

    vm.warp(block.timestamp + DEPOSIT_TIMELOCK);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.DepositTimelock.selector);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_InvalidAmount() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.invest(0);
  }

  function test_invest_revertsWith_MaximumInvestAmountExceeded() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.MaximumInvestAmountExceeded.selector);
    controller.invest(INVESTABLE + 1);
  }

  function test_invest_revertsWith_MaximumInvestAmountExceeded_idleAtBuffer() public {
    hub.setLiquidity(ASSET_ID, (SUPPLIED * BUFFER_BPS) / 10_000);

    assertEq(controller.getInvestableAmount(), 0);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.MaximumInvestAmountExceeded.selector);
    controller.invest(1);
  }

  function test_invest_revertsWith_MaximumInvestAmountExceeded_maxInvestIsZero() public {
    vm.prank(admin);
    controller.setMaxInvest(0);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.MaximumInvestAmountExceeded.selector);
    controller.invest(1);
  }

  function test_invest_partialAmountLeavesRemainingHeadroom() public {
    uint256 amount = 100_000e6;
    _invest(amount);

    assertEq(controller.getInvestedAmount(), amount);
    assertEq(controller.getInvestableAmount(), INVESTABLE - amount);
  }

  function test_invest_succeedsAgainAfterTimelockElapses() public {
    uint256 amount = 100_000e6;
    _invest(amount);

    vm.warp(block.timestamp + DEPOSIT_TIMELOCK + 1);

    vm.prank(admin);
    controller.invest(amount);

    assertEq(controller.getInvestedAmount(), amount * 2);
  }

  function test_invest() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.Invested(INVESTABLE);
    _invest(INVESTABLE);

    assertEq(usdc.balanceOf(address(gatewayWallet)), INVESTABLE);
    assertEq(usdc.balanceOf(address(hub)), SUPPLIED - INVESTABLE);
    assertEq(usdc.balanceOf(address(controller)), 0);

    assertEq(controller.getInvestedAmount(), INVESTABLE);
    assertEq(hub.getAssetLiquidity(ASSET_ID), SUPPLIED - INVESTABLE);
    assertEq(hub.getAddedAssets(ASSET_ID), SUPPLIED);

    assertEq(usdc.allowance(address(controller), address(gatewayWallet)), 0);
    assertEq(gatewayWallet.availableBalance(address(usdc), address(controller)), INVESTABLE);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_invest_withinInvestableAmount(uint256 amount) public {
    amount = bound(amount, 1, INVESTABLE);

    _invest(amount);

    assertEq(controller.getInvestedAmount(), amount);
    assertEq(controller.getInvestableAmount(), INVESTABLE - amount);
    assertEq(usdc.balanceOf(address(gatewayWallet)), amount);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function test_invest_revertsWith_MaximumInvestAmountExceeded_aboveInvestable(
    uint256 amount
  ) public {
    amount = bound(amount, INVESTABLE + 1, type(uint128).max);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.MaximumInvestAmountExceeded.selector);
    controller.invest(amount);
  }
}
