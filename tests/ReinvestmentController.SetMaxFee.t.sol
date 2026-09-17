// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetMaxFeeTest is ReinvestmentControllerTestBase {
  uint256 internal constant INVESTED = 400_000e6;
  uint256 internal constant NEW_MAX_FEE = 2e6;

  function setUp() public override {
    super.setUp();

    _invest(INVESTED);
    _pause();
  }

  function test_setMaxFee() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxFee(MAX_FEE, NEW_MAX_FEE);

    vm.prank(admin);
    controller.setMaxFee(NEW_MAX_FEE);

    assertEq(controller.getMaxFee(), NEW_MAX_FEE);
  }

  function test_setMaxFee(uint256 maxFee_) public {
    vm.prank(admin);
    controller.setMaxFee(maxFee_);

    assertEq(controller.getMaxFee(), maxFee_);
  }

  function test_setMaxFee_admitsABurnIntentAtTheNewMaximum() public {
    vm.prank(admin);
    controller.setMaxFee(NEW_MAX_FEE);
    _unpause();

    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6), NEW_MAX_FEE);
    (bytes32 digest, bytes memory signature) = _signBurnIntent(keeperPrivateKey, intent);

    assertEq(controller.isValidSignature(digest, signature), IERC1271.isValidSignature.selector);
  }

  function test_setMaxFee_zeroRejectsEveryFeeBearingBurnIntent() public {
    vm.startPrank(admin);
    controller.setMaxFee(NEW_MAX_FEE);
    controller.setMaxFee(0);
    vm.stopPrank();
    _unpause();

    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6), 1);
    (bytes32 digest, bytes memory signature) = _signBurnIntent(keeperPrivateKey, intent);

    assertEq(controller.getMaxFee(), 0);

    vm.expectRevert(IReinvestmentController.MaxFeeExceeded.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_setMaxFee_appliesToDivest() public {
    vm.prank(admin);
    controller.setMaxFee(NEW_MAX_FEE);
    _unpause();

    usdc.mint(keeper, NEW_MAX_FEE);
    vm.prank(keeper);
    usdc.approve(address(controller), NEW_MAX_FEE);

    uint256 amount = 100_000e6;

    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(amount, NEW_MAX_FEE);

    vm.prank(keeper);
    controller.divest(amount, _encodeAttestation(_defaultTransferSpec(amount)), hex'1234');

    assertEq(usdc.balanceOf(keeper), 0);
    assertEq(controller.getInvestedAmount(), INVESTED - amount - NEW_MAX_FEE);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTED + amount + NEW_MAX_FEE);
  }

  function test_setMaxFee_revertsWith_ExpectedPause() public {
    _unpause();

    vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
    vm.prank(admin);
    controller.setMaxFee(NEW_MAX_FEE);
  }

  function test_setMaxFee_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.setMaxFee(NEW_MAX_FEE);
  }
}
