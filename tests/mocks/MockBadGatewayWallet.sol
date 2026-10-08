// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

/// @dev Exposes just enough of {IGatewayWallet} to reach the domain separator probe, which it
/// fails. Stands in for an address that is not a Gateway wallet
contract MockBadGatewayWallet {
  uint32 public domain;

  function domainSeparator() external pure returns (bytes32) {
    return bytes32(0);
  }

  function isTokenSupported(address) external pure returns (bool) {
    return true;
  }
}
