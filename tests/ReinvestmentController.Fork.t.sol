// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {Test} from 'forge-std/Test.sol';

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {BurnIntentLib} from '@circle-gateway/src/lib/BurnIntentLib.sol';
import {TransferSpec} from '@circle-gateway/src/lib/TransferSpec.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';

import {ReinvestmentController} from '../src/ReinvestmentController.sol';
import {IGatewayWallet} from '../src/interfaces/IGatewayWallet.sol';
import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';
import {GatewayPayloads} from './utils/GatewayPayloads.sol';

interface IAttestationSigners {
  function addAttestationSigner(address signer) external;
}

interface IMintsErrors {
  error InvalidAttestationSigner();
}

interface IBurns {
  function addBurnSigner(address signer) external;

  function gatewayBurn(bytes calldata calldataBytes, bytes calldata signature) external;
}

interface IContractSignersAllowlist {
  function allowlistContractSigner(address contractAddr) external;

  function contractSignersAllowlister() external view returns (address);
}

contract ReinvestmentControllerForkTest is Test, GatewayPayloads {
  uint256 internal constant FORK_BLOCK = 25_796_690;

  // https://etherscan.io/address/0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE
  address public constant GATEWAY_WALLET = 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;

  // https://etherscan.io/address/0x2222222d7164433c4C09B0b0D809a9b52C04C205
  address public constant GATEWAY_MINTER = 0x2222222d7164433c4C09B0b0D809a9b52C04C205;

  // https://etherscan.io/address/0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9
  address public constant HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;

  // https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  uint256 internal constant INVEST_MIN_DELAY = 1 days;
  uint256 internal constant EXPOSURE_CAP_ABS = 10_000_000e6;
  uint256 internal constant EXPOSURE_CAP_BPS = 8_000;
  uint256 internal constant LIQUID_BUFFER_BPS = 1_000;
  uint256 internal constant MAX_FEE = 1e6;
  uint256 internal constant FEE_FUNDING = 1_000e6;

  address internal admin = makeAddr('admin');
  address internal proxyAdminOwner = makeAddr('proxyAdminOwner');
  address internal alice = makeAddr('alice');

  address internal keeper;
  uint256 internal keeperPrivateKey;
  address internal circleSigner;
  uint256 internal circleSignerPrivateKey;
  address internal burnSigner;
  uint256 internal burnSignerPrivateKey;

  ReinvestmentController internal controller;
  uint256 internal assetId;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), FORK_BLOCK);

    (keeper, keeperPrivateKey) = makeAddrAndKey('keeper');
    (circleSigner, circleSignerPrivateKey) = makeAddrAndKey('circleSigner');
    (burnSigner, burnSignerPrivateKey) = makeAddrAndKey('burnSigner');

    controller = ReinvestmentController(
      address(
        new TransparentUpgradeableProxy(
          address(new ReinvestmentController(GATEWAY_WALLET, GATEWAY_MINTER, HUB, USDC)),
          proxyAdminOwner,
          abi.encodeCall(
            IReinvestmentController.initialize,
            (
              admin,
              INVEST_MIN_DELAY,
              EXPOSURE_CAP_ABS,
              EXPOSURE_CAP_BPS,
              MAX_FEE,
              LIQUID_BUFFER_BPS
            )
          )
        )
      )
    );

    deal(USDC, keeper, FEE_FUNDING);
    vm.prank(keeper);
    IERC20(USDC).approve(address(controller), type(uint256).max);

    assetId = controller.ASSET_ID();
    _setPayloadContext(GATEWAY_WALLET, GATEWAY_MINTER, USDC, address(controller));

    bytes32 keeperRole = controller.KEEPER_ROLE();
    vm.prank(admin);
    controller.grantRole(keeperRole, keeper);

    _pointHubAtTheController();
    _allowCircleSigner();
    _allowBurnSigner();
    _allowControllerAsContractSigner();

    vm.warp(block.timestamp + INVEST_MIN_DELAY + 1);
  }

  function test_invest() public {
    uint256 amount = controller.getInvestableAmount();
    uint256 liquidityBefore = IHub(HUB).getAssetLiquidity(assetId);
    uint256 hubBalanceBefore = IERC20(USDC).balanceOf(HUB);

    vm.expectEmit(HUB);
    emit IHub.Sweep(assetId, address(controller), amount);
    vm.expectEmit(address(controller));
    emit IReinvestmentController.Invested(amount);

    vm.prank(keeper);
    controller.invest(amount);

    assertGt(amount, 0);
    assertEq(IHub(HUB).getAssetLiquidity(assetId), liquidityBefore - amount);
    assertEq(IHub(HUB).getAssetSwept(assetId), amount);
    assertEq(controller.getInvestedAmount(), amount);
    assertEq(controller.getInvestableAmount(), 0);
    assertEq(IERC20(USDC).balanceOf(HUB), hubBalanceBefore - amount);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);
    assertEq(IERC20(USDC).allowance(address(controller), GATEWAY_WALLET), 0);
    assertEq(IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)), amount);
    assertEq(IGatewayWallet(GATEWAY_WALLET).withdrawingBalance(USDC, address(controller)), 0);
  }

  function test_invest_revertsWith_ExposureCapExceeded() public {
    uint256 amount = controller.getInvestableAmount() + 1;

    vm.expectRevert(IReinvestmentController.ExposureCapExceeded.selector);
    vm.prank(keeper);
    controller.invest(amount);
  }

  function test_invest_revertsWith_OnlyReinvestmentController() public {
    uint256 amount = controller.getInvestableAmount();
    _pointHubAt(address(0));

    vm.expectRevert(IHub.OnlyReinvestmentController.selector);
    vm.prank(keeper);
    controller.invest(amount);
  }

  function test_divest() public {
    uint256 invested = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(invested);
    uint256 liquidityBefore = IHub(HUB).getAssetLiquidity(assetId);
    uint256 hubBalanceBefore = IERC20(USDC).balanceOf(HUB);

    uint256 amount = invested - MAX_FEE;
    _burn(amount, MAX_FEE);

    (bytes memory attestation, bytes memory signature) = _attest(amount);

    vm.expectEmit(HUB);
    emit IHub.Reclaim(assetId, address(controller), invested);
    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(amount, MAX_FEE);

    vm.prank(keeper);
    controller.divest(amount, attestation, signature);

    assertEq(IHub(HUB).getAssetLiquidity(assetId), liquidityBefore + invested);
    assertEq(IHub(HUB).getAssetSwept(assetId), 0);
    assertEq(controller.getInvestedAmount(), 0);
    assertEq(IERC20(USDC).balanceOf(HUB), hubBalanceBefore + invested);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);
    assertEq(IERC20(USDC).balanceOf(keeper), FEE_FUNDING - MAX_FEE);
    assertEq(IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)), 0);
  }

  /// @dev Circle charges a flat fee equal to MAX_FEE today, so this covers the hypothetical where
  /// it charges less. The Hub is made whole either way; the difference stays in the Gateway
  function test_divest_circleChargesBelowMaxFee() public {
    uint256 invested = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(invested);
    uint256 liquidityBefore = IHub(HUB).getAssetLiquidity(assetId);

    uint256 amount = invested - MAX_FEE;
    uint256 actualFee = 4e5;
    _burn(amount, actualFee);

    (bytes memory attestation, bytes memory signature) = _attest(amount);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(amount, MAX_FEE);

    vm.prank(keeper);
    controller.divest(amount, attestation, signature);

    assertEq(IHub(HUB).getAssetLiquidity(assetId), liquidityBefore + invested);
    assertEq(IHub(HUB).getAssetSwept(assetId), 0);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);
    assertEq(IERC20(USDC).balanceOf(keeper), FEE_FUNDING - MAX_FEE);
    assertEq(
      IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)),
      MAX_FEE - actualFee
    );
  }

  function test_divest_revertsWith_InsufficientLiquidity() public {
    uint256 amount = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(amount);
    (bytes memory attestation, bytes memory signature) = _attest(amount + 1);

    vm.expectRevert(IReinvestmentController.InsufficientLiquidity.selector);
    vm.prank(keeper);
    controller.divest(amount + 1, attestation, signature);
  }

  function test_divest_revertsWith_InvalidAttestationSigner() public {
    uint256 invested = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(invested);

    uint256 amount = invested - MAX_FEE;
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(amount));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      keeperPrivateKey,
      MessageHashUtils.toEthSignedMessageHash(keccak256(attestation))
    );

    vm.expectRevert(IMintsErrors.InvalidAttestationSigner.selector);
    vm.prank(keeper);
    controller.divest(amount, attestation, abi.encodePacked(r, s, v));
  }

  function test_initiateWithdrawal() public {
    uint256 amount = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(amount);

    vm.startPrank(admin);
    controller.pause();

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalInitiated(amount);
    controller.initiateWithdrawal();
    vm.stopPrank();

    assertEq(IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)), 0);
    assertEq(IGatewayWallet(GATEWAY_WALLET).withdrawingBalance(USDC, address(controller)), amount);
    assertEq(
      IGatewayWallet(GATEWAY_WALLET).withdrawalBlock(USDC, address(controller)),
      block.number + IGatewayWallet(GATEWAY_WALLET).withdrawalDelay()
    );
  }

  function test_withdraw() public {
    uint256 amount = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(amount);
    uint256 liquidityBefore = IHub(HUB).getAssetLiquidity(assetId);
    uint256 hubBalanceBefore = IERC20(USDC).balanceOf(HUB);

    vm.startPrank(admin);
    controller.pause();
    controller.initiateWithdrawal();
    vm.stopPrank();

    vm.roll(block.number + IGatewayWallet(GATEWAY_WALLET).withdrawalDelay());

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalCompleted(amount);

    vm.prank(admin);
    controller.withdraw();

    assertEq(IHub(HUB).getAssetLiquidity(assetId), liquidityBefore + amount);
    assertEq(IHub(HUB).getAssetSwept(assetId), 0);
    assertEq(IERC20(USDC).balanceOf(HUB), hubBalanceBefore + amount);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);
    assertEq(IGatewayWallet(GATEWAY_WALLET).withdrawingBalance(USDC, address(controller)), 0);
    assertTrue(controller.paused());
  }

  function test_isValidSignature() public {
    uint256 amount = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(amount);
    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      keeperPrivateKey,
      _encodeBurnIntent(_defaultTransferSpec(amount))
    );

    assertEq(controller.isValidSignature(digest, signature), IERC1271.isValidSignature.selector);
  }

  function test_isValidSignature_revertsWith_HashMismatch() public {
    uint256 amount = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(amount);
    (, bytes memory signature) = _signBurnIntent(
      keeperPrivateKey,
      _encodeBurnIntent(_defaultTransferSpec(amount))
    );

    vm.expectRevert(IReinvestmentController.HashMismatch.selector);
    controller.isValidSignature(keccak256('not the digest'), signature);
  }

  function test_isValidSignature_revertsWith_BurnIntentExceedsBalance() public {
    uint256 amount = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(amount);
    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      keeperPrivateKey,
      _encodeBurnIntent(_defaultTransferSpec(amount + 1))
    );

    vm.expectRevert(IReinvestmentController.BurnIntentExceedsBalance.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_invest_withinInvestableAmount(uint256 amount) public {
    amount = bound(amount, 1, controller.getInvestableAmount());
    uint256 liquidityBefore = IHub(HUB).getAssetLiquidity(assetId);

    vm.prank(keeper);
    controller.invest(amount);

    assertEq(IHub(HUB).getAssetSwept(assetId), amount);
    assertEq(IHub(HUB).getAssetLiquidity(assetId), liquidityBefore - amount);
    assertEq(IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)), amount);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);
  }

  function test_preconditions_gatewayWithdrawalDelayAtForkBlock() public view {
    assertEq(IGatewayWallet(GATEWAY_WALLET).withdrawalDelay(), 50_400);
  }

  function test_preconditions_assetHasNoReinvestmentControllerAtForkBlock() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), FORK_BLOCK);

    uint256 forkAssetId = IHub(HUB).getAssetId(USDC);

    assertEq(IHub(HUB).getAssetConfig(forkAssetId).reinvestmentController, address(0));
    assertEq(IHub(HUB).getAssetSwept(forkAssetId), 0);
  }

  function _attest(
    uint256 amount
  ) internal view returns (bytes memory attestation, bytes memory signature) {
    attestation = _encodeAttestation(_defaultTransferSpec(amount));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      circleSignerPrivateKey,
      MessageHashUtils.toEthSignedMessageHash(keccak256(attestation))
    );
    signature = abi.encodePacked(r, s, v);
  }

  function _signBurnIntent(
    uint256 privateKey,
    bytes memory burnIntentPayload
  ) internal view returns (bytes32 digest, bytes memory signature) {
    digest = MessageHashUtils.toTypedDataHash(
      IGatewayWallet(GATEWAY_WALLET).domainSeparator(),
      BurnIntentLib.getTypedDataHash(burnIntentPayload)
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    signature = abi.encode(abi.encodePacked(r, s, v), burnIntentPayload);
  }

  /// @dev Listing a reinvestment controller is an access-managed governance action, so the
  /// authority is short-circuited for the single configuration call and then restored.
  function _pointHubAtTheController() internal {
    _pointHubAt(address(controller));
  }

  function _pointHubAt(address reinvestmentController) internal {
    IHub.AssetConfig memory config = IHub(HUB).getAssetConfig(assetId);
    config.reinvestmentController = reinvestmentController;

    vm.mockCall(
      IHub(HUB).authority(),
      abi.encodeWithSignature('canCall(address,address,bytes4)'),
      abi.encode(true, uint32(0))
    );
    vm.prank(admin);
    IHub(HUB).updateAssetConfig(assetId, config, '');
    vm.clearMockedCalls();
  }

  function _allowCircleSigner() internal {
    vm.prank(Ownable(GATEWAY_MINTER).owner());
    IAttestationSigners(GATEWAY_MINTER).addAttestationSigner(circleSigner);
  }

  function _allowBurnSigner() internal {
    vm.prank(Ownable(GATEWAY_WALLET).owner());
    IBurns(GATEWAY_WALLET).addBurnSigner(burnSigner);
  }

  /// @dev The depositor is the controller, so the Gateway only takes the ERC-1271 path for its
  /// burn intent signature once the depositor is allowlisted. Otherwise it falls back to ECDSA
  /// recovery and resolves to the wrong signer
  function _allowControllerAsContractSigner() internal {
    vm.prank(IContractSignersAllowlist(GATEWAY_WALLET).contractSignersAllowlister());
    IContractSignersAllowlist(GATEWAY_WALLET).allowlistContractSigner(address(controller));
  }

  /// @dev Reproduces the transaction Circle's operator sends on the source domain. The Gateway
  /// debits `amount + fee`, so passing a fee below MAX_FEE exercises the case where {divest}
  /// pre-pays more than Circle charged, which its flat fee does not do today
  function _burn(uint256 amount, uint256 fee) internal {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(amount), MAX_FEE);
    (, bytes memory signature) = _signBurnIntent(keeperPrivateKey, intent);

    bytes[] memory intents = new bytes[](1);
    intents[0] = intent;

    bytes[] memory signatures = new bytes[](1);
    signatures[0] = signature;

    uint256[][] memory fees = new uint256[][](1);
    fees[0] = new uint256[](1);
    fees[0][0] = fee;

    bytes memory calldataBytes = abi.encode(intents, signatures, fees);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      burnSignerPrivateKey,
      MessageHashUtils.toEthSignedMessageHash(keccak256(calldataBytes))
    );

    IBurns(GATEWAY_WALLET).gatewayBurn(calldataBytes, abi.encodePacked(r, s, v));
  }
}
