// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {MockHub} from './mocks/MockHub.sol';
import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerInvestTest is ReinvestmentControllerTestBase {
  function test_invest() public {
    vm.expectEmit(address(hub));
    emit MockHub.Sweep(assetId, address(controller), INVESTABLE);
    vm.expectEmit(address(controller));
    emit IReinvestmentController.Invested(INVESTABLE);

    vm.prank(keeper);
    controller.invest(INVESTABLE);

    assertEq(hub.getAssetSwept(assetId), INVESTABLE);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTABLE);
    assertEq(hub.getAddedAssets(assetId), SUPPLIED);
    assertEq(usdc.balanceOf(address(hub)), SUPPLIED - INVESTABLE);
    assertEq(usdc.balanceOf(address(wallet)), INVESTABLE);
    assertEq(usdc.balanceOf(address(controller)), 0);
    assertEq(usdc.allowance(address(controller), address(wallet)), 0);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), INVESTABLE);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), 0);
    assertEq(controller.getInvestedAmount(), INVESTABLE);
    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_invest(uint256 amount) public {
    amount = bound(amount, 1, INVESTABLE);

    vm.prank(keeper);
    controller.invest(amount);

    assertEq(controller.getInvestedAmount(), amount);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - amount);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), amount);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function test_invest_byAdmin() public {
    vm.prank(admin);
    controller.invest(1_000e6);

    assertEq(controller.getInvestedAmount(), 1_000e6);
  }

  function test_invest_partialAmountLeavesRemainingHeadroom() public {
    vm.prank(keeper);
    controller.invest(INVESTABLE / 4);

    assertEq(controller.getInvestableAmount(), INVESTABLE - INVESTABLE / 4);
  }

  function test_invest_leavesLiquidBufferUntouchedWhenTheLiquidBufferIsTheBindingLimit() public {
    vm.prank(admin);
    controller.setExposureCapBps(PERCENTAGE_FACTOR - 1);

    uint256 investable = controller.getInvestableAmount();

    vm.prank(keeper);
    controller.invest(investable);

    assertEq(investable, SUPPLIED - BUFFER);
    assertEq(hub.getAssetLiquidity(assetId), BUFFER);
  }

  function test_invest_afterMinDelayElapses() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.warp(block.timestamp + INVEST_MIN_DELAY + 1);

    vm.prank(keeper);
    controller.invest(2_000e6);

    assertEq(controller.getInvestedAmount(), 3_000e6);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), 3_000e6);
  }

  function test_invest_atExactMinDelayExpiry() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.warp(block.timestamp + INVEST_MIN_DELAY);

    vm.prank(keeper);
    controller.invest(2_000e6);

    assertEq(controller.getInvestedAmount(), 3_000e6);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), 3_000e6);
  }

  function test_invest_afterAnyElapsedMinDelay(uint256 elapsed) public {
    elapsed = bound(elapsed, INVEST_MIN_DELAY, 365 days);

    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.warp(block.timestamp + elapsed);

    vm.prank(keeper);
    controller.invest(1_000e6);

    assertEq(controller.getInvestedAmount(), 2_000e6);
  }

  function test_invest_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 keeperRole = controller.KEEPER_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        alice,
        keeperRole
      )
    );
    vm.prank(alice);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_AccessControlUnauthorizedAccount_pauserIsNotKeeper() public {
    bytes32 keeperRole = controller.KEEPER_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        pauser,
        keeperRole
      )
    );
    vm.prank(pauser);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_AccessControlUnauthorizedAccount_afterRoleRevoked() public {
    bytes32 keeperRole = controller.KEEPER_ROLE();

    vm.prank(admin);
    controller.revokeRole(keeperRole, keeper);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        keeperRole
      )
    );
    vm.prank(keeper);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_AccessControlUnauthorizedAccount_beforeEnforcedPause() public {
    bytes32 keeperRole = controller.KEEPER_ROLE();

    vm.prank(pauser);
    controller.pause();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        alice,
        keeperRole
      )
    );
    vm.prank(alice);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_EnforcedPause() public {
    vm.prank(pauser);
    controller.pause();

    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    vm.prank(keeper);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_EnforcedPause_beforeInvalidAmount() public {
    vm.prank(pauser);
    controller.pause();

    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    vm.prank(keeper);
    controller.invest(0);
  }

  function test_invest_revertsWith_InvestMinDelayNotElapsed_beforeExpiry() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.expectRevert(IReinvestmentController.InvestMinDelayNotElapsed.selector);
    vm.prank(keeper);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_InvestMinDelayNotElapsed_oneSecondBeforeExpiry() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.warp(block.timestamp + INVEST_MIN_DELAY - 1);

    vm.expectRevert(IReinvestmentController.InvestMinDelayNotElapsed.selector);
    vm.prank(keeper);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_InvestMinDelayNotElapsed_beforeInvalidAmount() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.expectRevert(IReinvestmentController.InvestMinDelayNotElapsed.selector);
    vm.prank(keeper);
    controller.invest(0);
  }

  function test_invest_revertsWith_InvestMinDelayNotElapsed_afterMinDelayIsExtended() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.prank(admin);
    controller.setInvestMinDelay(30 days);

    vm.warp(block.timestamp + INVEST_MIN_DELAY + 1);

    vm.expectRevert(IReinvestmentController.InvestMinDelayNotElapsed.selector);
    vm.prank(keeper);
    controller.invest(1_000e6);
  }

  function test_invest_revertsWith_InvalidAmount() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(keeper);
    controller.invest(0);
  }

  function test_invest_revertsWith_ExposureCapExceeded_aboveInvestable() public {
    vm.expectRevert(IReinvestmentController.ExposureCapExceeded.selector);
    vm.prank(keeper);
    controller.invest(INVESTABLE + 1);
  }

  function test_invest_revertsWith_ExposureCapExceeded_exposureCapAbsIsZero() public {
    vm.prank(admin);
    controller.setExposureCapAbs(0);

    vm.expectRevert(IReinvestmentController.ExposureCapExceeded.selector);
    vm.prank(keeper);
    controller.invest(1);
  }

  function test_invest_revertsWith_ExposureCapExceeded_idleAtLiquidBuffer() public {
    hub.setAccounting(SUPPLIED, BUFFER, 0);

    vm.expectRevert(IReinvestmentController.ExposureCapExceeded.selector);
    vm.prank(keeper);
    controller.invest(1);
  }

  function test_invest_revertsWith_ExposureCapExceeded_capRoomExhausted() public {
    vm.prank(keeper);
    controller.invest(INVESTABLE);

    vm.warp(block.timestamp + INVEST_MIN_DELAY + 1);

    vm.expectRevert(IReinvestmentController.ExposureCapExceeded.selector);
    vm.prank(keeper);
    controller.invest(1);
  }
}
