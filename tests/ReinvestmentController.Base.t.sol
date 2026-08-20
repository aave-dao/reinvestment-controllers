// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from 'forge-std/Test.sol';
import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import {ReinvestmentController, IReinvestmentController} from '../src/ReinvestmentController.sol';
import {MockERC20} from './mocks/MockERC20.sol';
import {MockGatewayMinter} from './mocks/MockGatewayMinter.sol';
import {MockGatewayWallet} from './mocks/MockGatewayWallet.sol';
import {MockHub} from './mocks/MockHub.sol';

contract ReinvestmentControllerTestBase is Test {
  uint256 public constant ASSET_ID = 1;

  uint256 public constant DEPOSIT_TIMELOCK = 1 days;
  uint256 public constant MAX_INVEST = 100_000_000e6;
  uint256 public constant MAX_INVEST_BPS = 80_00; // 80%
  uint256 public constant BUFFER_BPS = 10_00; // 10%

  /// @dev Starting Hub state: everything supplied is idle, nothing swept yet
  uint256 public constant SUPPLIED = 1_000_000e6;

  /// @dev What `getInvestableAmount()` returns from the default state
  uint256 public constant INVESTABLE = 800_000e6; // 80% of liquidity

  ReinvestmentController public controller;
  ReinvestmentController public implementation;
  TransparentUpgradeableProxy public proxy;

  MockERC20 public usdc;
  MockGatewayWallet public gatewayWallet;
  MockGatewayMinter public gatewayMinter;
  MockHub public hub;

  address public admin = makeAddr('admin');
  address public proxyAdminOwner = makeAddr('proxyAdminOwner');

  function setUp() public virtual {
    usdc = new MockERC20('USD Coin', 'USDC', 6);
    gatewayWallet = new MockGatewayWallet();
    gatewayMinter = new MockGatewayMinter();
    hub = new MockHub();

    hub.listAsset(address(usdc), ASSET_ID);

    implementation = new ReinvestmentController(
      address(gatewayWallet),
      address(gatewayMinter),
      address(hub),
      address(usdc)
    );

    proxy = new TransparentUpgradeableProxy(
      address(implementation),
      proxyAdminOwner,
      abi.encodeCall(
        ReinvestmentController.initialize,
        (admin, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS)
      )
    );

    controller = ReinvestmentController(address(proxy));

    _fundHub(SUPPLIED);

    // _depositLastUpdate starts at 0, so the first invest stays gated until the
    // timelock has elapsed against the block clock
    vm.warp(DEPOSIT_TIMELOCK + 1);
  }

  function _fundHub(uint256 amount) internal {
    usdc.mint(address(hub), amount);
    hub.setAddedAssets(ASSET_ID, amount);
    hub.setLiquidity(ASSET_ID, amount);
  }

  function _invest(uint256 amount) internal {
    vm.prank(admin);
    controller.invest(amount);

    gatewayMinter.setNextMint(address(usdc), amount);
  }

  function _pause() internal {
    vm.prank(admin);
    controller.pause();
  }
}
