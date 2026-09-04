// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetExposureCapBpsTest is ReinvestmentControllerTestBase {
  function test_setExposureCapBps() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetExposureCapBps(EXPOSURE_CAP_BPS, 1_000);

    vm.prank(admin);
    controller.setExposureCapBps(1_000);

    assertEq(controller.getExposureCapBps(), 1_000);
  }

  function test_setExposureCapBps(uint256 exposureCapBps_) public {
    exposureCapBps_ = bound(exposureCapBps_, 1, PERCENTAGE_FACTOR - 1);

    vm.prank(admin);
    controller.setExposureCapBps(exposureCapBps_);

    assertEq(controller.getExposureCapBps(), exposureCapBps_);
  }

  function test_setExposureCapBps_boundsInvestableAmount() public {
    vm.prank(admin);
    controller.setExposureCapBps(100);

    assertEq(controller.getInvestableAmount(), (SUPPLIED * 100) / PERCENTAGE_FACTOR);
  }

  function test_setExposureCapBps_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.setExposureCapBps(1_000);
  }

  function test_setExposureCapBps_revertsWith_InvalidAmount_zero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setExposureCapBps(0);
  }

  function test_setExposureCapBps_revertsWith_InvalidAmount_atPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setExposureCapBps(PERCENTAGE_FACTOR);
  }

  function test_setExposureCapBps_revertsWith_InvalidAmount_abovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setExposureCapBps(PERCENTAGE_FACTOR + 1);
  }
}
