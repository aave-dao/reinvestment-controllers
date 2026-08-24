// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {TransferSpec} from '@circle-gateway/src/lib/TransferSpec.sol';

import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerIsValidSignatureTest is ReinvestmentControllerTestBase {
  uint256 internal constant INVESTED = 400_000e6;

  function setUp() public override {
    super.setUp();

    _invest(INVESTED);
  }

  function test_isValidSignature() public view {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(INVESTED / 2));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    assertEq(controller.isValidSignature(digest, signature), IERC1271.isValidSignature.selector);
  }

  function test_isValidSignature(uint256 value) public view {
    value = bound(value, 0, INVESTED);
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(value));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    assertEq(controller.isValidSignature(digest, signature), IERC1271.isValidSignature.selector);
  }

  function test_isValidSignature_atFullSweptBalance() public view {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(INVESTED));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    assertEq(controller.isValidSignature(digest, signature), IERC1271.isValidSignature.selector);
  }

  function test_isValidSignature_signedByAdmin() public view {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(adminPrivateKey, intent);

    assertEq(controller.isValidSignature(digest, signature), IERC1271.isValidSignature.selector);
  }

  function test_isValidSignature_afterUnpause() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    vm.prank(pauser);
    controller.pause();

    vm.prank(admin);
    controller.unpause();

    assertEq(controller.isValidSignature(digest, signature), IERC1271.isValidSignature.selector);
  }

  function test_isValidSignature_revertsWith_EnforcedPause() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    vm.prank(pauser);
    controller.pause();

    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_HashMismatch() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    vm.expectRevert(IReinvestmentController.HashMismatch.selector);
    controller.isValidSignature(keccak256('not the digest'), signature);
  }

  function test_isValidSignature_revertsWith_HashMismatch_digestOfADifferentBurnIntent() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    bytes memory otherIntent = _encodeBurnIntent(_defaultTransferSpec(2_000e6));
    (bytes32 otherDigest, ) = _signBurnIntent(investorPrivateKey, otherIntent);

    vm.expectRevert(IReinvestmentController.HashMismatch.selector);
    controller.isValidSignature(otherDigest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidSignature_signerLacksInvestorRole() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(alicePrivateKey, intent);

    vm.expectRevert(IReinvestmentController.InvalidSignature.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidSignature_afterInvestorRoleIsRevoked() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    bytes32 investorRole = controller.INVESTOR_ROLE();

    vm.prank(admin);
    controller.revokeRole(investorRole, investor);

    vm.expectRevert(IReinvestmentController.InvalidSignature.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidSignature_signedOverAnotherDigest() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (bytes32 digest, ) = _signBurnIntent(investorPrivateKey, intent);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(investorPrivateKey, keccak256('another digest'));
    bytes memory signature = abi.encode(abi.encodePacked(r, s, v), intent);

    vm.expectRevert(IReinvestmentController.InvalidSignature.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_ECDSAInvalidSignatureLength() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1_000e6));
    (bytes32 digest, ) = _signBurnIntent(investorPrivateKey, intent);
    bytes memory signature = abi.encode(hex'1234', intent);

    vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 2));
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidElementCount_burnIntentSetWithTwoElements()
    public
  {
    TransferSpec[] memory specs = new TransferSpec[](2);
    specs[0] = _defaultTransferSpec(1_000e6);
    specs[1] = _defaultTransferSpec(1_000e6);

    bytes memory intent = _encodeBurnIntentSet(specs);
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    vm.expectRevert(IReinvestmentController.InvalidElementCount.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidElementCount_emptyBurnIntentSet() public {
    bytes memory intent = _encodeBurnIntentSet(new TransferSpec[](0));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    vm.expectRevert(IReinvestmentController.InvalidElementCount.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_BurnIntentExceedsBalance_aboveSwept() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(INVESTED + 1));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    vm.expectRevert(IReinvestmentController.BurnIntentExceedsBalance.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_BurnIntentExceedsBalance_nothingInvested() public {
    bytes memory intent = _encodeBurnIntent(_defaultTransferSpec(1));
    (bytes32 digest, bytes memory signature) = _signBurnIntent(investorPrivateKey, intent);

    hub.setAccounting(SUPPLIED, SUPPLIED, 0);

    vm.expectRevert(IReinvestmentController.BurnIntentExceedsBalance.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_CrossChainTransferNotAllowed() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationDomain = 1;

    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      investorPrivateKey,
      _encodeBurnIntent(spec)
    );

    vm.expectRevert(IReinvestmentController.CrossChainTransferNotAllowed.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidSourceToken() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.sourceToken = _toBytes32(makeAddr('otherToken'));

    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      investorPrivateKey,
      _encodeBurnIntent(spec)
    );

    vm.expectRevert(IReinvestmentController.InvalidSourceToken.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidDestinationToken() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationToken = _toBytes32(makeAddr('otherToken'));

    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      investorPrivateKey,
      _encodeBurnIntent(spec)
    );

    vm.expectRevert(IReinvestmentController.InvalidDestinationToken.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidDepositor() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.sourceDepositor = _toBytes32(alice);

    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      investorPrivateKey,
      _encodeBurnIntent(spec)
    );

    vm.expectRevert(IReinvestmentController.InvalidDepositor.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidRecipient() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationRecipient = _toBytes32(alice);

    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      investorPrivateKey,
      _encodeBurnIntent(spec)
    );

    vm.expectRevert(IReinvestmentController.InvalidRecipient.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidSigner() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.sourceSigner = _toBytes32(investor);

    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      investorPrivateKey,
      _encodeBurnIntent(spec)
    );

    vm.expectRevert(IReinvestmentController.InvalidSigner.selector);
    controller.isValidSignature(digest, signature);
  }

  function test_isValidSignature_revertsWith_InvalidDestinationCaller() public {
    TransferSpec memory spec = _defaultTransferSpec(1_000e6);
    spec.destinationCaller = bytes32(0);

    (bytes32 digest, bytes memory signature) = _signBurnIntent(
      investorPrivateKey,
      _encodeBurnIntent(spec)
    );

    vm.expectRevert(IReinvestmentController.InvalidDestinationCaller.selector);
    controller.isValidSignature(digest, signature);
  }
}
