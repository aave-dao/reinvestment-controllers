// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerPauseTest is ReinvestmentControllerTestBase {
  function test_pause() public {
    vm.expectEmit(address(controller));
    emit PausableUpgradeable.Paused(pauser);

    vm.prank(pauser);
    controller.pause();

    assertTrue(controller.paused());
    assertEq(controller.pausedAt(), block.timestamp);
  }

  function test_pause(uint256 timestamp) public {
    timestamp = bound(timestamp, block.timestamp, block.timestamp + 3650 days);
    vm.warp(timestamp);

    vm.prank(pauser);
    controller.pause();

    assertEq(controller.pausedAt(), timestamp);
  }

  function test_pause_byAdmin() public {
    vm.prank(admin);
    controller.pause();

    assertTrue(controller.paused());
    assertEq(controller.pausedAt(), block.timestamp);
  }

  function test_pause_recordsLatestTimestampAcrossPauseCycles() public {
    vm.prank(pauser);
    controller.pause();

    vm.prank(admin);
    controller.unpause();

    vm.warp(block.timestamp + 5 days);

    vm.prank(pauser);
    controller.pause();

    assertEq(controller.pausedAt(), block.timestamp);
  }

  function test_pause_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 pauserRole = controller.PAUSER_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        alice,
        pauserRole
      )
    );
    vm.prank(alice);
    controller.pause();
  }

  function test_pause_revertsWith_AccessControlUnauthorizedAccount_keeperIsNotPauser() public {
    bytes32 pauserRole = controller.PAUSER_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        pauserRole
      )
    );
    vm.prank(keeper);
    controller.pause();
  }

  function test_pause_revertsWith_EnforcedPause_alreadyPaused() public {
    vm.prank(pauser);
    controller.pause();

    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    vm.prank(pauser);
    controller.pause();
  }
}
