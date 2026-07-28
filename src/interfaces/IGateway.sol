// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

interface IGateway {
    /// @notice Deposit tokens after approving this contract for the token
    /// @dev The resulting balance in this contract belongs to `msg.sender`
    /// @param token The token to deposit
    /// @param value The amount to be deposited
    function deposit(address token, uint256 value) external;

    /// @notice Mint funds via a signed attestation
    /// @param attestationPayload The byte-encoded attestation(s)
    /// @param signature The signature from a valid attestation signer on `attestationPayload`
    function gatewayMint(
        bytes memory attestationPayload,
        bytes memory signature
    ) external;

    /// Starts the withdrawal process. After `withdrawalDelay` blocks, `withdraw` may be called to complete the
    /// withdrawal. Once a withdrawal has been initiated, that amount can no longer be used. Repeated calls will add to
    /// the amount and reset the timer.
    ///
    /// @param token   The token to initiate a withdrawal for
    /// @param value   The amount to be withdrawn
    function initiateWithdrawal(address token, uint256 value) external;

    /// Completes a withdrawal that was initiated at least `withdrawalDelay` blocks ago. The funds are sent to
    /// the depositor (msg.sender).
    ///
    /// @dev The full amount that is in the process of being withdrawn is always withdrawn
    ///
    /// @param token   The token to withdraw
    function withdraw(address token) external;

    /// @return The EIP-712 domain separator used for signing burn intent payloads
    function domainSeparator() external view returns (bytes32);
}
