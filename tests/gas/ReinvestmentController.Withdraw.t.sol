// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {ReinvestmentControllerTestBase} from '../ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerWithdrawGasTest is ReinvestmentControllerTestBase {
  function test_withdraw() public {
    _invest(INVESTABLE);
    _pause();
    vm.prank(admin);
    controller.initiateWithdrawal();
    vm.roll(block.number + WITHDRAWAL_DELAY);

    vm.prank(admin);
    controller.withdraw();
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'withdraw');

    assertEq(hub.getAssetSwept(assetId), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), 0);
    assertEq(usdc.balanceOf(address(controller)), 0);
    assertTrue(controller.paused());
  }
}
