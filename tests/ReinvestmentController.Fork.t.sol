// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';

import {IGatewayWallet} from '../src/interfaces/IGatewayWallet.sol';
import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {
  IContractSignatureSigners,
  IContractSignersAllowlist,
  IMintsErrors,
  ReinvestmentControllerForkBase
} from './ReinvestmentController.ForkBase.t.sol';

contract ReinvestmentControllerForkTest is ReinvestmentControllerForkBase {
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
    Authorization memory auth = _authorize(amount, 'a');

    vm.expectEmit(HUB);
    emit IHub.Reclaim(assetId, address(controller), invested);
    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(amount, MAX_FEE);

    vm.prank(keeper);
    controller.divest(amount, auth.attestation, auth.attestationSignature);

    _teeBurn(auth, MAX_FEE);

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
    Authorization memory auth = _authorize(amount, 'a');

    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(amount, MAX_FEE);

    vm.prank(keeper);
    controller.divest(amount, auth.attestation, auth.attestationSignature);

    _teeBurn(auth, actualFee);

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

  function test_preconditions_burnsRelyOnTeeSignerNotContractAllowlist() public view {
    assertFalse(
      IContractSignersAllowlist(GATEWAY_WALLET).isAllowlistedContractSigner(address(controller))
    );
    assertTrue(IContractSignatureSigners(GATEWAY_WALLET).isContractSignatureSigner(teeSigner));
  }
}
