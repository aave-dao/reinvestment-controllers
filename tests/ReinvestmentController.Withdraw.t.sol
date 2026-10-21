// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerWithdrawTest is ReinvestmentControllerTestBase {
  // From GatewayWallet
  error WithdrawalNotYetAvailable();

  uint256 internal constant INVESTED = 400_000e6;

  function setUp() public override {
    super.setUp();

    _invest(INVESTED);
    _pause();
  }

  function test_withdraw() public {
    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalCompleted(INVESTED);

    vm.prank(admin);
    controller.withdraw();

    assertEq(hub.getAssetSwept(assetId), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
    assertEq(usdc.balanceOf(address(hub)), SUPPLIED);
    assertEq(usdc.balanceOf(address(controller)), 0);
    assertEq(usdc.balanceOf(address(wallet)), 0);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), 0);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), 0);
    assertEq(wallet.withdrawalBlock(address(usdc), address(controller)), 0);
    assertEq(controller.getInvestedAmount(), 0);
    assertTrue(controller.paused());
  }

  function test_withdraw(uint256 blocksAhead) public {
    blocksAhead = bound(blocksAhead, 0, 1_000);

    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY + blocksAhead);

    vm.prank(admin);
    controller.withdraw();

    assertEq(hub.getAssetSwept(assetId), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), 0);
  }

  function test_withdraw_afterPartialDivest() public {
    vm.prank(admin);
    controller.unpause();

    vm.prank(keeper);
    controller.divest(100_000e6, _encodeAttestation(_defaultTransferSpec(100_000e6)), hex'1234');

    vm.prank(pauser);
    controller.pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalCompleted(INVESTED - 100_000e6);

    vm.prank(admin);
    controller.withdraw();

    assertEq(hub.getAssetSwept(assetId), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
  }

  function test_withdraw_unblocksUnpause() public {
    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY);

    vm.prank(admin);
    controller.withdraw();

    vm.prank(admin);
    controller.unpause();

    assertFalse(controller.paused());
  }

  function test_withdraw_revertsWith_WithdrawalNotYetAvailable() public {
    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY - 1);
    vm.expectRevert(WithdrawalNotYetAvailable.selector);
    vm.prank(admin);
    controller.withdraw();
  }

  function test_withdraw_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.withdraw();
  }

  function test_withdraw_revertsWith_NoWithdrawalInProcess() public {
    vm.expectRevert(IReinvestmentController.NoWithdrawalInProcess.selector);
    vm.prank(admin);
    controller.withdraw();
  }

  function test_withdraw_revertsWith_NoWithdrawalInProcess_afterWithdrawalCompletes() public {
    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY);

    vm.prank(admin);
    controller.withdraw();

    vm.expectRevert(IReinvestmentController.NoWithdrawalInProcess.selector);
    vm.prank(admin);
    controller.withdraw();
  }
}
