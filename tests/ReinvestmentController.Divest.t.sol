// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {AddressLib} from '@circle-gateway/src/lib/AddressLib.sol';
import {AttestationLib} from '@circle-gateway/src/lib/AttestationLib.sol';
import {Attestation, AttestationSet} from '@circle-gateway/src/lib/Attestations.sol';
import {TransferSpec, TRANSFER_SPEC_VERSION} from '@circle-gateway/src/lib/TransferSpec.sol';

import {IReinvestmentController} from '../src/ReinvestmentController.sol';
import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerDivestTest is ReinvestmentControllerTestBase {
  uint256 public constant DIVEST_AMOUNT = 100_000e6;

  function test_divest_revertsWith_AccessControlUnauthorizedAccount() public {
    _invest(INVESTABLE);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        controller.INVESTOR_ROLE()
      )
    );
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT), '');
  }

  function test_divest_revertsWith_EnforcedPause() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    controller.pause();

    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT), '');
  }

  function test_divest_revertsWith_InvalidAmount_amountIsZero() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.divest(0, _attestation(0), '');
  }

  function test_divest_revertsWith_InsufficientLiquidity() public {
    _invest(INVESTABLE);

    uint256 amount = INVESTABLE + 1;

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InsufficientLiquidity.selector);
    controller.divest(amount, _attestation(amount), '');
  }

  function test_divest_revertsWith_CrossChainTransferNotAllowed() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationDomain = spec.sourceDomain + 1;

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.CrossChainTransferNotAllowed.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_InvalidSourceToken() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.sourceToken = AddressLib._addressToBytes32(address(hub));

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidSourceToken.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_InvalidDestinationToken() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationToken = AddressLib._addressToBytes32(address(hub));

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidDestinationToken.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_InvalidDepositor() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.sourceDepositor = AddressLib._addressToBytes32(admin);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidDepositor.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_InvalidRecipient() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationRecipient = AddressLib._addressToBytes32(admin);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidRecipient.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_InvalidSigner() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.sourceSigner = AddressLib._addressToBytes32(admin);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidSigner.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_InvalidDestinationCaller() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationCaller = bytes32(0);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidDestinationCaller.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_InvalidMintAmount_valueBelowAmount() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidMintAmount.selector);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT - 1), '');
  }

  function test_divest_revertsWith_InvalidMintAmount_valueAboveAmount() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidMintAmount.selector);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT + 1), '');
  }

  function test_divest_revertsWith_InvalidElementCount() public {
    _invest(INVESTABLE);

    bytes memory payload = _attestationSet(DIVEST_AMOUNT / 4, (DIVEST_AMOUNT * 3) / 4);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidElementCount.selector);
    controller.divest(DIVEST_AMOUNT, payload, '');
  }

  function test_divest_fullSweptAmount() public {
    _invest(INVESTABLE);

    _burnAtGateway(INVESTABLE);
    gatewayMinter.setNextMint(address(usdc), INVESTABLE);

    vm.prank(admin);
    controller.divest(INVESTABLE, _attestation(INVESTABLE), '');

    assertEq(controller.getInvestedAmount(), 0);
    assertEq(usdc.balanceOf(address(hub)), SUPPLIED);
    assertEq(usdc.balanceOf(address(gatewayWallet)), 0);
    assertEq(gatewayWallet.availableBalance(address(usdc), address(controller)), 0);
  }

  function test_divest() public {
    _invest(INVESTABLE);

    _burnAtGateway(DIVEST_AMOUNT);
    gatewayMinter.setNextMint(address(usdc), DIVEST_AMOUNT);

    vm.expectEmit(address(controller));
    emit IReinvestmentController.Divested(DIVEST_AMOUNT);

    vm.prank(admin);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT), '');

    assertEq(usdc.balanceOf(address(hub)), SUPPLIED - INVESTABLE + DIVEST_AMOUNT);
    assertEq(usdc.balanceOf(address(controller)), 0);

    assertEq(controller.getInvestedAmount(), INVESTABLE - DIVEST_AMOUNT);
    assertEq(hub.getAssetLiquidity(ASSET_ID), SUPPLIED - INVESTABLE + DIVEST_AMOUNT);

    assertEq(usdc.balanceOf(address(gatewayWallet)), INVESTABLE - DIVEST_AMOUNT);
    assertEq(
      gatewayWallet.availableBalance(address(usdc), address(controller)),
      INVESTABLE - DIVEST_AMOUNT
    );

    assertEq(usdc.totalSupply(), SUPPLIED);
  }

  function _burnAtGateway(uint256 amount) internal {
    gatewayWallet.simulateGatewayBurn(address(usdc), address(controller), amount);
  }

  function _transferSpec(uint256 value) internal view returns (TransferSpec memory) {
    bytes32 self = AddressLib._addressToBytes32(address(controller));

    return
      TransferSpec({
        version: TRANSFER_SPEC_VERSION,
        sourceDomain: 0,
        destinationDomain: 0,
        sourceContract: AddressLib._addressToBytes32(address(gatewayWallet)),
        destinationContract: AddressLib._addressToBytes32(address(gatewayWallet)),
        sourceToken: AddressLib._addressToBytes32(address(usdc)),
        destinationToken: AddressLib._addressToBytes32(address(usdc)),
        sourceDepositor: self,
        destinationRecipient: self,
        sourceSigner: self,
        destinationCaller: self,
        value: value,
        salt: bytes32(uint256(1)),
        hookData: ''
      });
  }

  function _encode(TransferSpec memory spec) internal view returns (bytes memory) {
    return
      AttestationLib.encodeAttestation(Attestation({maxBlockHeight: block.number + 1, spec: spec}));
  }

  function _attestation(uint256 value) internal view returns (bytes memory) {
    return _encode(_transferSpec(value));
  }

  function _attestationSet(
    uint256 firstValue,
    uint256 secondValue
  ) internal view returns (bytes memory) {
    Attestation[] memory attestations = new Attestation[](2);

    attestations[0] = Attestation({
      maxBlockHeight: block.number + 1,
      spec: _transferSpec(firstValue)
    });

    TransferSpec memory secondSpec = _transferSpec(secondValue);
    secondSpec.salt = bytes32(uint256(2));
    attestations[1] = Attestation({maxBlockHeight: block.number + 1, spec: secondSpec});

    return AttestationLib.encodeAttestationSet(AttestationSet({attestations: attestations}));
  }

  function test_divest_withinSweptAmount(uint256 amount) public {
    _invest(INVESTABLE);

    amount = bound(amount, 1, INVESTABLE);

    _burnAtGateway(amount);
    gatewayMinter.setNextMint(address(usdc), amount);

    vm.prank(admin);
    controller.divest(amount, _attestation(amount), '');

    assertEq(controller.getInvestedAmount(), INVESTABLE - amount);
    assertEq(usdc.balanceOf(address(hub)), SUPPLIED - INVESTABLE + amount);
    assertEq(usdc.balanceOf(address(controller)), 0);
  }
}
