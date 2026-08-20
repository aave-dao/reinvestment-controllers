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

import {ReinvestmentControllerTest} from './ReinvestmentControllerBase.t.sol';

contract ConstructorTest is Test {
  uint256 public constant ASSET_ID = 1;

  function test_constructor_revertsWith_gatewayWalletIsZeroAddress() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayMinter gatewayMinter = new MockGatewayMinter();
    MockHub hub = new MockHub();

    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(0), address(gatewayMinter), address(hub), address(usdc));
  }

  function test_constructor_revertsWith_gatewayMinterIsZeroAddress() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayWallet gatewayWallet = new MockGatewayWallet();
    MockHub hub = new MockHub();

    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(gatewayWallet), address(0), address(hub), address(usdc));
  }

  function test_constructor_revertsWith_hubIsZeroAddress() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayWallet gatewayWallet = new MockGatewayWallet();
    MockGatewayMinter gatewayMinter = new MockGatewayMinter();

    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(
      address(gatewayWallet),
      address(gatewayMinter),
      address(0),
      address(usdc)
    );
  }

  function test_constructor_revertsWith_usdcIsZeroAddress() public {
    MockGatewayWallet gatewayWallet = new MockGatewayWallet();
    MockGatewayMinter gatewayMinter = new MockGatewayMinter();
    MockHub hub = new MockHub();

    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(
      address(gatewayWallet),
      address(gatewayMinter),
      address(hub),
      address(0)
    );
  }

  function test_constructor_revertsWith_assetNotListedOnHub() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayWallet gatewayWallet = new MockGatewayWallet();
    MockGatewayMinter gatewayMinter = new MockGatewayMinter();
    MockHub hub = new MockHub();

    vm.expectRevert(MockHub.AssetNotListed.selector);
    new ReinvestmentController(
      address(gatewayWallet),
      address(gatewayMinter),
      address(hub),
      address(usdc)
    );
  }

  function test_constructor_locksImplementation() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayWallet gatewayWallet = new MockGatewayWallet();
    MockGatewayMinter gatewayMinter = new MockGatewayMinter();
    MockHub hub = new MockHub();
    hub.listAsset(address(usdc), ASSET_ID);

    ReinvestmentController controller = new ReinvestmentController(
      address(gatewayWallet),
      address(gatewayMinter),
      address(hub),
      address(usdc)
    );

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    controller.initialize(address(this), 1 days, 1e6, 8_000, 1_000);
  }

  function test_constructor_successful() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayWallet gatewayWallet = new MockGatewayWallet();
    MockGatewayMinter gatewayMinter = new MockGatewayMinter();
    MockHub hub = new MockHub();
    hub.listAsset(address(usdc), ASSET_ID);

    ReinvestmentController controller = new ReinvestmentController(
      address(gatewayWallet),
      address(gatewayMinter),
      address(hub),
      address(usdc)
    );

    assertEq(address(controller.GATEWAY_WALLET()), address(gatewayWallet));
    assertEq(address(controller.GATEWAY_MINTER()), address(gatewayMinter));
    assertEq(address(controller.HUB()), address(hub));
    assertEq(address(controller.USDC()), address(usdc));
    assertEq(controller.ASSET_ID(), ASSET_ID);
  }
}

contract InitializeTest is ReinvestmentControllerTest {
  function test_initialize_revertsWith_alreadyInitialized() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    controller.initialize(admin, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS);
  }

  function test_initialize_revertsWith_adminIsZeroAddress() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    _initProxy(address(0), DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS);
  }

  function test_initialize_revertsWith_depositTimelockIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, 0, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS);
  }

  function test_initialize_revertsWith_maxInvestBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, 0, BUFFER_BPS);
  }

  function test_initialize_revertsWith_maxInvestBpsAtMaxBps() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, 10_000, BUFFER_BPS);
  }

  function test_initialize_revertsWith_bufferBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, 0);
  }

  function test_initialize_revertsWith_bufferBpsAtMaxBps() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, 10_000);
  }

  function test_initialize_successful() public {
    ReinvestmentController newController = _initProxy(
      admin,
      DEPOSIT_TIMELOCK,
      MAX_INVEST,
      MAX_INVEST_BPS,
      BUFFER_BPS
    );

    assertTrue(newController.hasRole(newController.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(newController.hasRole(newController.INVESTOR_ROLE(), admin));
    assertTrue(newController.hasRole(newController.PAUSER_ROLE(), admin));

    assertFalse(newController.paused());

    assertEq(newController.depositTimelock(), DEPOSIT_TIMELOCK);
    assertEq(newController.gatewayTxLimit(), 10_000_000e6);
    assertEq(newController.maxInvest(), MAX_INVEST);
    assertEq(newController.maxInvestBps(), MAX_INVEST_BPS);
    assertEq(newController.bufferBps(), BUFFER_BPS);
  }

  function _initProxy(
    address admin_,
    uint256 depositTimelock_,
    uint256 maxInvest_,
    uint256 maxInvestBps_,
    uint256 bufferBps_
  ) internal returns (ReinvestmentController) {
    TransparentUpgradeableProxy newProxy = new TransparentUpgradeableProxy(
      address(implementation),
      proxyAdminOwner,
      abi.encodeCall(
        ReinvestmentController.initialize,
        (admin_, depositTimelock_, maxInvest_, maxInvestBps_, bufferBps_)
      )
    );

    return ReinvestmentController(address(newProxy));
  }
}

contract PauseTest is ReinvestmentControllerTest {
  function test_pause_revertsWith_callerIsNotPauser() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.PAUSER_ROLE()
      )
    );
    controller.pause();
  }

  function test_pause_revertsWith_alreadyPaused() public {
    vm.prank(admin);
    controller.pause();

    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    controller.pause();
  }

  function test_pause_successful() public {
    vm.expectEmit(address(controller));
    emit PausableUpgradeable.Paused(admin);

    vm.prank(admin);
    controller.pause();

    assertTrue(controller.paused());
  }
}

