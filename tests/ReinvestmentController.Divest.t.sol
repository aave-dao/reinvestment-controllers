// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {TransferSpec} from '@circle-gateway/src/lib/TransferSpec.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {MockHub} from './mocks/MockHub.sol';
import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerDivestTest is ReinvestmentControllerTestBase {
  uint256 internal constant INVESTED = 400_000e6;

  function setUp() public override {
    super.setUp();

    _invest(INVESTED);
  }

  function test_divest() public {
    uint256 amount = INVESTED / 2;
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(amount));
    bytes memory signature = hex'1234';

    vm.expectEmit(address(hub));
    emit MockHub.Reclaim(assetId, address(controller), amount);
    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(amount);

    vm.prank(investor);
    controller.divest(amount, attestation, signature);

    assertEq(hub.getAssetSwept(assetId), INVESTED - amount);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTED + amount);
    assertEq(usdc.balanceOf(address(hub)), SUPPLIED - INVESTED + amount);
    assertEq(usdc.balanceOf(address(controller)), 0);
    assertEq(usdc.balanceOf(address(wallet)), INVESTED - amount);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), INVESTED - amount);
    assertEq(controller.getInvestedAmount(), INVESTED - amount);
  }

  function test_divest(uint256 amount) public {
    amount = bound(amount, 1, INVESTED);

    vm.prank(investor);
    controller.divest(amount, _encodeAttestation(_defaultTransferSpec(amount)), hex'1234');

    assertEq(controller.getInvestedAmount(), INVESTED - amount);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED - INVESTED + amount);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }

  function test_divest_fullSweptBalance() public {
    vm.prank(investor);
    controller.divest(INVESTED, _encodeAttestation(_defaultTransferSpec(INVESTED)), hex'1234');

    assertEq(controller.getInvestedAmount(), 0);
    assertEq(hub.getAssetLiquidity(assetId), SUPPLIED);
    assertEq(usdc.balanceOf(address(hub)), SUPPLIED);
    assertEq(wallet.availableBalance(address(usdc), address(controller)), 0);
  }

  function test_divest_byAdmin() public {
    vm.prank(admin);
    controller.divest(1_000e6, _encodeAttestation(_defaultTransferSpec(1_000e6)), hex'1234');

    assertEq(controller.getInvestedAmount(), INVESTED - 1_000e6);
  }

  function test_divest_restoresInvestableHeadroom() public {
    uint256 investableBefore = controller.getInvestableAmount();

    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(_defaultTransferSpec(1_000e6)), hex'1234');

    assertEq(controller.getInvestableAmount(), investableBefore + 1_000e6);
  }

  function test_divest_isNotSubjectToDepositTimelock() public {
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(_defaultTransferSpec(1_000e6)), hex'1234');

    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(_defaultTransferSpec(1_000e6)), hex'1234');

    assertEq(controller.getInvestedAmount(), INVESTED - 2_000e6);
  }

  function test_divest_forwardsPayloadAndSignatureToMinter() public {
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(1_000e6));
    bytes memory signature = hex'deadbeef';

    vm.expectCall(address(minter), abi.encodeCall(minter.gatewayMint, (attestation, signature)));

    vm.prank(investor);
    controller.divest(1_000e6, attestation, signature);
  }

  function test_divest_revertsWith_AccessControlUnauthorizedAccount() public {
    bytes32 investorRole = controller.INVESTOR_ROLE();

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        alice,
        investorRole
      )
    );
    vm.prank(alice);
    controller.divest(1_000e6, _encodeAttestation(_defaultTransferSpec(1_000e6)), hex'1234');
  }

  function test_divest_revertsWith_EnforcedPause() public {
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(1_000e6));

    vm.prank(pauser);
    controller.pause();

    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    vm.prank(investor);
    controller.divest(1_000e6, attestation, hex'1234');
  }

  function test_divest_revertsWith_InvalidAmount() public {
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    vm.prank(investor);
    controller.divest(0, _encodeAttestation(_defaultTransferSpec(0)), hex'1234');
  }

  function test_divest_revertsWith_InsufficientLiquidity_aboveSweptBalance() public {
    bytes memory attestation = _encodeAttestation(_defaultTransferSpec(INVESTED + 1));

    vm.expectRevert(IReinvestmentController.InsufficientLiquidity.selector);
    vm.prank(investor);
    controller.divest(INVESTED + 1, attestation, hex'1234');
  }

  function test_divest_revertsWith_InsufficientLiquidity_beforeAttestationChecks() public {
    TransferSpec memory spec = _defaultTransferSpec(INVESTED + 1);
    spec.sourceToken = _toBytes32(makeAddr('otherToken'));

    vm.expectRevert(IReinvestmentController.InsufficientLiquidity.selector);
    vm.prank(investor);
    controller.divest(INVESTED + 1, _encodeAttestation(spec), hex'1234');
  }

  function test_divest_revertsWith_InvalidElementCount_attestationSetWithTwoElements() public {
    TransferSpec[] memory specs = new TransferSpec[](2);
    specs[0] = _defaultTransferSpec(1_000e6);
    specs[1] = _defaultTransferSpec(1_000e6);

    vm.expectRevert(IReinvestmentController.InvalidElementCount.selector);
    vm.prank(investor);
    controller.divest(2_000e6, _encodeAttestationSet(specs), hex'1234');
  }

  function test_divest_revertsWith_InvalidElementCount_emptyAttestationSet() public {
    vm.expectRevert(IReinvestmentController.InvalidElementCount.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestationSet(new TransferSpec[](0)), hex'1234');
  }

  function test_divest_revertsWith_InvalidMintAmount_attestationValueBelowAmount() public {
    vm.expectRevert(IReinvestmentController.InvalidMintAmount.selector);
    vm.prank(investor);
    controller.divest(2_000e6, _encodeAttestation(_defaultTransferSpec(1_000e6)), hex'1234');
  }

  function test_divest_revertsWith_InvalidMintAmount_attestationValueAboveAmount() public {
    vm.expectRevert(IReinvestmentController.InvalidMintAmount.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(_defaultTransferSpec(2_000e6)), hex'1234');
  }

  function test_divest_revertsWith_CrossChainTransferNotAllowed() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationDomain = 1;

    vm.expectRevert(IReinvestmentController.CrossChainTransferNotAllowed.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(spec), hex'1234');
  }

  function test_divest_revertsWith_InvalidSourceToken() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.sourceToken = _toBytes32(makeAddr('otherToken'));

    vm.expectRevert(IReinvestmentController.InvalidSourceToken.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(spec), hex'1234');
  }

  function test_divest_revertsWith_InvalidDestinationToken() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationToken = _toBytes32(makeAddr('otherToken'));

    vm.expectRevert(IReinvestmentController.InvalidDestinationToken.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(spec), hex'1234');
  }

  function test_divest_revertsWith_InvalidDepositor() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.sourceDepositor = _toBytes32(alice);

    vm.expectRevert(IReinvestmentController.InvalidDepositor.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(spec), hex'1234');
  }

  function test_divest_revertsWith_InvalidRecipient() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationRecipient = _toBytes32(alice);

    vm.expectRevert(IReinvestmentController.InvalidRecipient.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(spec), hex'1234');
  }

  function test_divest_revertsWith_InvalidSigner() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.sourceSigner = _toBytes32(investor);

    vm.expectRevert(IReinvestmentController.InvalidSigner.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(spec), hex'1234');
  }

  function test_divest_revertsWith_InvalidDestinationCaller() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationCaller = bytes32(0);

    vm.expectRevert(IReinvestmentController.InvalidDestinationCaller.selector);
    vm.prank(investor);
    controller.divest(1_000e6, _encodeAttestation(spec), hex'1234');
  }
}
