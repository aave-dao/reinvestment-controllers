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
    emit IReinvestmentController.SetMaxInvest(0, MAX_INVEST);
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetMaxInvestBps(0, MAX_INVEST_BPS);
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetMaxFee(0, MAX_FEE);
    vm.expectEmit(address(fresh));
    emit IReinvestmentController.SetBufferBps(0, BUFFER_BPS);

    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);

    assertEq(fresh.investMinDelay(), INVEST_MIN_DELAY);
    assertEq(fresh.maxInvest(), MAX_INVEST);
    assertEq(fresh.maxInvestBps(), MAX_INVEST_BPS);
    assertEq(fresh.maxFee(), MAX_FEE);
    assertEq(fresh.bufferBps(), BUFFER_BPS);
    assertEq(fresh.pausedAt(), 0);
    assertFalse(fresh.paused());

    assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(fresh.hasRole(fresh.KEEPER_ROLE(), admin));
    assertTrue(fresh.hasRole(fresh.PAUSER_ROLE(), admin));

    assertEq(fresh.getRoleAdmin(fresh.KEEPER_ROLE()), fresh.DEFAULT_ADMIN_ROLE());
    assertEq(fresh.getRoleAdmin(fresh.PAUSER_ROLE()), fresh.DEFAULT_ADMIN_ROLE());
  }

  function test_initialize(
    uint256 investMinDelay_,
    uint256 maxInvest_,
    uint256 maxInvestBps_,
    uint256 maxFee_,
    uint256 bufferBps_
  ) public {
    investMinDelay_ = bound(investMinDelay_, 1, 365 days);
    maxInvest_ = bound(maxInvest_, 0, type(uint128).max);
    maxInvestBps_ = bound(maxInvestBps_, 1, PERCENTAGE_FACTOR - 1);
    bufferBps_ = bound(bufferBps_, 1, PERCENTAGE_FACTOR - 1);

    fresh.initialize(admin, investMinDelay_, maxInvest_, maxInvestBps_, maxFee_, bufferBps_);

    assertEq(fresh.investMinDelay(), investMinDelay_);
    assertEq(fresh.maxInvest(), maxInvest_);
    assertEq(fresh.maxInvestBps(), maxInvestBps_);
    assertEq(fresh.maxFee(), maxFee_);
    assertEq(fresh.bufferBps(), bufferBps_);
  }

  function test_initialize_grantsEveryRoleToAdminOnly() public {
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);

    assertFalse(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), alice));
    assertFalse(fresh.hasRole(fresh.KEEPER_ROLE(), alice));
    assertFalse(fresh.hasRole(fresh.PAUSER_ROLE(), alice));
  }

  function test_initialize_leavesImmutablesUntouched() public {
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);

    assertEq(address(fresh.GATEWAY_WALLET()), address(wallet));
    assertEq(address(fresh.GATEWAY_MINTER()), address(minter));
    assertEq(address(fresh.HUB()), address(hub));
    assertEq(address(fresh.USDC()), address(usdc));
    assertEq(fresh.ASSET_ID(), assetId);
  }

  function test_initialize_allowsZeroMaxInvest() public {
    fresh.initialize(admin, INVEST_MIN_DELAY, 0, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);

    assertEq(fresh.maxInvest(), 0);
    assertEq(fresh.getInvestableAmount(), 0);
  }

  function test_initialize_callableByAnyone() public {
    vm.prank(alice);
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);

    assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
    assertFalse(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), alice));
  }

  function test_initialize_revertsWith_InvalidZeroAddress() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    fresh.initialize(address(0), INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_investMinDelayIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(admin, 0, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_maxInvestBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, 0, MAX_FEE, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_maxInvestBpsAtPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, PERCENTAGE_FACTOR, MAX_FEE, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_maxInvestBpsAbovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      MAX_INVEST,
      PERCENTAGE_FACTOR + 1,
      MAX_FEE,
      BUFFER_BPS
    );
  }

  function test_initialize_revertsWith_InvalidAmount_bufferBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, 0);
  }

  function test_initialize_revertsWith_InvalidAmount_bufferBpsAtPercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      MAX_INVEST,
      MAX_INVEST_BPS,
      MAX_FEE,
      PERCENTAGE_FACTOR
    );
  }

  function test_initialize_revertsWith_InvalidAmount_bufferBpsAbovePercentageFactor() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    fresh.initialize(
      admin,
      INVEST_MIN_DELAY,
      MAX_INVEST,
      MAX_INVEST_BPS,
      MAX_FEE,
      PERCENTAGE_FACTOR + 1
    );
  }

  function test_initialize_revertsWith_InvalidInitialization_calledTwice() public {
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    fresh.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidInitialization_proxyInitializedAtDeployment() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    controller.initialize(admin, INVEST_MIN_DELAY, MAX_INVEST, MAX_INVEST_BPS, MAX_FEE, BUFFER_BPS);
  }
}
