// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetInvestMinDelayTest is ReinvestmentControllerTestBase {
  function test_setInvestMinDelay() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetInvestMinDelay(INVEST_MIN_DELAY, 7 days);

    vm.prank(admin);
    controller.setInvestMinDelay(7 days);

    assertEq(controller.investMinDelay(), 7 days);
  }

  function test_setInvestMinDelay(uint256 investMinDelay_) public {
    investMinDelay_ = bound(investMinDelay_, 1, 3650 days);

    vm.prank(admin);
    controller.setInvestMinDelay(investMinDelay_);

    assertEq(controller.investMinDelay(), investMinDelay_);
  }

  function test_setInvestMinDelay_appliesToTheNextInvest() public {
    vm.prank(keeper);
    controller.invest(1_000e6);

    vm.prank(admin);
    controller.setInvestMinDelay(1);

    vm.warp(block.timestamp + 2);

    vm.prank(keeper);
    controller.invest(1_000e6);

    assertEq(controller.getInvestedAmount(), 2_000e6);
  }

  function test_setInvestMinDelay_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.setInvestMinDelay(7 days);
  }

  function test_setInvestMinDelay_revertsWith_InvalidAmount() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setInvestMinDelay(0);
  }
}
