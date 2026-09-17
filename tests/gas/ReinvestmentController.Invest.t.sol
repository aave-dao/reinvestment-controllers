// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {ReinvestmentControllerTestBase} from '../ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerInvestGasTest is ReinvestmentControllerTestBase {
  function test_invest() public {
    vm.prank(keeper);
    controller.invest(INVESTABLE);
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'invest: first');

    assertEq(controller.getInvestedAmount(), INVESTABLE);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTABLE);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function test_invest_afterMinDelay() public {
    _invest(INVESTABLE / 2);
    vm.warp(block.timestamp + INVEST_MIN_DELAY);

    vm.prank(keeper);
    controller.invest(INVESTABLE / 2);
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'invest: subsequent');

    assertEq(controller.getInvestedAmount(), INVESTABLE);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTABLE);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }
}
