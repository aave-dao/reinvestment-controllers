// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerClaimDustTest is ReinvestmentControllerTestBase {
  uint256 internal constant INVESTED = 400_000e6;
  uint256 internal constant DUST = 1_000e6;
  uint256 internal constant BURNED = 100_000e6;

  function setUp() public override {
    super.setUp();

    _invest(INVESTED);
    _donate(DUST);
    _pause();

    vm.prank(admin);
    controller.initiateDustWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY);
  }

  function test_claimDust() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.ClaimedDust(alice, DUST);

    vm.prank(admin);
    controller.claimDust(alice);

    assertEq(controller.getPendingDust(), 0);
    assertEq(usdc.balanceOf(alice), DUST);
    assertEq(usdc.balanceOf(address(controller)), 0);
    assertEq(usdc.balanceOf(address(wallet)), INVESTED);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), 0);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), INVESTED);
    assertEq(hub.getAssetSwept(assetId), INVESTED);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTED);
  }

  function test_claimDust_doesNotReclaimToHub() public {
    uint256 liquidityBefore = hub.getAssetLiquidity(assetId);
    uint256 sweptBefore = hub.getAssetSwept(assetId);

    vm.prank(admin);
    controller.claimDust(alice);

    assertEq(hub.getAssetLiquidity(assetId), liquidityBefore);
    assertEq(hub.getAssetSwept(assetId), sweptBefore);
    assertEq(usdc.balanceOf(address(hub)), liquidityBefore);
  }

  function test_claimDust_allowsUnpause() public {
    vm.prank(admin);
    controller.claimDust(alice);

    vm.prank(admin);
    controller.unpause();

    assertFalse(controller.paused());
  }

  /// @dev Circle burns an attested intent after the mint, so a burn can land while the dust
  /// withdrawal is queued. Paying out would leave the Hub's swept balance unbacked
  function test_claimDust_revertsWith_SweptNotBacked() public {
    vm.prank(address(minter));
    wallet.gatewayBurn(address(usdc), address(controller), BURNED, 0);

    assertLt(
      wallet.availableBalance(address(usdc), address(controller)),
      hub.getAssetSwept(assetId)
    );

    vm.expectRevert(IReinvestmentController.SweptNotBacked.selector);
    vm.prank(admin);
    controller.claimDust(alice);
  }

  /// @dev The queued amount is not stranded when {claimDust} refuses it: {withdraw} returns it to
  /// the Hub instead
  function test_claimDust_blockedDustIsRecoverableThroughWithdraw() public {
    vm.prank(address(minter));
    wallet.gatewayBurn(address(usdc), address(controller), BURNED, 0);

    uint256 liquidityBefore = hub.getAssetLiquidity(assetId);

    vm.expectRevert(IReinvestmentController.SweptNotBacked.selector);
    vm.prank(admin);
    controller.claimDust(alice);

    vm.prank(admin);
    controller.withdraw();

    assertEq(controller.getPendingDust(), 0);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), 0);
    assertEq(hub.getAssetLiquidity(assetId), liquidityBefore + DUST);
    assertEq(hub.getAssetSwept(assetId), INVESTED - DUST);
  }

  function test_claimDust_revertsWith_NoDustWithdrawalInProcess_principalWithdrawal() public {
    vm.startPrank(admin);
    controller.claimDust(alice);
    controller.initiateWithdrawal();
    vm.stopPrank();

    vm.roll(block.number + WITHDRAWAL_DELAY);

    assertEq(controller.getPendingDust(), 0);
    assertGt(wallet.withdrawingBalance(address(usdc), address(controller)), 0);

    vm.expectRevert(IReinvestmentController.NoDustWithdrawalInProcess.selector);
    vm.prank(admin);
    controller.claimDust(alice);
  }

  function test_claimDust_revertsWith_AccessControlUnauthorizedAccount_keeper() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.claimDust(alice);
  }

  function test_claimDust_revertsWith_AccessControlUnauthorizedAccount_pauser() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        pauser,
        adminRole
      )
    );
    vm.prank(pauser);
    controller.claimDust(alice);
  }

  function test_claimDust_revertsWith_InvalidZeroAddress() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    vm.prank(admin);
    controller.claimDust(address(0));
  }

  function test_claimDust_revertsWith_NoDustWithdrawalInProcess() public {
    vm.prank(admin);
    controller.claimDust(alice);

    vm.expectRevert(IReinvestmentController.NoDustWithdrawalInProcess.selector);
    vm.prank(admin);
    controller.claimDust(alice);
  }

  function test_claimDust_revertsWith_ExpectedPause() public {
    vm.prank(admin);
    controller.claimDust(alice);

    vm.prank(admin);
    controller.unpause();

    vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
    vm.prank(admin);
    controller.claimDust(alice);
  }
}
