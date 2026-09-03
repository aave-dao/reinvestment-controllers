// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerGetInvestableAmountTest is ReinvestmentControllerTestBase {
  function test_getInvestableAmount() public view {
    assertEq(controller.getInvestableAmount(), INVESTABLE);
  }

  function test_getInvestableAmount(
    uint256 supplied,
    uint256 idle,
    uint256 swept,
    uint256 liquidBufferBps_,
    uint256 exposureCapAbs_,
    uint256 exposureCapBps_
  ) public {
    supplied = bound(supplied, 0, type(uint96).max);
    idle = bound(idle, 0, type(uint96).max);
    swept = bound(swept, 0, type(uint96).max);
    liquidBufferBps_ = bound(liquidBufferBps_, 1, PERCENTAGE_FACTOR - 1);
    exposureCapAbs_ = bound(exposureCapAbs_, 0, type(uint96).max);
    exposureCapBps_ = bound(exposureCapBps_, 1, PERCENTAGE_FACTOR - 1);

    hub.setAccounting(supplied, idle, swept);

    vm.startPrank(admin);
    controller.setLiquidBufferBps(liquidBufferBps_);
    controller.setExposureCapAbs(exposureCapAbs_);
    controller.setExposureCapBps(exposureCapBps_);
    vm.stopPrank();

    uint256 liquidBuffer = Math.mulDiv(
      supplied,
      liquidBufferBps_,
      PERCENTAGE_FACTOR,
      Math.Rounding.Ceil
    );
    uint256 capLimit = Math.min(
      exposureCapAbs_,
      Math.mulDiv(supplied, exposureCapBps_, PERCENTAGE_FACTOR, Math.Rounding.Floor)
    );
    uint256 capRoom = capLimit > swept ? capLimit - swept : 0;
    uint256 expected = idle <= liquidBuffer ? 0 : Math.min(idle - liquidBuffer, capRoom);

    assertEq(controller.getInvestableAmount(), expected);
  }

  function test_getInvestableAmount_zeroWhenNothingSupplied() public {
    hub.setAccounting(0, 0, 0);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_zeroWhenIdleIsBelowLiquidBuffer() public {
    hub.setAccounting(SUPPLIED, BUFFER - 1, 0);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_zeroWhenIdleEqualsLiquidBuffer() public {
    hub.setAccounting(SUPPLIED, BUFFER, 0);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_oneWhenIdleExceedsLiquidBufferByOne() public {
    hub.setAccounting(SUPPLIED, BUFFER + 1, 0);

    assertEq(controller.getInvestableAmount(), 1);
  }

  function test_getInvestableAmount_freeIdleBindsBelowCap() public {
    hub.setAccounting(SUPPLIED, BUFFER + 1_000e6, 0);

    assertEq(controller.getInvestableAmount(), 1_000e6);
  }

  function test_getInvestableAmount_absoluteCapBindsBelowBpsCap() public {
    vm.prank(admin);
    controller.setExposureCapAbs(1_234e6);

    assertEq(controller.getInvestableAmount(), 1_234e6);
  }

  function test_getInvestableAmount_bpsCapBindsBelowAbsoluteCap() public {
    vm.prank(admin);
    controller.setExposureCapBps(250);

    assertEq(controller.getInvestableAmount(), (SUPPLIED * 250) / PERCENTAGE_FACTOR);
  }

  function test_getInvestableAmount_zeroWhenExposureCapAbsIsZero() public {
    vm.prank(admin);
    controller.setExposureCapAbs(0);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_reducedBySweptBalance() public {
    vm.prank(keeper);
    controller.invest(100_000e6);

    assertEq(controller.getInvestableAmount(), INVESTABLE - 100_000e6);
  }

  function test_getInvestableAmount_zeroWhenSweptEqualsCap() public {
    hub.setAccounting(SUPPLIED, SUPPLIED, INVESTABLE);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_zeroWhenSweptExceedsCap() public {
    hub.setAccounting(SUPPLIED, SUPPLIED, INVESTABLE + 1);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_tracksInvestAndDivest() public {
    vm.prank(keeper);
    controller.invest(100_000e6);

    assertEq(controller.getInvestableAmount(), INVESTABLE - 100_000e6);

    vm.prank(keeper);
    controller.divest(40_000e6, _encodeAttestation(_defaultTransferSpec(40_000e6)), hex'1234');

    assertEq(controller.getInvestableAmount(), INVESTABLE - 60_000e6);
  }

  function test_getInvestableAmount_ignoresWithdrawingBalance() public {
    vm.prank(keeper);
    controller.invest(100_000e6);

    vm.prank(pauser);
    controller.pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    assertEq(controller.getInvestableAmount(), INVESTABLE - 100_000e6);
  }

  function test_getInvestableAmount_roundsLiquidBufferUp() public {
    hub.setAccounting(10_001, 1_001, 0);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_roundsCapDown() public {
    hub.setAccounting(10_001, 10_001, 0);

    vm.startPrank(admin);
    controller.setLiquidBufferBps(1);
    controller.setExposureCapBps(5_000);
    vm.stopPrank();

    assertEq(controller.getInvestableAmount(), 5_000);
  }
}
