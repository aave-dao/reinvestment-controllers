// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';

import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';

import {AddressLib} from '@circle-gateway/src/lib/AddressLib.sol';
import {AttestationLib} from '@circle-gateway/src/lib/AttestationLib.sol';
import {Attestation} from '@circle-gateway/src/lib/Attestations.sol';
import {TransferSpec, TRANSFER_SPEC_VERSION} from '@circle-gateway/src/lib/TransferSpec.sol';

import {IGatewayMinter} from '../src/interfaces/IGatewayMinter.sol';
import {IGatewayWallet} from '../src/interfaces/IGatewayWallet.sol';
import {ReinvestmentController, IReinvestmentController} from '../src/ReinvestmentController.sol';

contract ReinvestmentControllerForkTestBase is Test {
  // https://etherscan.io/address/0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE
  address public constant GATEWAY_WALLET = 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;

  // https://etherscan.io/address/0x2222222d7164433c4C09B0b0D809a9b52C04C205
  address public constant GATEWAY_MINTER = 0x2222222d7164433c4C09B0b0D809a9b52C04C205;

  // https://etherscan.io/address/0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9
  address public constant HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;

  // https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  // https://etherscan.io/address/0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A
  address public constant EXECUTOR_LVL_1 = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A; // governance

  // https://etherscan.io/address/0x1F0753480bB03EaA00863224602267B7E0525C3d
  address public constant HUB_CONFIGURATOR = 0x1F0753480bB03EaA00863224602267B7E0525C3d; // Holds the Hub's asset config role

  uint256 public constant DEPOSIT_TIMELOCK = 1 days;
  uint256 public constant MAX_INVEST = 100_000_000e6;
  uint256 public constant MAX_INVEST_BPS = 80_00; // 80%
  uint256 public constant BUFFER_BPS = 10_00; // 10%

  uint256 public constant GATEWAY_WITHDRAWAL_DELAY = 50_400;

  ReinvestmentController public controller;
  ReinvestmentController public implementation;
  TransparentUpgradeableProxy public proxy;

  uint256 public assetId;

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 25726000);

    assetId = IHub(HUB).getAssetId(USDC);

    implementation = new ReinvestmentController(GATEWAY_WALLET, GATEWAY_MINTER, HUB, USDC);

    proxy = new TransparentUpgradeableProxy(
      address(implementation),
      EXECUTOR_LVL_1,
      abi.encodeCall(
        ReinvestmentController.initialize,
        (EXECUTOR_LVL_1, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS)
      )
    );

    controller = ReinvestmentController(address(proxy));
  }

  function _setReinvestmentController() internal {
    IHub.AssetConfig memory config = IHub(HUB).getAssetConfig(assetId);
    config.reinvestmentController = address(controller);

    vm.prank(HUB_CONFIGURATOR);
    IHub(HUB).updateAssetConfig(assetId, config, '');
  }

  function _invest(uint256 amount) internal {
    vm.prank(EXECUTOR_LVL_1);
    controller.invest(amount);
  }
}

contract ReinvestmentControllerForkInvestTest is ReinvestmentControllerForkTestBase {
  /// @notice Thrown when an invalid reinvestment controller attempts to perform a `sweep` action.
  error OnlyReinvestmentController();

  function test_invest_revertsWith_AccessControlUnauthorizedAccount() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.INVESTOR_ROLE()
      )
    );
    controller.invest(100_000e6);
  }

  function test_invest_revertsWith_OnlyReinvestmentController() public {
    vm.expectRevert(OnlyReinvestmentController.selector);
    _invest(100_000e6);
  }

  function test_invest_revertsWith_MaximumInvestAmountExceeded() public {
    _setReinvestmentController();

    uint256 amount = controller.getInvestableAmount() + 1;

    vm.expectRevert(IReinvestmentController.MaximumInvestAmountExceeded.selector);
    _invest(amount);
  }

  function test_invest_atFullInvestableAmount() public {
    _setReinvestmentController();

    uint256 investable = controller.getInvestableAmount();

    _invest(investable);

    assertEq(controller.getInvestedAmount(), investable);
    assertEq(controller.getInvestableAmount(), 0);
  }

  function test_invest_preservesLiquidityBuffer() public {
    _setReinvestmentController();

    uint256 supplied = IHub(HUB).getAddedAssets(assetId);

    _invest(controller.getInvestableAmount());

    assertGe(IHub(HUB).getAssetLiquidity(assetId), (supplied * BUFFER_BPS) / 100_00);
  }

  function test_invest_accumulatesAcrossDeposits() public {
    _setReinvestmentController();

    uint256 amount = controller.getInvestableAmount() / 4;

    _invest(amount);

    vm.warp(block.timestamp + DEPOSIT_TIMELOCK + 1);

    _invest(amount);

    assertEq(controller.getInvestedAmount(), amount * 2);
    assertEq(
      IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)),
      amount * 2
    );
  }

  function test_invest(uint256 amount) public {
    _setReinvestmentController();

    uint256 availableLiquidity = IHub(HUB).getAssetLiquidity(assetId);
    uint256 suppliedBefore = IHub(HUB).getAddedAssets(assetId);
    uint256 investableBefore = controller.getInvestableAmount();
    uint256 hubBalanceBefore = IERC20(USDC).balanceOf(HUB);
    uint256 walletBalanceBefore = IERC20(USDC).balanceOf(GATEWAY_WALLET);

    amount = bound(amount, 1_000e6, investableBefore);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.Invested(amount);

    _invest(amount);

    assertEq(IERC20(USDC).balanceOf(GATEWAY_WALLET), walletBalanceBefore + amount);
    assertEq(IERC20(USDC).balanceOf(HUB), hubBalanceBefore - amount);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);

    assertEq(controller.getInvestedAmount(), amount);
    assertEq(IHub(HUB).getAssetLiquidity(assetId), availableLiquidity - amount);
    assertEq(IHub(HUB).getAddedAssets(assetId), suppliedBefore);

    assertEq(IERC20(USDC).allowance(address(controller), GATEWAY_WALLET), 0);
    assertEq(controller.getInvestableAmount(), investableBefore - amount);
    assertEq(IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)), amount);
  }
}

