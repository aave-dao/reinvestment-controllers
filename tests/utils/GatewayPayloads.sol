// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {AttestationLib} from '@circle-gateway/src/lib/AttestationLib.sol';
import {Attestation, AttestationSet} from '@circle-gateway/src/lib/Attestations.sol';
import {BurnIntentLib} from '@circle-gateway/src/lib/BurnIntentLib.sol';
import {BurnIntent, BurnIntentSet} from '@circle-gateway/src/lib/BurnIntents.sol';
import {TransferSpec, TRANSFER_SPEC_VERSION} from '@circle-gateway/src/lib/TransferSpec.sol';

/// @dev Builds the Circle Gateway payloads the controller consumes. Call {_setPayloadContext}
/// once the controller and its counterparties are deployed.
abstract contract GatewayPayloads {
  uint32 internal constant ETHEREUM_DOMAIN = 0;

  address internal payloadWallet;
  address internal payloadMinter;
  address internal payloadToken;
  address internal payloadDepositor;

  function _setPayloadContext(
    address wallet_,
    address minter_,
    address token_,
    address depositor_
  ) internal {
    payloadWallet = wallet_;
    payloadMinter = minter_;
    payloadToken = token_;
    payloadDepositor = depositor_;
  }

  function _defaultTransferSpec(uint256 value) internal view returns (TransferSpec memory) {
    return
      TransferSpec({
        version: TRANSFER_SPEC_VERSION,
        sourceDomain: ETHEREUM_DOMAIN,
        destinationDomain: ETHEREUM_DOMAIN,
        sourceContract: _toBytes32(payloadWallet),
        destinationContract: _toBytes32(payloadMinter),
        sourceToken: _toBytes32(payloadToken),
        destinationToken: _toBytes32(payloadToken),
        sourceDepositor: _toBytes32(payloadDepositor),
        destinationRecipient: _toBytes32(payloadDepositor),
        sourceSigner: _toBytes32(payloadDepositor),
        destinationCaller: _toBytes32(payloadDepositor),
        value: value,
        salt: keccak256(abi.encode(value, block.timestamp, block.number)),
        hookData: ''
      });
  }

  function _encodeAttestation(TransferSpec memory spec) internal view returns (bytes memory) {
    return
      AttestationLib.encodeAttestation(Attestation({maxBlockHeight: block.number, spec: spec}));
  }

  function _encodeAttestationSet(TransferSpec[] memory specs) internal view returns (bytes memory) {
    Attestation[] memory attestations = new Attestation[](specs.length);
    for (uint256 i = 0; i < specs.length; i++) {
      attestations[i] = Attestation({maxBlockHeight: block.number, spec: specs[i]});
    }
    return AttestationLib.encodeAttestationSet(AttestationSet({attestations: attestations}));
  }

  function _encodeBurnIntent(TransferSpec memory spec) internal view returns (bytes memory) {
    return
      BurnIntentLib.encodeBurnIntent(
        BurnIntent({maxBlockHeight: block.number, maxFee: 0, spec: spec})
      );
  }

  function _encodeBurnIntentSet(TransferSpec[] memory specs) internal view returns (bytes memory) {
    BurnIntent[] memory intents = new BurnIntent[](specs.length);
    for (uint256 i = 0; i < specs.length; i++) {
      intents[i] = BurnIntent({maxBlockHeight: block.number, maxFee: 0, spec: specs[i]});
    }
    return BurnIntentLib.encodeBurnIntentSet(BurnIntentSet({intents: intents}));
  }

  function _toBytes32(address account) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(account)));
  }
}
