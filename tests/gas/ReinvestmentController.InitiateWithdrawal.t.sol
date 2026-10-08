// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {ReinvestmentControllerTestBase} from '../ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerInitiateWithdrawalGasTest is ReinvestmentControllerTestBase {
  function test_initiateWithdrawal() public {
    _invest(INVESTABLE);
    _pause();

    vm.prank(admin);
    controller.initiateWithdrawal();
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'initiateWithdrawal');

    assertEq(wallet.availableBalance(address(usdc), address(controller)), 0);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), INVESTABLE);
    assertEq(hub.getAssetSwept(assetId), INVESTABLE);
  }
}
