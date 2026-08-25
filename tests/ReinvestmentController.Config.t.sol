// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from 'forge-std/Test.sol';
import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import {ReinvestmentController, IReinvestmentController} from '../src/ReinvestmentController.sol';
import {MockERC20} from './mocks/MockERC20.sol';
import {MockGatewayMinter} from './mocks/MockGatewayMinter.sol';
import {MockGatewayWallet} from './mocks/MockGatewayWallet.sol';
import {MockHub} from './mocks/MockHub.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerPauseTest is ReinvestmentControllerTestBase {
  function test_pause_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.PAUSER_ROLE()
      )
    );
    controller.pause();
  }

  function test_pause_revertsWith_EnforcedPause() public {
    vm.prank(admin);
    controller.pause();

    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    controller.pause();
  }

  function test_pause() public {
    vm.expectEmit(address(controller));
    emit PausableUpgradeable.Paused(admin);

    vm.prank(admin);
    controller.pause();

    assertTrue(controller.paused());
  }
}

contract ReinvestmentControllerUnpauseTest is ReinvestmentControllerTestBase {
  address public pauser = makeAddr('pauser');

  function test_unpause_revertsWith_WithdrawalInProcess() public {
    _invest(INVESTABLE);
    _pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.WithdrawalInProcess.selector);
    controller.unpause();
  }

  function test_unpause_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.prank(admin);
    controller.pause();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.unpause();
  }

  function test_unpause_revertsWith_AccessControlUnauthorizedAccount_pauserWithoutAdmin() public {
    bytes32 role = controller.PAUSER_ROLE();

    vm.prank(admin);
    controller.grantRole(role, pauser);

    vm.prank(pauser);
    controller.pause();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        pauser,
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(pauser);
    controller.unpause();
  }

  function test_unpause_revertsWith_ExpectedPause() public {
    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
    controller.unpause();
  }

  function test_unpause() public {
    vm.prank(admin);
    controller.pause();

    vm.expectEmit(address(controller));
    emit PausableUpgradeable.Unpaused(admin);

    vm.prank(admin);
    controller.unpause();

    assertFalse(controller.paused());
  }
}

contract ReinvestmentControllerSetDepositTimelockTest is ReinvestmentControllerTestBase {
  uint256 public constant NEW_DEPOSIT_TIMELOCK = 2 days;

  function test_setDepositTimelock_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setDepositTimelock(NEW_DEPOSIT_TIMELOCK);
  }

  function test_setDepositTimelock_revertsWith_InvalidAmount() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setDepositTimelock(0);
  }

  function test_setDepositTimelock() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetDepositTimelock(DEPOSIT_TIMELOCK, NEW_DEPOSIT_TIMELOCK);

    vm.prank(admin);
    controller.setDepositTimelock(NEW_DEPOSIT_TIMELOCK);

    assertEq(controller.depositTimelock(), NEW_DEPOSIT_TIMELOCK);
  }
}

contract ReinvestmentControllerSetBufferBpsTest is ReinvestmentControllerTestBase {
  uint256 public constant NEW_BUFFER_BPS = 2_000;

  function test_setBufferBps_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setBufferBps(NEW_BUFFER_BPS);
  }

  function test_setBufferBps_revertsWith_InvalidAmount_bufferIsZero() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setBufferBps(0);
  }

  function test_setBufferBps_revertsWith_InvalidAmount_bufferAtMax() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setBufferBps(10_000);
  }

  function test_setBufferBps() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetBufferBps(BUFFER_BPS, NEW_BUFFER_BPS);

    vm.prank(admin);
    controller.setBufferBps(NEW_BUFFER_BPS);

    assertEq(controller.bufferBps(), NEW_BUFFER_BPS);
  }
}

contract ReinvestmentControllerSetMaxFeeTest is ReinvestmentControllerTestBase {
  uint256 public constant NEW_MAX_FEE = 2e6;

  function test_setMaxFee_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setMaxFee(NEW_MAX_FEE);
  }

  function test_setMaxFee_allowsZeroToRejectAllFees() public {
    vm.prank(admin);
    controller.setMaxFee(0);

    assertEq(controller.maxFee(), 0);
  }

  function test_setMaxFee() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxFee(MAX_FEE, NEW_MAX_FEE);

    vm.prank(admin);
    controller.setMaxFee(NEW_MAX_FEE);

    assertEq(controller.maxFee(), NEW_MAX_FEE);
  }
}

