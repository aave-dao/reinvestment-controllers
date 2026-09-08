// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';

import {ReinvestmentController} from '../src/ReinvestmentController.sol';
import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {MockHub} from './mocks/MockHub.sol';
import {MockUSDC} from './mocks/MockUSDC.sol';
import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerConstructorTest is ReinvestmentControllerTestBase {
  function test_constructor() public view {
    assertEq(address(implementation.GATEWAY_WALLET()), address(wallet));
    assertEq(address(implementation.GATEWAY_MINTER()), address(minter));
    assertEq(address(implementation.HUB()), address(hub));
    assertEq(address(implementation.USDC()), address(usdc));
    assertEq(implementation.ASSET_ID(), hub.USDC_ASSET_ID());
  }

  function test_constructor_definesDistinctRoleIdentifiers() public view {
    assertEq(implementation.KEEPER_ROLE(), keccak256('KEEPER_ROLE'));
    assertEq(implementation.PAUSER_ROLE(), keccak256('PAUSER_ROLE'));
    assertTrue(implementation.KEEPER_ROLE() != implementation.PAUSER_ROLE());
    assertTrue(implementation.KEEPER_ROLE() != implementation.DEFAULT_ADMIN_ROLE());
  }

  function test_constructor_leavesImplementationUnconfigured() public view {
    assertEq(implementation.getInvestMinDelay(), 0);
    assertEq(implementation.getLastInvestTimestamp(), 0);
    assertEq(implementation.getExposureCapAbs(), 0);
    assertEq(implementation.getExposureCapBps(), 0);
    assertEq(implementation.getLiquidBufferBps(), 0);
    assertFalse(implementation.hasRole(implementation.DEFAULT_ADMIN_ROLE(), admin));
  }

  function test_constructor_resolvesAssetIdFromHub() public {
    MockUSDC otherToken = new MockUSDC();
    MockHub otherHub = new MockHub(address(otherToken));

    ReinvestmentController other = new ReinvestmentController(
      address(wallet),
      address(minter),
      address(otherHub),
      address(otherToken)
    );

    assertEq(other.ASSET_ID(), otherHub.USDC_ASSET_ID());
  }

  function test_constructor_revertsWith_InvalidInitialization_onTheImplementation() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    implementation.initialize(
      admin,
      INVEST_MIN_DELAY,
      EXPOSURE_CAP_ABS,
      EXPOSURE_CAP_BPS,
      MAX_FEE,
      LIQUID_BUFFER_BPS
    );
  }

  function test_constructor_revertsWith_InvalidZeroAddress_gatewayWallet() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(0), address(minter), address(hub), address(usdc));
  }

  function test_constructor_revertsWith_InvalidZeroAddress_gatewayMinter() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(wallet), address(0), address(hub), address(usdc));
  }

  function test_constructor_revertsWith_InvalidZeroAddress_hub() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(wallet), address(minter), address(0), address(usdc));
  }

  function test_constructor_revertsWith_InvalidZeroAddress_usdc() public {
    vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
    new ReinvestmentController(address(wallet), address(minter), address(hub), address(0));
  }

  function test_constructor_revertsWith_AssetNotListed_underlyingUnknownToHub() public {
    address unlisted = makeAddr('unlisted');

    vm.expectRevert(MockHub.AssetNotListed.selector);
    new ReinvestmentController(address(wallet), address(minter), address(hub), unlisted);
  }
}
