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

  /// @notice Returns the Gateway domain this contract operates on
  /// @return The Gateway domain identifier
  function domain() external view returns (uint32);

  /// @notice Whether the minter can mint a token
  /// @param token The token to check
  /// @return True when the token is supported
  function isTokenSupported(address token) external view returns (bool);
}
