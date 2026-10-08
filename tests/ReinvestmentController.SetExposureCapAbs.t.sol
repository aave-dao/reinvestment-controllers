// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerSetExposureCapAbsTest is ReinvestmentControllerTestBase {
  function test_setExposureCapAbs() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetExposureCapAbs(EXPOSURE_CAP_ABS, 1_000e6);

    vm.prank(admin);
    controller.setExposureCapAbs(1_000e6);

    assertEq(controller.getExposureCapAbs(), 1_000e6);
    assertEq(controller.getInvestableAmount(), 1_000e6);
  }

  function test_setExposureCapAbs(uint256 exposureCapAbs_) public {
    vm.prank(admin);
    controller.setExposureCapAbs(exposureCapAbs_);

    assertEq(controller.getExposureCapAbs(), exposureCapAbs_);
  }

  function test_setExposureCapAbs_zeroSunsetsController() public {
    vm.prank(admin);
    controller.setExposureCapAbs(0);

    assertEq(controller.getExposureCapAbs(), 0);
    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_setExposureCapAbs_stillAllowsDivest() public {
    vm.prank(keeper);
    controller.invest(100_000e6);

    vm.prank(admin);
    controller.setExposureCapAbs(0);

    vm.prank(keeper);
    controller.divest(100_000e6, _encodeAttestation(_defaultTransferSpec(100_000e6)), hex'1234');

    assertEq(controller.getInvestedAmount(), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
  }

  function test_setExposureCapAbs_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        keeper,
        adminRole
      )
    );
    vm.prank(keeper);
    controller.setExposureCapAbs(1_000e6);
  }
}
