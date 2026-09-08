// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {ReinvestmentControllerTestBase} from '../ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerDivestGasTest is ReinvestmentControllerTestBase {
  uint256 internal constant INVESTED = 400_000e6;

  function setUp() public override {
    super.setUp();
    _invest(INVESTED);
  }

  function test_divest() public {
    uint256 amount = INVESTED / 2;
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(amount));

    vm.prank(keeper);
    controller.divest(amount, attestation, hex'1234');
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'divest: partial');

    assertEq(controller.getInvestedAmount(), INVESTED - amount);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTED + amount);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function test_divest_fullSweptBalance() public {
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(INVESTED));

    vm.prank(keeper);
    controller.divest(INVESTED, attestation, hex'1234');
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'divest: full');

    assertEq(controller.getInvestedAmount(), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function test_divest_withFee() public {
    uint256 amount = INVESTED / 2;
    uint256 fee = 1e6;
    vm.prank(admin);
    controller.setMaxFee(fee);
    minter.setNextFee(fee);
    usdc.mint(keeper, fee);
    vm.prank(keeper);
    usdc.approve(address(controller), fee);
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(amount));

    vm.prank(keeper);
    controller.divest(amount, attestation, hex'1234');
    vm.snapshotGasLastFrame('ReinvestmentController.Operations', 'divest: with fee');

    assertEq(controller.getInvestedAmount(), INVESTED - amount - fee);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTED + amount + fee);
    assertEq(usdc.balanceOf(keeper), 0);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }
}
