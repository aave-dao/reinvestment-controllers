// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';

import {ReinvestmentController} from '../src/ReinvestmentController.sol';
import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract UninitializedProxy is ERC1967Proxy {
  constructor(address implementation_) ERC1967Proxy(implementation_, '') {}

  function _unsafeAllowUninitialized() internal pure override returns (bool) {
    return true;
  }
}

contract ReinvestmentControllerInitializeTest is ReinvestmentControllerTestBase {
  ReinvestmentController internal fresh;

  function setUp() public override {
    super.setUp();

    fresh = ReinvestmentController(address(new UninitializedProxy(address(implementation))));
  }

  function test_initialize() public {
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetInvestMinDelay(0, INVEST_MIN_DELAY);
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetExposureCapAbs(0, EXPOSURE_CAP_ABS);
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetExposureCapBps(0, EXPOSURE_CAP_BPS);
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetMaxFee(0, MAX_FEE);
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetLiquidBufferBps(0, LIQUID_BUFFER_BPS);

    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );

    assertEq(fresh.getInvestMinDelay(), INVEST_MIN_DELAY);
    assertEq(fresh.getLastInvestTimestamp(), 0);
    assertEq(fresh.getExposureCapAbs(), EXPOSURE_CAP_ABS);
    assertEq(fresh.getExposureCapBps(), EXPOSURE_CAP_BPS);
    assertEq(fresh.getMaxFee(), MAX_FEE);
    assertEq(fresh.getLiquidBufferBps(), LIQUID_BUFFER_BPS);
    assertFalse(fresh.paused());

    assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(fresh.hasRole(fresh.KEEPER_ROLE(), admin));
    assertTrue(fresh.hasRole(fresh.PAUSER_ROLE(), admin));

    assertEq(fresh.getRoleAdmin(fresh.KEEPER_ROLE()), fresh.DEFAULT_ADMIN_ROLE());
    assertEq(fresh.getRoleAdmin(fresh.PAUSER_ROLE()), fresh.DEFAULT_ADMIN_ROLE());
  }

  function test_initialize(
    uint256 investMinDelay_,
    uint256 exposureCapAbs_,
    uint256 exposureCapBps_,
    uint256 maxFee_,
    uint256 liquidBufferBps_
  ) public {
    investMinDelay_ = bound(investMinDelay_, 1, 365 days);
    exposureCapAbs_ = bound(exposureCapAbs_, 0, type(uint128).max);
    exposureCapBps_ = bound(exposureCapBps_, 1, PERCENTAGE_FACTOR - 1);
    liquidBufferBps_ = bound(liquidBufferBps_, 1, PERCENTAGE_FACTOR - 1);

    fresh.initialize(
      admin,
      investMinDelay_,
      exposureCapAbs_,
      exposureCapBps_,
      maxFee_,
      liquidBufferBps_
    );

    assertEq(fresh.getInvestMinDelay(), investMinDelay_);
    assertEq(fresh.getExposureCapAbs(), exposureCapAbs_);
    assertEq(fresh.getExposureCapBps(), exposureCapBps_);
    assertEq(fresh.getMaxFee(), maxFee_);
    assertEq(fresh.getLiquidBufferBps(), liquidBufferBps_);
  }

  function test_initialize_grantsEveryRoleToAdminOnly() public {
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );

    assertFalse(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), alice));
    assertFalse(fresh.hasRole(fresh.KEEPER_ROLE(), alice));
    assertFalse(fresh.hasRole(fresh.PAUSER_ROLE(), alice));
  }

  function test_initialize_leavesImmutablesUntouched() public {
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );

    assertEq(address(fresh.GATEWAY_WALLET()), address(wallet));
    assertEq(address(fresh.GATEWAY_MINTER()), address(minter));
    assertEq(address(fresh.HUB()), address(hub));
    assertEq(address(fresh.USDC()), address(usdc));
    assertEq(fresh.ASSET_ID(), assetId);
  }

  function test_initialize_allowsZeroExposureCapAbs() public {
    fresh.initialize(admin, INVEST_MIN_DELAY, 0, EXPOSURE_CAP_BPS, MAX_FEE, LIQUID_BUFFER_BPS);

    assertEq(fresh.getExposureCapAbs(), 0);
    assertEq(fresh.getInvestableAmount(), 0);
  }

  function test_initialize_callableByAnyone() public {
    vm.prank(alice);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );

    assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
    assertFalse(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), alice));
  }

  function test_initialize_revertsWith_InvalidZeroAddress() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    fresh.initialize(
      address(0),
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );
  }

  function test_initialize_revertsWith_InvalidAmount_investMinDelayIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(admin, 0, EXPOSURE_CAP_ABS, EXPOSURE_CAP_BPS, MAX_FEE, LIQUID_BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_exposureCapBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(admin, INVEST_MIN_DELAY, EXPOSURE_CAP_ABS, 0, MAX_FEE, LIQUID_BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_exposureCapBpsAtPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      PERCENTAGE_FACTOR,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );
  }

  function test_initialize_revertsWith_InvalidAmount_exposureCapBpsAbovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      PERCENTAGE_FACTOR + 1,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );
  }

  function test_initialize_revertsWith_InvalidAmount_liquidBufferBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(admin, INVEST_MIN_DELAY, EXPOSURE_CAP_ABS, EXPOSURE_CAP_BPS, MAX_FEE, 0);
  }

  function test_initialize_revertsWith_InvalidAmount_liquidBufferBpsAtPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      PERCENTAGE_FACTOR
    );
  }

  function test_initialize_revertsWith_InvalidAmount_liquidBufferBpsAbovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      PERCENTAGE_FACTOR + 1
    );
  }

  function test_initialize_revertsWith_InvalidInitialization_calledTwice() public {
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );
  }

  function test_initialize_revertsWith_InvalidInitialization_proxyInitializedAtDeployment() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    controller.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );
  }
}
