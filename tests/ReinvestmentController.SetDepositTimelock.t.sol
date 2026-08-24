// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetDepositTimelockTest is ReinvestmentControllerTestBase {
  function test_setDepositTimelock() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetDepositTimelock(DEPOSIT_TIMELOCK, 7 days);

    vm.prank(admin);
    controller.setDepositTimelock(7 days);

    assertEq(controller.depositTimelock(), 7 days);
  }

  function test_setDepositTimelock(uint256 depositTimelock_) public {
    depositTimelock_ = bound(depositTimelock_, 1, 3650 days);

    vm.prank(admin);
    controller.setDepositTimelock(depositTimelock_);

    assertEq(controller.depositTimelock(), depositTimelock_);
  }

  function test_setDepositTimelock_appliesToTheNextInvest() public {
    vm.prank(investor);
    controller.invest(1_000e6);

    vm.prank(admin);
    controller.setDepositTimelock(1);

    vm.warp(block.timestamp + 2);

    vm.prank(investor);
    controller.invest(1_000e6);

    assertEq(controller.getInvestedAmount(), 2_000e6);
  }

  function test_setDepositTimelock_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        investor,
        adminRole
      )
    );
    vm.prank(investor);
    controller.setDepositTimelock(7 days);
  }

  function test_setDepositTimelock_revertsWith_InvalidAmount() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(admin);
    controller.setDepositTimelock(0);
  }
}
