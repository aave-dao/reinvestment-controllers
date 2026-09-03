// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetMaxInvestTest is ReinvestmentControllerTestBase {
  function test_setMaxInvest() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxInvest(MAX_INVEST, 1_000e6);

    vm.prank(admin);
    controller.setMaxInvest(1_000e6);

    assertEq(controller.getMaxInvest(), 1_000e6);
    assertEq(controller.getInvestableAmount(), 1_000e6);
  }

  function test_setMaxInvest(uint256 maxInvest_) public {
    vm.prank(admin);
    controller.setMaxInvest(maxInvest_);

    assertEq(controller.getMaxInvest(), maxInvest_);
  }

  function test_setMaxInvest_zeroSunsetsController() public {
    vm.prank(admin);
    controller.setMaxInvest(0);

    assertEq(controller.getMaxInvest(), 0);
    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_setMaxInvest_stillAllowsDivest() public {
    vm.prank(keeper);
    controller.invest(100_000e6);

    vm.prank(admin);
    controller.setMaxInvest(0);

    vm.prank(keeper);
    controller.divest(100_000e6, _encodeAttestation(_defaultTransferSpec(100_000e6)), hex'1234');

    assertEq(controller.getInvestedAmount(), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
  }

  function test_setMaxInvest_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.setMaxInvest(1_000e6);
  }
}