contract ReinvestmentControllerSetMaxInvestTest is ReinvestmentControllerTestBase {
  uint256 public constant NEW_MAX_INVEST = 50_000_000e6;

  function test_setMaxInvest_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setMaxInvest(NEW_MAX_INVEST);
  }

  function test_setMaxInvest_allowsZeroToSunset() public {
    vm.prank(admin);
    controller.setMaxInvest(0);

    assertEq(controller.maxInvest(), 0);
    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_setMaxInvest() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxInvest(MAX_INVEST, NEW_MAX_INVEST);

    vm.prank(admin);
    controller.setMaxInvest(NEW_MAX_INVEST);

    assertEq(controller.maxInvest(), NEW_MAX_INVEST);
  }
}

contract ReinvestmentControllerSetMaxInvestBpsTest is ReinvestmentControllerTestBase {
  uint256 public constant NEW_MAX_INVEST_BPS = 5_000;

  function test_setMaxInvestBps_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setMaxInvestBps(NEW_MAX_INVEST_BPS);
  }

  function test_setMaxInvestBps_revertsWith_InvalidAmount_bpsIsZero() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setMaxInvestBps(0);
  }

  function test_setMaxInvestBps_revertsWith_InvalidAmount_bpsAtMax() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setMaxInvestBps(10_000);
  }

  function test_setMaxInvestBps() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxInvestBps(MAX_INVEST_BPS, NEW_MAX_INVEST_BPS);

    vm.prank(admin);
    controller.setMaxInvestBps(NEW_MAX_INVEST_BPS);

    assertEq(controller.maxInvestBps(), NEW_MAX_INVEST_BPS);
  }
}

contract ReinvestmentControllerGetInvestableAmountTest is ReinvestmentControllerTestBase {
  function test_getInvestableAmount_zeroWhenNoAssetsSupplied() public {
    hub.setAddedAssets(ASSET_ID, 0);
    hub.setLiquidity(ASSET_ID, 0);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_zeroWhenIdleEqualsBuffer() public {
    hub.setLiquidity(ASSET_ID, (SUPPLIED * BUFFER_BPS) / 100_00);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_zeroWhenIdleBelowBuffer() public {
    hub.setLiquidity(ASSET_ID, (SUPPLIED * BUFFER_BPS) / 100_00 - 1);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_zeroWhenSweptEqualsCap() public {
    hub.setSwept(ASSET_ID, INVESTABLE);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_zeroWhenSweptExceedsCap() public {
    hub.setSwept(ASSET_ID, INVESTABLE + 1);

    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_getInvestableAmount_reducedBySweptAmount() public {
    hub.setSwept(ASSET_ID, 300_000e6);

    assertEq(controller.getInvestableAmount(), INVESTABLE - 300_000e6);
  }

  function test_getInvestableAmount_freeIdleBindsBelowCap() public {
    hub.setLiquidity(ASSET_ID, 200_000e6);

    assertEq(controller.getInvestableAmount(), 100_000e6);
  }

  function test_getInvestableAmount_absoluteCapBindsBelowBpsCap() public {
    vm.prank(admin);
    controller.setMaxInvest(50_000e6);

    assertEq(controller.getInvestableAmount(), 50_000e6);
  }

  function test_getInvestableAmount_reflectsBufferBpsChange() public {
    vm.prank(admin);
    controller.setBufferBps(50_00);

    assertEq(controller.getInvestableAmount(), 500_000e6);
  }

  function test_getInvestableAmount_reflectsMaxInvestBpsChange() public {
    vm.prank(admin);
    controller.setMaxInvestBps(50_00);

    assertEq(controller.getInvestableAmount(), 500_000e6);
  }

  function test_getInvestableAmount() public view {
    assertEq(controller.getInvestableAmount(), INVESTABLE);
  }

  function test_getInvestableAmount_neverBreachesBufferOrCap(
    uint256 bufferBps_,
    uint256 maxInvestBps_,
    uint256 liquidity
  ) public {
    bufferBps_ = bound(bufferBps_, 1, 9_999);
    maxInvestBps_ = bound(maxInvestBps_, 1, 9_999);
    liquidity = bound(liquidity, 0, SUPPLIED);

    vm.prank(admin);
    controller.setBufferBps(bufferBps_);

    vm.prank(admin);
    controller.setMaxInvestBps(maxInvestBps_);

    hub.setLiquidity(ASSET_ID, liquidity);

    uint256 investable = controller.getInvestableAmount();
    uint256 buffer = (SUPPLIED * bufferBps_ + 9_999) / 10_000;

    assertLe(investable, (SUPPLIED * maxInvestBps_) / 10_000);
    assertLe(investable, liquidity);

    if (investable > 0) {
      assertGe(liquidity - investable, buffer);
    }
  }
}
