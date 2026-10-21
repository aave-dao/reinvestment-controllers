// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetLiquidBufferBpsTest is ReinvestmentControllerTestBase {
  function test_setLiquidBufferBps() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetLiquidBufferBps(LIQUID_BUFFER_BPS, 2_500);

    vm.prank(admin);
    controller.setLiquidBufferBps(2_500);

    assertEq(controller.getLiquidBufferBps(), 2_500);
  }

  function test_setLiquidBufferBps(uint256 liquidBufferBps_) public {
    liquidBufferBps_ = bound(liquidBufferBps_, 1, PERCENTAGE_FACTOR - 1);

    vm.prank(admin);
    controller.setLiquidBufferBps(liquidBufferBps_);

    assertEq(controller.getLiquidBufferBps(), liquidBufferBps_);
  }

  function test_setLiquidBufferBps_atMaximumAllowedValue() public {
    vm.prank(admin);
    controller.setLiquidBufferBps(PERCENTAGE_FACTOR - 1);

    assertEq(controller.getLiquidBufferBps(), PERCENTAGE_FACTOR - 1);
  }

  function test_setLiquidBufferBps_shrinksInvestableAmount() public {
    vm.prank(admin);
    controller.setLiquidBufferBps(5_000);

    assertEq(controller.getInvestableAmount(), SUPPLIED - (SUPPLIED * 5_000) / PERCENTAGE_FACTOR);
  }

  function test_setLiquidBufferBps_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.setLiquidBufferBps(2_500);
  }

  function test_setLiquidBufferBps_revertsWith_InvalidAmount_zero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setLiquidBufferBps(0);
  }

  function test_setLiquidBufferBps_revertsWith_InvalidAmount_atPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setLiquidBufferBps(PERCENTAGE_FACTOR);
  }

  function test_setLiquidBufferBps_revertsWith_InvalidAmount_abovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setLiquidBufferBps(PERCENTAGE_FACTOR + 1);
  }
}
