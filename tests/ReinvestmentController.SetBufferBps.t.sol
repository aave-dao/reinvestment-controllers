// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetBufferBpsTest is ReinvestmentControllerTestBase {
  function test_setBufferBps() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetBufferBps(BUFFER_BPS, 2_500);

    vm.prank(admin);
    controller.setBufferBps(2_500);

    assertEq(controller.bufferBps(), 2_500);
  }

  function test_setBufferBps(uint256 bufferBps_) public {
    bufferBps_ = bound(bufferBps_, 1, PERCENTAGE_FACTOR - 1);

    vm.prank(admin);
    controller.setBufferBps(bufferBps_);

    assertEq(controller.bufferBps(), bufferBps_);
  }

  function test_setBufferBps_atMaximumAllowedValue() public {
    vm.prank(admin);
    controller.setBufferBps(PERCENTAGE_FACTOR - 1);

    assertEq(controller.bufferBps(), PERCENTAGE_FACTOR - 1);
  }

  function test_setBufferBps_shrinksInvestableAmount() public {
    vm.prank(admin);
    controller.setBufferBps(5_000);

    assertEq(controller.getInvestableAmount(), SUPPLIED - (SUPPLIED * 5_000) / PERCENTAGE_FACTOR);
  }

  function test_setBufferBps_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        investor,
        adminRole
      )
    );
    vm.prank(investor);
    controller.setBufferBps(2_500);
  }

  function test_setBufferBps_revertsWith_InvalidAmount_zero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setBufferBps(0);
  }

  function test_setBufferBps_revertsWith_InvalidAmount_atPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setBufferBps(PERCENTAGE_FACTOR);
  }

  function test_setBufferBps_revertsWith_InvalidAmount_abovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setBufferBps(PERCENTAGE_FACTOR + 1);
  }
}
