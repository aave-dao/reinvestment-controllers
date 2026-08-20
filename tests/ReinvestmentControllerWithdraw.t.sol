// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';

import {IReinvestmentController} from '../src/ReinvestmentController.sol';
import {MockGatewayWallet} from './mocks/MockGatewayWallet.sol';
import {ReinvestmentControllerTest} from './ReinvestmentControllerBase.t.sol';

uint256 constant GATEWAY_WITHDRAWAL_DELAY = 50_400;

contract InitiateWithdrawalTest is ReinvestmentControllerTest {
  function test_initiateWithdrawal_revertsWith_callerIsNotAdmin() public {
    _invest(INVESTABLE);
    _pause();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.initiateWithdrawal();
  }

  function test_initiateWithdrawal_revertsWith_notPaused() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
    controller.initiateWithdrawal();
  }

  function test_initiateWithdrawal_revertsWith_nothingInvested() public {
    _pause();

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.initiateWithdrawal();
  }

  function test_initiateWithdrawal_revertsWith_insufficientLiquidity() public {
    _invest(INVESTABLE);
    hub.setSwept(ASSET_ID, INVESTABLE - 1);
    _pause();

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InsufficientLiquidity.selector);
    controller.initiateWithdrawal();
  }

  function test_initiateWithdrawal_revertsWith_withdrawalInProcess() public {
    _invest(INVESTABLE);
    _pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.WithdrawalInProcess.selector);
    controller.initiateWithdrawal();
  }

  function test_initiateWithdrawal_successful() public {
    _invest(INVESTABLE);
    _pause();

    uint256 expectedWithdrawalBlock = block.number + GATEWAY_WITHDRAWAL_DELAY;

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalInitiated(INVESTABLE);

    vm.prank(admin);
    controller.initiateWithdrawal();

    assertEq(
      gatewayWallet.withdrawalBlock(address(usdc), address(controller)),
      expectedWithdrawalBlock
    );

    assertEq(gatewayWallet.withdrawingBalance(address(usdc), address(controller)), INVESTABLE);
    assertEq(gatewayWallet.availableBalance(address(usdc), address(controller)), 0);

    assertEq(usdc.balanceOf(address(gatewayWallet)), INVESTABLE);
    assertEq(controller.getInvestedAmount(), INVESTABLE);
  }
}

contract WithdrawTest is ReinvestmentControllerTest {
  function test_withdraw_revertsWith_callerIsNotAdmin() public {
    _invest(INVESTABLE);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock());

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.withdraw();
  }

  function test_withdraw_revertsWith_noWithdrawalInProcess() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.NoWithdrawalInProcess.selector);
    controller.withdraw();
  }

  function test_withdraw_revertsWith_gatewayDelayNotElapsed() public {
    _invest(INVESTABLE);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock() - 1);

    vm.prank(admin);
    vm.expectRevert(MockGatewayWallet.WithdrawalNotYetAvailable.selector);
    controller.withdraw();
  }

  function test_withdraw_atExactReadyBlock() public {
    _invest(INVESTABLE);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock());

    vm.prank(admin);
    controller.withdraw();

    assertEq(gatewayWallet.withdrawingBalance(address(usdc), address(controller)), 0);
  }

  function test_withdraw_whileStillPaused() public {
    _invest(INVESTABLE);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock());

    vm.prank(admin);
    controller.withdraw();

    assertTrue(controller.paused());
    assertEq(controller.getInvestedAmount(), 0);
  }

  function test_withdraw_successful() public {
    _invest(INVESTABLE);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock() + 1);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalCompleted(INVESTABLE);

    vm.prank(admin);
    controller.withdraw();

    assertEq(usdc.balanceOf(address(hub)), SUPPLIED);
    assertEq(usdc.balanceOf(address(gatewayWallet)), 0);
    assertEq(usdc.balanceOf(address(controller)), 0);

    assertEq(controller.getInvestedAmount(), 0);
    assertEq(hub.getAssetLiquidity(ASSET_ID), SUPPLIED);
    assertEq(gatewayWallet.withdrawingBalance(address(usdc), address(controller)), 0);
  }

  function _withdrawalBlock() internal view returns (uint256) {
    return gatewayWallet.withdrawalBlock(address(usdc), address(controller));
  }

  function _initiateWithdrawal() internal {
    vm.prank(admin);
    controller.initiateWithdrawal();
  }
}
