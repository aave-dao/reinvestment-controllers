// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

import {AddressLib} from '@circle-gateway/src/lib/AddressLib.sol';
import {BurnIntentLib} from '@circle-gateway/src/lib/BurnIntentLib.sol';
import {BurnIntent, BurnIntentSet} from '@circle-gateway/src/lib/BurnIntents.sol';
import {TransferSpec, TRANSFER_SPEC_VERSION} from '@circle-gateway/src/lib/TransferSpec.sol';

import {IReinvestmentController} from '../src/ReinvestmentController.sol';
import {ReinvestmentControllerTest} from './ReinvestmentControllerBase.t.sol';

contract IsValidSignatureTest is ReinvestmentControllerTest {
  uint256 public constant INVESTOR_KEY = 0xA11CE;
  uint256 public constant OUTSIDER_KEY = 0xB0B;
  uint256 public constant WITHDRAW_AMOUNT = 100_000e6;

  address public investor = vm.addr(INVESTOR_KEY);
  address public outsider = vm.addr(OUTSIDER_KEY);

  function test_isValidSignature_revertsWith_paused() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    bytes memory payload = _burnIntent(WITHDRAW_AMOUNT);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.prank(admin);
    controller.pause();

    vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_hashMismatch() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    bytes memory payload = _burnIntent(WITHDRAW_AMOUNT);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.HashMismatch.selector);
    controller.isValidSignature(keccak256('bad-digest'), sig);
  }

  function test_isValidSignature_revertsWith_signerLacksInvestorRole() public {
    _invest(INVESTABLE);

    bytes memory payload = _burnIntent(WITHDRAW_AMOUNT);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(OUTSIDER_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidSignature.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_investorRoleRevoked() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    bytes32 role = controller.INVESTOR_ROLE();

    vm.prank(admin);
    controller.revokeRole(role, investor);

    bytes memory payload = _burnIntent(WITHDRAW_AMOUNT);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidSignature.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_crossChainTransferNotAllowed() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(WITHDRAW_AMOUNT);
    spec.destinationDomain = spec.sourceDomain + 1;
    bytes memory payload = _encode(spec);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.CrossChainTransferNotAllowed.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_invalidSourceToken() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(WITHDRAW_AMOUNT);
    spec.sourceToken = AddressLib._addressToBytes32(address(hub));
    bytes memory payload = _encode(spec);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidSourceToken.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_invalidDestinationToken() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(WITHDRAW_AMOUNT);
    spec.destinationToken = AddressLib._addressToBytes32(address(hub));
    bytes memory payload = _encode(spec);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidDestinationToken.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_invalidDepositor() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(WITHDRAW_AMOUNT);
    spec.sourceDepositor = AddressLib._addressToBytes32(investor);
    bytes memory payload = _encode(spec);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidDepositor.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_invalidRecipient() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(WITHDRAW_AMOUNT);
    spec.destinationRecipient = AddressLib._addressToBytes32(investor);
    bytes memory payload = _encode(spec);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidRecipient.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_invalidSigner() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(WITHDRAW_AMOUNT);
    spec.sourceSigner = AddressLib._addressToBytes32(investor);
    bytes memory payload = _encode(spec);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidSigner.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_invalidDestinationCaller() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    TransferSpec memory spec = _transferSpec(WITHDRAW_AMOUNT);
    spec.destinationCaller = bytes32(0);
    bytes memory payload = _encode(spec);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidDestinationCaller.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_burnIntentExceedsBalance() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    bytes memory payload = _burnIntent(INVESTABLE + 1);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.BurnIntentExceedsBalance.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_balanceQueuedForWithdrawal() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    vm.prank(admin);
    controller.initiateWithdrawal(WITHDRAW_AMOUNT);

    bytes memory payload = _burnIntent(INVESTABLE - WITHDRAW_AMOUNT + 1);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.BurnIntentExceedsBalance.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_revertsWith_burnIntentSet() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    bytes memory payload = _burnIntentSet(WITHDRAW_AMOUNT, WITHDRAW_AMOUNT);

    bytes32 digest = _digest(payload);
    bytes memory sig = _signature(INVESTOR_KEY, payload);

    vm.expectRevert(IReinvestmentController.InvalidElementCount.selector);
    controller.isValidSignature(digest, sig);
  }

  function test_isValidSignature_atFullMintableBalance() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    bytes memory payload = _burnIntent(INVESTABLE);

    assertEq(
      controller.isValidSignature(_digest(payload), _signature(INVESTOR_KEY, payload)),
      IERC1271.isValidSignature.selector
    );
  }

  function test_isValidSignature_successful() public {
    _grantInvestorRole();
    _invest(INVESTABLE);

    bytes memory payload = _burnIntent(WITHDRAW_AMOUNT);

    assertEq(
      controller.isValidSignature(_digest(payload), _signature(INVESTOR_KEY, payload)),
      IERC1271.isValidSignature.selector
    );
  }

  function _grantInvestorRole() internal {
    bytes32 role = controller.INVESTOR_ROLE();

    vm.prank(admin);
    controller.grantRole(role, investor);
  }

  function _transferSpec(uint256 value) internal view returns (TransferSpec memory) {
    bytes32 self = AddressLib._addressToBytes32(address(controller));

    return
      TransferSpec({
        version: TRANSFER_SPEC_VERSION,
        sourceDomain: 0,
        destinationDomain: 0,
        sourceContract: AddressLib._addressToBytes32(address(gatewayWallet)),
        destinationContract: AddressLib._addressToBytes32(address(gatewayMinter)),
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
      BurnIntentLib.encodeBurnIntent(
        BurnIntent({maxBlockHeight: block.number + 1, maxFee: 0, spec: spec})
      );
  }

  function _burnIntent(uint256 value) internal view returns (bytes memory) {
    return _encode(_transferSpec(value));
  }

  function _burnIntentSet(
    uint256 firstValue,
    uint256 secondValue
  ) internal view returns (bytes memory) {
    BurnIntent[] memory intents = new BurnIntent[](2);

    intents[0] = BurnIntent({
      maxBlockHeight: block.number + 1,
      maxFee: 0,
      spec: _transferSpec(firstValue)
    });

    TransferSpec memory secondSpec = _transferSpec(secondValue);
    secondSpec.salt = bytes32(uint256(2));
    intents[1] = BurnIntent({maxBlockHeight: block.number + 1, maxFee: 0, spec: secondSpec});

    return BurnIntentLib.encodeBurnIntentSet(BurnIntentSet({intents: intents}));
  }

  function _digest(bytes memory burnIntentPayload) internal view returns (bytes32) {
    return
      MessageHashUtils.toTypedDataHash(
        gatewayWallet.domainSeparator(),
        BurnIntentLib.getTypedDataHash(burnIntentPayload)
      );
  }

  function _signature(
    uint256 signerKey,
    bytes memory burnIntentPayload
  ) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _digest(burnIntentPayload));

    return abi.encode(abi.encodePacked(r, s, v), burnIntentPayload);
  }
}
