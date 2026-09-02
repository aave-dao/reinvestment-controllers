// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetMaxInvestBpsTest is ReinvestmentControllerTestBase {
  function test_setMaxInvestBps() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxInvestBps(MAX_INVEST_BPS, 1_000);

    vm.prank(admin);
    controller.setMaxInvestBps(1_000);

    assertEq(controller.maxInvestBps(), 1_000);
  }

  function test_setMaxInvestBps(uint256 maxInvestBps_) public {
    maxInvestBps_ = bound(maxInvestBps_, 1, PERCENTAGE_FACTOR - 1);

    vm.prank(admin);
    controller.setMaxInvestBps(maxInvestBps_);

    assertEq(controller.maxInvestBps(), maxInvestBps_);
  }

  function test_setMaxInvestBps_boundsInvestableAmount() public {
    vm.prank(admin);
    controller.setMaxInvestBps(100);

    assertEq(controller.getInvestableAmount(), (SUPPLIED * 100) / PERCENTAGE_FACTOR);
  }

  function test_setMaxInvestBps_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        investor,
        adminRole
      )
    );
    vm.prank(investor);
    controller.setMaxInvestBps(1_000);
  }

  function test_setMaxInvestBps_revertsWith_InvalidAmount_zero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setMaxInvestBps(0);
  }

  function test_setMaxInvestBps_revertsWith_InvalidAmount_atPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setMaxInvestBps(PERCENTAGE_FACTOR);
  }

  function test_setMaxInvestBps_revertsWith_InvalidAmount_abovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setMaxInvestBps(PERCENTAGE_FACTOR + 1);
  }
}
