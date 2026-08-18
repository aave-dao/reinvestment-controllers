// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

/// @notice The mint side of Circle's Gateway, deployed as `GatewayMinter`
/// @dev A separate contract at a separate address from {IGatewayWallet}. `gatewayMint` is
/// not present on the wallet, and the wallet's `gatewayBurn` is not present here.
interface IGatewayMinter {
  /// @notice Mint funds via a signed attestation
  /// @param attestationPayload The byte-encoded attestation(s)
  /// @param signature The signature from a valid attestation signer on `attestationPayload`
  function gatewayMint(bytes memory attestationPayload, bytes memory signature) external;
}
