// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {AddressLib} from '@circle-gateway/src/lib/AddressLib.sol';
import {AttestationLib} from '@circle-gateway/src/lib/AttestationLib.sol';
import {Attestation, AttestationSet} from '@circle-gateway/src/lib/Attestations.sol';
import {TransferSpec, TRANSFER_SPEC_VERSION} from '@circle-gateway/src/lib/TransferSpec.sol';

import {IReinvestmentController} from '../src/ReinvestmentController.sol';
import {ReinvestmentControllerTest} from './ReinvestmentControllerBase.t.sol';

contract DivestTest is ReinvestmentControllerTest {
  uint256 public constant DIVEST_AMOUNT = 100_000e6;

  function test_divest_revertsWith_callerIsNotInvestor() public {
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

  function test_divest_revertsWith_paused() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    controller.pause();

    vm.prank(admin);
    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT), '');
  }

  function test_divest_revertsWith_amountIsZero() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.divest(0, _attestation(0), '');
  }

  function test_divest_revertsWith_amountExceedsGatewayTxLimit() public {
    _invest(INVESTABLE);

    uint256 amount = controller.gatewayTxLimit() + 1;

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.divest(amount, _attestation(amount), '');
  }

  function test_divest_revertsWith_gatewayTxLimitSetToZero() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    controller.setGatewayTxLimit(0);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT), '');
  }

  function test_divest_revertsWith_insufficientLiquidity() public {
    _invest(INVESTABLE);

    uint256 amount = INVESTABLE + 1;

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InsufficientLiquidity.selector);
    controller.divest(amount, _attestation(amount), '');
  }

  function test_divest_revertsWith_crossChainTransferNotAllowed() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationDomain = spec.sourceDomain + 1;

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.CrossChainTransferNotAllowed.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_invalidSourceToken() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.sourceToken = AddressLib._addressToBytes32(address(hub));

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidSourceToken.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_invalidDestinationToken() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationToken = AddressLib._addressToBytes32(address(hub));

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidDestinationToken.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_invalidDepositor() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.sourceDepositor = AddressLib._addressToBytes32(admin);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidDepositor.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_invalidRecipient() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationRecipient = AddressLib._addressToBytes32(admin);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidRecipient.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_invalidSigner() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.sourceSigner = AddressLib._addressToBytes32(admin);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidSigner.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_invalidDestinationCaller() public {
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(DIVEST_AMOUNT);
    spec.destinationCaller = bytes32(0);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidDestinationCaller.selector);
    controller.divest(DIVEST_AMOUNT, _encode(spec), '');
  }

  function test_divest_revertsWith_attestationValueBelowAmount() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidMintAmount.selector);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT - 1), '');
  }

  function test_divest_revertsWith_attestationValueAboveAmount() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidMintAmount.selector);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT + 1), '');
  }

  function test_divest_revertsWith_attestationSet() public {
    _invest(INVESTABLE);

    bytes memory payload = _attestationSet(DIVEST_AMOUNT / 4, (DIVEST_AMOUNT * 3) / 4);

    vm.prank(admin);
    vm.expectRevert(IReinvestmentController.InvalidElementCount.selector);
    controller.divest(DIVEST_AMOUNT, payload, '');
  }

  function test_divest_atGatewayTxLimit() public {
    _invest(INVESTABLE);

    vm.prank(admin);
    controller.setGatewayTxLimit(DIVEST_AMOUNT);

    _burnAtGateway(DIVEST_AMOUNT);
    gatewayMinter.setNextMint(address(usdc), DIVEST_AMOUNT);

    vm.prank(admin);
    controller.divest(DIVEST_AMOUNT, _attestation(DIVEST_AMOUNT), '');

    assertEq(controller.getInvestedAmount(), INVESTABLE - DIVEST_AMOUNT);
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

  function test_divest_successful() public {
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
}
