// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';

import {ReinvestmentControllerHandler} from './handlers/ReinvestmentControllerHandler.sol';
import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerInvariantsTest is ReinvestmentControllerTestBase {
  using PercentageMath for uint256;

  uint256 internal constant INVARIANT_MAX_FEE = 1e6;
  uint256 internal constant KEEPER_FEE_FUNDING = 1_000e6;

  ReinvestmentControllerHandler internal handler;

  function setUp() public override {
    super.setUp();

    _setMaxFee(INVARIANT_MAX_FEE);

    usdc.mint(keeper, KEEPER_FEE_FUNDING);
    vm.prank(keeper);
    usdc.approve(address(controller), type(uint256).max);

    _invest(INVESTABLE);

    handler = new ReinvestmentControllerHandler(
      controller,
      hub,
      wallet,
      usdc,
      admin,
      keeper,
      pauser
    );

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = handler.invest.selector;
    selectors[1] = handler.divest.selector;
    selectors[2] = handler.fullExit.selector;
    selectors[3] = handler.supplyToHub.selector;

    targetContract(address(handler));
    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  function invariant_accountedAssetsArePhysicallyHeld() public view {
    assertGe(
      usdc.balanceOf(address(hub)) + wallet.totalBalance(address(usdc), address(controller)),
      hub.getAddedAssets(assetId)
    );
  }

  function invariant_hubHoldsExactlyItsIdleLiquidity() public view {
    assertEq(usdc.balanceOf(address(hub)), hub.getAssetLiquidity(assetId));
  }

  /// @dev Equality holds while Circle's fee matches {maxFee}, as its flat fee does today, but
  /// {divest} pre-pays {maxFee} regardless, so a lower fee would leave the difference in the
  /// Gateway. Over-funding is the safe direction; the Gateway balance falling below what the Hub
  /// swept is what would leave assets unbacked
  function invariant_gatewayBalanceNeverFallsBelowSwept() public view {
    assertGe(wallet.totalBalance(address(usdc), address(controller)), hub.getAssetSwept(assetId));
  }

  function invariant_controllerHoldsNoTokensAtRest() public view {
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function invariant_sweptBalanceCanAlwaysExit() public view {
    assertEq(handler.fullExitFailures(), 0);
  }

  function invariant_investableAmountNeverBreachesTheCap() public view {
    uint256 investable = controller.getInvestableAmount();
    if (investable == 0) return;

    uint256 capLimit = Math.min(
      controller.getExposureCapAbs(),
      hub.getAddedAssets(assetId).percentMulDown(controller.getExposureCapBps())
    );

    assertLe(hub.getAssetSwept(assetId) + investable, capLimit);
  }

  function invariant_investableAmountNeverBreachesTheLiquidBuffer() public view {
    uint256 investable = controller.getInvestableAmount();
    if (investable == 0) return;

    assertGe(
      hub.getAssetLiquidity(assetId) - investable,
      hub.getAddedAssets(assetId).percentMulUp(controller.getLiquidBufferBps())
    );
  }
}
