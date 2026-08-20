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

contract ReinvestmentControllerConstructorTest is Test {
  uint256 public constant ASSET_ID = 1;

  function test_constructor_revertsWith_InvalidZeroAddress_gatewayWallet() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayMinter gatewayMinter = new MockGatewayMinter();
    MockHub hub = new MockHub();

    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(0), address(gatewayMinter), address(hub), address(usdc));
  }

  function test_constructor_revertsWith_InvalidZeroAddress_gatewayMinter() public {
    MockERC20 usdc = new MockERC20('USD Coin', 'USDC', 6);
    MockGatewayWallet gatewayWallet = new MockGatewayWallet();
    MockHub hub = new MockHub();

    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(gatewayWallet), address(0), address(hub), address(usdc));
  }

  function test_constructor_revertsWith_InvalidZeroAddress_hub() public {
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

  function test_constructor_revertsWith_InvalidZeroAddress_usdc() public {
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

  function test_constructor_revertsWith_AssetNotListed() public {
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

  function test_constructor_revertsWith_InvalidInitialization_implementationIsLocked() public {
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

  function test_constructor() public {
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

contract ReinvestmentControllerInitializeTest is ReinvestmentControllerTestBase {
  function test_initialize_revertsWith_InvalidInitialization() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    controller.initialize(admin, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidZeroAddress() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    _initProxy(address(0), DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_depositTimelockIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, 0, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_maxInvestBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, 0, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_maxInvestBpsAtMax() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, 10_000, BUFFER_BPS);
  }

  function test_initialize_revertsWith_InvalidAmount_bufferBpsIsZero() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, 0);
  }

  function test_initialize_revertsWith_InvalidAmount_bufferBpsAtMax() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    _initProxy(admin, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, 10_000);
  }

  function test_initialize() public {
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
