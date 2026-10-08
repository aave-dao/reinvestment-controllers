// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

/// @notice The deposit side of Circle's Gateway, deployed as `GatewayWallet`
/// @dev Holds deposited balances and owns the on-chain withdrawal path. Minting is a
/// separate contract at a separate address; see {IGatewayMinter}.
interface IGatewayWallet {
  /// @notice Deposit tokens after approving this contract for the token
  /// @dev The resulting balance in this contract belongs to `msg.sender`
  /// @param token The token to deposit
  /// @param value The amount to be deposited
  function deposit(address token, uint256 value) external;

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

  /// @dev Burn intents are signed against the wallet's domain, so this is the separator
  /// the controller must reproduce when validating an ERC-1271 signature. The minter
  /// exposes its own separator bound to a different verifying contract.
  /// @return The EIP-712 domain separator used for signing burn intent payloads
  function domainSeparator() external view returns (bytes32);

  /// @notice Returns the Gateway domain this contract operates on
  /// @return The Gateway domain identifier
  function domain() external view returns (uint32);

  /// @notice Whether the wallet accepts deposits of a token
  /// @param token The token to check
  /// @return True when the token is supported
  function isTokenSupported(address token) external view returns (bool);

  /// @notice The balance still usable to back a burn, and therefore a mint
  /// @dev Reduced by `initiateWithdrawal`, which moves the amount into {withdrawingBalance}, by
  /// Circle's out-of-band burn of an attested intent, and by `submitBatch`, where a signer
  /// registered by the wallet's owner applies balance deltas with no depositor signature and no
  /// burn intent. This contract neither registers such signers nor opts into batches, and cannot
  /// decline them. A batch must net to zero across depositors, so it cannot create balance, but it
  /// can move this contract's balance to another depositor
  /// @param token The deposited token
  /// @param depositor The owner of the balance
  /// @return The available balance
  function availableBalance(address token, address depositor) external view returns (uint256);

  /// @notice The balance reserved by an in-progress on-chain withdrawal
  /// @dev Not usable to back a new mint, but still reachable by a burn or a `submitBatch` debit
  /// once the available balance is exhausted. Paid out by `withdraw` once {withdrawalBlock} has
  /// been reached.
  /// @param token The deposited token
  /// @param depositor The owner of the balance
  /// @return The withdrawing balance
  function withdrawingBalance(address token, address depositor) external view returns (uint256);

  /// @notice The number of blocks that must pass before an initiated withdrawal completes
  /// @return The withdrawal delay, in blocks
  function withdrawalDelay() external view returns (uint256);

  /// @notice The block at which an in-progress withdrawal becomes completable
  /// @dev `withdraw` reverts while `block.number` is below this. Zero when no
  /// withdrawal is in progress.
  /// @param token The deposited token
  /// @param depositor The owner of the balance
  /// @return The block number
  function withdrawalBlock(address token, address depositor) external view returns (uint256);
}