contract UnpauseTest is ReinvestmentControllerTest {
  address public pauser = makeAddr('pauser');

  function test_unpause_revertsWith_withdrawalInProcess() public {
    _invest(INVESTABLE);
    _pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.WithdrawalInProcess.selector);
    controller.unpause();
  }

  function test_unpause_revertsWith_callerIsNotAdmin() public {
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

  function test_unpause_revertsWith_callerIsPauserWithoutAdmin() public {
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

  function test_unpause_revertsWith_notPaused() public {
    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
    controller.unpause();
  }

  function test_unpause_successful() public {
    vm.prank(admin);
    controller.pause();

    vm.expectEmit(address(controller));
    emit PausableUpgradeable.Unpaused(admin);

    vm.prank(admin);
    controller.unpause();

    assertFalse(controller.paused());
  }
}

contract SetDepositTimelockTest is ReinvestmentControllerTest {
  uint256 public constant NEW_DEPOSIT_TIMELOCK = 2 days;

  function test_setDepositTimelock_revertsWith_callerIsNotAdmin() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setDepositTimelock(NEW_DEPOSIT_TIMELOCK);
  }

  function test_setDepositTimelock_revertsWith_timelockIsZero() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setDepositTimelock(0);
  }

  function test_setDepositTimelock_successful() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetDepositTimelock(DEPOSIT_TIMELOCK, NEW_DEPOSIT_TIMELOCK);

    vm.prank(admin);
    controller.setDepositTimelock(NEW_DEPOSIT_TIMELOCK);

    assertEq(controller.depositTimelock(), NEW_DEPOSIT_TIMELOCK);
  }
}

contract SetGatewayTxLimitTest is ReinvestmentControllerTest {
  uint256 public constant DEFAULT_GATEWAY_TX_LIMIT = 10_000_000e6;
  uint256 public constant NEW_GATEWAY_TX_LIMIT = 5_000_000e6;

  function test_setGatewayTxLimit_revertsWith_callerIsNotAdmin() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setGatewayTxLimit(NEW_GATEWAY_TX_LIMIT);
  }

  function test_setGatewayTxLimit_allowsZero() public {
    vm.prank(admin);
    controller.setGatewayTxLimit(0);

    assertEq(controller.gatewayTxLimit(), 0);
  }

  function test_setGatewayTxLimit_successful() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetGatewayTxLimit(DEFAULT_GATEWAY_TX_LIMIT, NEW_GATEWAY_TX_LIMIT);

    vm.prank(admin);
    controller.setGatewayTxLimit(NEW_GATEWAY_TX_LIMIT);

    assertEq(controller.gatewayTxLimit(), NEW_GATEWAY_TX_LIMIT);
  }
}

contract SetBufferBpsTest is ReinvestmentControllerTest {
  uint256 public constant NEW_BUFFER_BPS = 2_000;

  function test_setBufferBps_revertsWith_callerIsNotAdmin() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setBufferBps(NEW_BUFFER_BPS);
  }

  function test_setBufferBps_revertsWith_bufferIsZero() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setBufferBps(0);
  }

  function test_setBufferBps_revertsWith_bufferAtMaxBps() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setBufferBps(10_000);
  }

  function test_setBufferBps_successful() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetBufferBps(BUFFER_BPS, NEW_BUFFER_BPS);

    vm.prank(admin);
    controller.setBufferBps(NEW_BUFFER_BPS);

    assertEq(controller.bufferBps(), NEW_BUFFER_BPS);
  }
}

contract SetMaxInvestTest is ReinvestmentControllerTest {
  uint256 public constant NEW_MAX_INVEST = 50_000_000e6;

  function test_setMaxInvest_revertsWith_callerIsNotAdmin() public {
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

  function test_setMaxInvest_successful() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxInvest(MAX_INVEST, NEW_MAX_INVEST);

    vm.prank(admin);
    controller.setMaxInvest(NEW_MAX_INVEST);

    assertEq(controller.maxInvest(), NEW_MAX_INVEST);
  }
}

contract SetMaxInvestBpsTest is ReinvestmentControllerTest {
  uint256 public constant NEW_MAX_INVEST_BPS = 5_000;

  function test_setMaxInvestBps_revertsWith_callerIsNotAdmin() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.DEFAULT_ADMIN_ROLE()
      )
    );
    controller.setMaxInvestBps(NEW_MAX_INVEST_BPS);
  }

  function test_setMaxInvestBps_revertsWith_bpsIsZero() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setMaxInvestBps(0);
  }

  function test_setMaxInvestBps_revertsWith_bpsAtMaxBps() public {
    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.setMaxInvestBps(10_000);
  }

  function test_setMaxInvestBps_successful() public {
    vm.expectEmit(address(controller));
    emit IReinvestmentController.SetMaxInvestBps(MAX_INVEST_BPS, NEW_MAX_INVEST_BPS);

    vm.prank(admin);
    controller.setMaxInvestBps(NEW_MAX_INVEST_BPS);

    assertEq(controller.maxInvestBps(), NEW_MAX_INVEST_BPS);
  }
}

contract GetInvestableAmountTest is ReinvestmentControllerTest {
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

  function test_getInvestableAmount_successful() public view {
    assertEq(controller.getInvestableAmount(), INVESTABLE);
  }
}
