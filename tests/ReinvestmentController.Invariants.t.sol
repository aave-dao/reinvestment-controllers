// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';

import {ReinvestmentControllerHandler} from './handlers/ReinvestmentControllerHandler.sol';
import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerInvariantsTest is ReinvestmentControllerTestBase {
  using PercentageMath for uint256;

  ReinvestmentControllerHandler internal handler;

  function setUp() public override {
    super.setUp();

    handler = new ReinvestmentControllerHandler(
      controller,
      hub,
      wallet,
      usdc,
      admin,
      keeper,
      pauser
    );

    targetContract(address(handler));
  }

  function invariant_liquidityPlusSweptEqualsAddedAssets() public view {
    assertEq(
      hub.getAssetLiquidity(assetId) + hub.getAssetSwept(assetId),
      hub.getAddedAssets(assetId)
    );
  }

  function invariant_hubHoldsExactlyItsIdleLiquidity() public view {
    assertEq(usdc.balanceOf(address(hub)), hub.getAssetLiquidity(assetId));
  }

  function invariant_sweptIsBackedByTheGatewayBalance() public view {
    assertEq(hub.getAssetSwept(assetId), wallet.totalBalance(address(usdc), address(controller)));
  }

  function invariant_controllerHoldsNoTokensAtRest() public view {
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function invariant_controllerHoldsNoResidualAllowance() public view {
    assertEq(usdc.allowance(address(controller), address(wallet)), 0);
  }

  function invariant_totalSupplyIsBackedByHubAndGateway() public view {
    assertEq(usdc.totalSupply(), usdc.balanceOf(address(hub)) + usdc.balanceOf(address(wallet)));
  }

  function invariant_investableAmountNeverBreachesTheCap() public view {
    uint256 investable = controller.getInvestableAmount();
    if (investable == 0) return;

    uint256 capLimit = Math.min(
      controller.maxInvest(),
      hub.getAddedAssets(assetId).percentMulDown(controller.maxInvestBps())
    );

    assertLe(hub.getAssetSwept(assetId) + investable, capLimit);
  }

  function invariant_investableAmountNeverBreachesTheBuffer() public view {
    uint256 investable = controller.getInvestableAmount();
    if (investable == 0) return;

    assertGe(
      hub.getAssetLiquidity(assetId) - investable,
      hub.getAddedAssets(assetId).percentMulUp(controller.bufferBps())
    );
  }

  function invariant_investableNeverExceedsIdleLiquidity() public view {
    assertLe(controller.getInvestableAmount(), hub.getAssetLiquidity(assetId));
  }

  function invariant_pausedAtIsSetExactlyWhilePaused() public view {
    assertEq(controller.pausedAt() != 0, controller.paused());
  }

  function invariant_withdrawalsOnlyRunWhilePaused() public view {
    if (wallet.withdrawingBalance(address(usdc), address(controller)) > 0) {
      assertTrue(controller.paused());
    }
  }

  function invariant_investedNeverBelowDivested() public view {
    assertGe(handler.totalInvested(), handler.totalDivested());
  }

  function afterInvariant() public view {
    assertGt(handler.investCalls(), 0);
    assertGt(handler.divestCalls(), 0);
    assertGt(handler.initiateWithdrawalCalls(), 0);
    assertGt(handler.withdrawCalls(), 0);
  }
}