contract ReinvestmentControllerForkWithdrawalTest is ReinvestmentControllerForkTestBase {
  /// @notice Thrown by the Gateway wallet when `withdraw` runs before the delay elapses.
  error WithdrawalNotYetAvailable();

  function test_initiateWithdrawal() public {
    _setReinvestmentController();

    uint256 amount = controller.getInvestableAmount() / 4;
    _invest(amount);

    _pause();

    uint256 walletBalanceBefore = IERC20(USDC).balanceOf(GATEWAY_WALLET);
    uint256 expectedWithdrawalBlock = block.number + GATEWAY_WITHDRAWAL_DELAY;

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalInitiated(amount);

    _initiateWithdrawal();

    assertEq(_withdrawalBlock(), expectedWithdrawalBlock);

    assertEq(_availableBalance(), 0);
    assertEq(_withdrawingBalance(), amount);

    assertEq(IERC20(USDC).balanceOf(GATEWAY_WALLET), walletBalanceBefore);
    assertEq(controller.getInvestedAmount(), amount);
  }

  function test_withdraw_revertsWith_WithdrawalNotYetAvailable() public {
    _setReinvestmentController();

    uint256 amount = controller.getInvestableAmount() / 4;
    _invest(amount);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock() - 1);

    vm.expectRevert(WithdrawalNotYetAvailable.selector);
    _withdraw();
  }

  function test_withdraw_atExactWithdrawalBlock() public {
    _setReinvestmentController();

    uint256 amount = controller.getInvestableAmount() / 4;
    _invest(amount);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock());

    _withdraw();
  }

  function test_withdraw() public {
    _setReinvestmentController();

    uint256 availableLiquidity = IHub(HUB).getAssetLiquidity(assetId);
    uint256 hubBalanceBefore = IERC20(USDC).balanceOf(HUB);
    uint256 walletBalanceBefore = IERC20(USDC).balanceOf(GATEWAY_WALLET);

    uint256 amount = controller.getInvestableAmount() / 4;
    _invest(amount);
    _pause();
    _initiateWithdrawal();

    vm.roll(_withdrawalBlock() + 1);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.WithdrawalCompleted(amount);

    _withdraw();

    assertEq(controller.getInvestedAmount(), 0);

    assertEq(IERC20(USDC).balanceOf(HUB), hubBalanceBefore);
    assertEq(IERC20(USDC).balanceOf(GATEWAY_WALLET), walletBalanceBefore);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);

    assertEq(IHub(HUB).getAssetLiquidity(assetId), availableLiquidity);

    assertEq(_availableBalance(), 0);
    assertEq(_withdrawingBalance(), 0);
    assertEq(_withdrawalBlock(), 0);
  }

  function _pause() internal {
    vm.prank(EXECUTOR_LVL_1);
    controller.pause();
  }

  function _initiateWithdrawal() internal {
    vm.prank(EXECUTOR_LVL_1);
    controller.initiateWithdrawal();
  }

  function _withdraw() internal {
    vm.prank(EXECUTOR_LVL_1);
    controller.withdraw();
  }

  function _withdrawalBlock() internal view returns (uint256) {
    return IGatewayWallet(GATEWAY_WALLET).withdrawalBlock(USDC, address(controller));
  }

  function _availableBalance() internal view returns (uint256) {
    return IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller));
  }

  function _withdrawingBalance() internal view returns (uint256) {
    return IGatewayWallet(GATEWAY_WALLET).withdrawingBalance(USDC, address(controller));
  }
}

interface IGatewayMinterAdmin {
  function addAttestationSigner(address signer) external;
}

contract ReinvestmentControllerForkDivestTest is ReinvestmentControllerForkTestBase {
  /// @notice Thrown by the Gateway minter when the attestation signer is not authorized.
  error InvalidAttestationSigner();

  uint256 public constant ATTESTATION_KEY = 0xA77E57;

  // https://etherscan.io/address/0x3c54FFa14d01EF3A555106007A4fED6E8964aAB6
  address public constant MINTER_OWNER = 0x3c54FFa14d01EF3A555106007A4fED6E8964aAB6;

  function test_divest_revertsWith_InvalidAttestationSigner() public {
    _setReinvestmentController();

    uint256 amount = controller.getInvestableAmount() / 4;
    _invest(amount);

    bytes memory payload = _attestation(amount);
    bytes memory signature = _attestationSignature(payload);

    vm.expectRevert(InvalidAttestationSigner.selector);
    _divest(amount, payload, signature);
  }

  function test_divest_revertsWith_InvalidMintAmount() public {
    _setReinvestmentController();
    _authorizeAttestationSigner();

    uint256 amount = controller.getInvestableAmount() / 4;
    _invest(amount);

    bytes memory payload = _attestation(amount - 1);
    bytes memory signature = _attestationSignature(payload);

    vm.expectRevert(IReinvestmentController.InvalidMintAmount.selector);
    _divest(amount, payload, signature);
  }

  function test_divest() public {
    _setReinvestmentController();
    _authorizeAttestationSigner();

    uint256 hubBalanceBefore = IERC20(USDC).balanceOf(HUB);

    uint256 amount = controller.getInvestableAmount() / 4;
    _invest(amount);

    uint256 supplyBefore = IERC20(USDC).totalSupply();

    bytes memory payload = _attestation(amount);
    bytes memory signature = _attestationSignature(payload);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(amount);

    _divest(amount, payload, signature);

    assertEq(controller.getInvestedAmount(), 0);
    assertEq(IERC20(USDC).balanceOf(HUB), hubBalanceBefore);
    assertEq(IERC20(USDC).balanceOf(address(controller)), 0);
    assertEq(IERC20(USDC).totalSupply(), supplyBefore + amount);
  }

  function _authorizeAttestationSigner() internal {
    vm.prank(MINTER_OWNER);
    IGatewayMinterAdmin(GATEWAY_MINTER).addAttestationSigner(vm.addr(ATTESTATION_KEY));
  }

  function _divest(uint256 amount, bytes memory payload, bytes memory signature) internal {
    vm.prank(EXECUTOR_LVL_1);
    controller.divest(amount, payload, signature);
  }

  function _attestation(uint256 value) internal view returns (bytes memory) {
    bytes32 self = AddressLib._addressToBytes32(address(controller));

    TransferSpec memory spec = TransferSpec({
      version: TRANSFER_SPEC_VERSION,
      sourceDomain: 0,
      destinationDomain: 0,
      sourceContract: AddressLib._addressToBytes32(GATEWAY_WALLET),
      destinationContract: AddressLib._addressToBytes32(GATEWAY_MINTER),
      sourceToken: AddressLib._addressToBytes32(USDC),
      destinationToken: AddressLib._addressToBytes32(USDC),
      sourceDepositor: self,
      destinationRecipient: self,
      sourceSigner: self,
      destinationCaller: self,
      value: value,
      salt: bytes32(block.number),
      hookData: ''
    });

    return
      AttestationLib.encodeAttestation(Attestation({maxBlockHeight: block.number + 1, spec: spec}));
  }

  function _attestationSignature(bytes memory payload) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      ATTESTATION_KEY,
      MessageHashUtils.toEthSignedMessageHash(keccak256(payload))
    );

    return abi.encodePacked(r, s, v);
  }
}

contract ReinvestmentControllerForkPreconditionsTest is ReinvestmentControllerForkTestBase {
  function test_preconditions_assetHasNoReinvestmentController() public view {
    assertEq(IHub(HUB).getAssetConfig(assetId).reinvestmentController, address(0));
    assertEq(IHub(HUB).getAssetSwept(assetId), 0);
  }

  function test_preconditions_gatewayWithdrawalDelayMatchesMock() public view {
    assertEq(IGatewayWallet(GATEWAY_WALLET).withdrawalDelay(), GATEWAY_WITHDRAWAL_DELAY);
  }
}
