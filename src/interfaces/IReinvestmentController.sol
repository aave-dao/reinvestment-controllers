// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {IGatewayMinter} from './IGatewayMinter.sol';
import {IGatewayWallet} from './IGatewayWallet.sol';

interface IReinvestmentController is IERC1271 {
  /// @dev Burn intent exceeds the invested amount
  error BurnIntentExceedsBalance();

  /// @dev Withdrawals are only allowed on the same network as invested
  error CrossChainTransferNotAllowed();

  /// @dev Deposits under timelock
  error DepositTimelock();

  /// @dev Provided hash does not match the calculated hash
  error HashMismatch();

  /// @dev Invalid amount provided
  error InvalidAmount();

  /// @dev Payload must contain exactly one burn intent or attestation
  error InvalidElementCount();

  /// @dev Invalid depositor provided in transfer specification
  error InvalidDepositor();

  /// @dev Invalid destination caller provided in transfer specification
  error InvalidDestinationCaller();

  /// @dev Invalid destination token provided in transfer specification
  error InvalidDestinationToken();

  /// @dev Invalid mint amount provided in attestation
  error InvalidMintAmount();

  /// @dev Invalid recipient provided in transfer specification
  error InvalidRecipient();

  /// @dev Signer does not have INVESTOR_ROLE to sign transaction
  error InvalidSignature();

  /// @dev Invalid signer provided in transfer specification
  error InvalidSigner();

  /// @dev Invalid source token provided in transfer specification
  error InvalidSourceToken();

  /// @dev Amount exceeds the invested amount
  error InsufficientLiquidity();

  /// @dev Provided address cannot be the zero-address
  error InvalidZeroAddress();

  /// @dev Fee in the burn intent exceeds the maximum allowed fee
  error MaxFeeExceeded();

  /// @dev Amount to be deposited cannot exceed max investable amount
  error MaximumInvestAmountExceeded();

  /// @dev No pending on-chain withdrawal
  error NoWithdrawalInProcess();

  /// @dev An existing withdrawal is already in process
  error WithdrawalInProcess();

  /// @dev Emitted when funds are invested
  /// @param amount The amount of funds invested
  event Invested(uint256 amount);

  /// @dev Emitted when funds are divested
  /// @param amount The amount of funds divested
  /// @param fee The fee pre-paid by the caller to keep the Hub's swept accounting exact
  event Divested(uint256 amount, uint256 fee);

  /// @dev Emitted when the deposit timelock is updated
  /// @param oldDepositTimelock The old deposit timelock
  /// @param depositTimelock The new deposit timelock
  event SetDepositTimelock(uint256 oldDepositTimelock, uint256 depositTimelock);

  /// @dev Emitted when the maximum allowed burn intent fee is updated
  /// @param oldMaxFee The old maximum fee
  /// @param maxFee The new maximum fee
  event SetMaxFee(uint256 oldMaxFee, uint256 maxFee);

  /// @dev Emitted when the maximum investable amount (in absolute terms) is updated
  /// @param oldMaxInvest The old maximum investable amount
  /// @param maxInvest The new maximum investable amount
  event SetMaxInvest(uint256 oldMaxInvest, uint256 maxInvest);

  /// @dev Emitted when the maximum investable amount (in BPS) is updated
  /// @param oldMaxInvestBps The old maximum investable amount
  /// @param maxInvestBps The new maximum investable amount
  event SetMaxInvestBps(uint256 oldMaxInvestBps, uint256 maxInvestBps);

  /// @dev Emitted when the minimum uninvestable amount buffer (in BPS) is updated
  /// @param oldBufferBps The old minimum buffer amount
  /// @param bufferBps The new  minimum buffer amount
  event SetBufferBps(uint256 oldBufferBps, uint256 bufferBps);

  /// @dev Emitted when an on-chain withdrawal is completed
  /// @param amount The amount of funds withdrawn
  event WithdrawalCompleted(uint256 amount);

  /// @dev Emitted when an on-chain withdrawal is initiated
  /// @param amount The amount of funds withdrawn
  event WithdrawalInitiated(uint256 amount);

  /// @notice Initializes the controller's roles and investment limits
  /// @dev Callable once, on a proxy. The implementation itself is locked at construction,
  /// and the protocol addresses (GATEWAY_WALLET, GATEWAY_MINTER, HUB, USDC, ASSET_ID) are
  /// fixed there rather than
  /// here, so changing one requires deploying a new implementation and upgrading to it.
  /// @param admin The address granted both DEFAULT_ADMIN_ROLE and INVESTOR_ROLE
  /// @param depositTimelock_ The initial deposit timelock (in seconds)
  /// @param maxInvest_ The initial maximum investable amount (in absolute terms)
  /// @param maxInvestBps_ The initial maximum investable amount (in BPS)
  /// @param maxFee_ The initial maximum fee payable on a withdrawal (in absolute terms)
  /// @param bufferBps_ The initial minimum uninvested buffer (in BPS)
  function initialize(
    address admin,
    uint256 depositTimelock_,
    uint256 maxInvest_,
    uint256 maxInvestBps_,
    uint256 maxFee_,
    uint256 bufferBps_
  ) external;

  /// @notice Invests amount of funds into USDC Gateway
  /// @param amount Amount of USDC to invest
  function invest(uint256 amount) external;

  /// @notice Divests amount of funds from USDC Gateway
  /// @dev Bounded only by the swept balance. Circle caps attestation size off-chain, and the
  /// Gateway contracts impose no on-chain limit
  /// @dev The caller must hold and have approved {maxFee} of USDC. It is forwarded to the Hub
  /// alongside the minted amount, because the Gateway debits `amount + fee` when Circle later
  /// burns. Reclaiming `amount + maxFee` keeps the Hub's swept figure matched to the balance
  /// actually held at the Gateway, rather than overstating it by the fee on every divest
  /// @param amount The amount of funds to withdraw
  /// @param attestationPayload The specification of the withdrawal
  /// @param signature The signature that validates attestation was originated by authorized entity
  function divest(
    uint256 amount,
    bytes calldata attestationPayload,
    bytes calldata signature
  ) external;

  /// @notice Initiates an on-chain withdrawal of the entire Gateway balance
  /// @dev Only while paused, so no attestation or burn intent can be live against the balance
  /// being moved. Moving it out of the Gateway's available bucket is itself what stops any
  /// further burn from succeeding
  function initiateWithdrawal() external;

  /// @notice Finalizes a pending withdrawal after required time has elapsed
  function withdraw() external;

  /// @notice Halts {invest}, {divest} and {isValidSignature}
  /// @dev Blocking {isValidSignature} stops the Gateway from burning against this contract's
  /// balance while paused. Withdrawal paths stay open so funds can always be returned to the Hub
  function pause() external;

  /// @notice Resumes {invest}, {divest} and {isValidSignature}
  /// @dev Restricted to DEFAULT_ADMIN_ROLE, so a PAUSER_ROLE holder cannot undo its own halt.
  /// Blocked while an on-chain withdrawal is in flight, since those funds have left the
  /// Gateway's available balance and can no longer back a burn until {withdraw} completes
  function unpause() external;

  /// @notice Sets a new deposit timelock (in seconds)
  /// @param depositTimelock_ The new deposit timelock amount (in seconds)
  function setDepositTimelock(uint256 depositTimelock_) external;

  /// @dev Sets the minimum amount of buffer that must be left on the Hub uninvested (in BPS)
  /// @param buffer New buffer amount (in BPS)
  function setBufferBps(uint256 buffer) external;

  /// @notice Sets the maximum fee that can be paid to the Gateway operator on a withdrawal
  /// Can be set to 0 to reject any fee-bearing withdrawal
  /// @param maxFee_ The new maximum fee (in absolute terms)
  function setMaxFee(uint256 maxFee_) external;

  /// @notice Sets the maximum amount that can be invested (in absolute terms)
  /// Can be set to 0 to sunset ReinvestmentController
  /// @param maxAmount The new maximum amount (in absolute terms)
  function setMaxInvest(uint256 maxAmount) external;

  /// @dev Sets the maximum amount that can be invested (in BPS)
  /// @dev maxBps New maximum amount (in BPS)
  function setMaxInvestBps(uint256 maxBps) external;

  /// @notice Returns the identifier of the INVESTOR Role
  /// @return The bytes32 id hash of the INVESTOR_ROLE
  function INVESTOR_ROLE() external view returns (bytes32);

  /// @notice Returns the identifier of the PAUSER Role
  /// @return The bytes32 id hash of the PAUSER_ROLE
  function PAUSER_ROLE() external view returns (bytes32);

  /// @notice Returns the address of the Circle Gateway wallet, which holds deposits and
  /// serves the on-chain withdrawal path
  /// @return The address of the Gateway wallet
  function GATEWAY_WALLET() external view returns (IGatewayWallet);

  /// @notice Returns the address of the Circle Gateway minter, which mints against
  /// signed attestations
  /// @return The address of the Gateway minter
  function GATEWAY_MINTER() external view returns (IGatewayMinter);

  /// @notice Returns the address of the Hub
  /// @return The address of the Hub
  function HUB() external view returns (IHub);

  /// @notice Returns the address of the USDC token
  /// @return The address of USDC
  function USDC() external view returns (IERC20);

  /// @notice Returns the ID of the USDC asset on the Hub
  /// @return The asset ID
  function ASSET_ID() external view returns (uint256);

  /// @notice Returns the amount available to invest at any given time
  /// @return The investable amount
  function getInvestableAmount() external view returns (uint256);

  /// @notice Returns the amount of funds currently invested
  /// @return The amount invested
  function getInvestedAmount() external view returns (uint256);

  /// @notice Returns the amount by which the Hub's swept figure exceeds the balance actually
  /// held at the Gateway
  /// @dev Zero in normal operation, since {divest} pre-pays the fee. A non-zero value means a
  /// burn charged more than was pre-paid, and that much of the Hub's asset base is unbacked
  /// @return The unbacked amount
  function getDrift() external view returns (uint256);

  /// @notice Validates an ERC-1271 signature over a Circle Gateway burn intent
  /// @dev Called by the Gateway to confirm this contract authorized a withdrawal, as the
  /// contract is the depositor, recipient and signer of every burn intent it submits.
  /// The burn intent is re-hashed against the Gateway's domain separator and must match
  /// `hash`, the recovered signer must hold INVESTOR_ROLE, and the intent itself must pass
  /// the same-chain, token, counterparty and balance checks applied on submission.
  /// Reverts on any failure rather than returning a non-magic selector, so a call that
  /// returns at all returns `IERC1271.isValidSignature.selector`.
  /// @param hash The EIP-712 digest the Gateway expects to have been signed
  /// @param signature abi.encode(bytes adminSignature, bytes burnIntentPayload), where
  /// `adminSignature` is an ECDSA signature over `hash` and `burnIntentPayload` is the
  /// burn intent that signature authorizes
  /// @return `IERC1271.isValidSignature.selector` when the signature is valid
  function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);

  /// @notice Returns the deposit timelock
  /// @return The timelock (in seconds)
  function depositTimelock() external view returns (uint256);

  /// @notice Returns the maximum fee payable to the Gateway operator on a withdrawal
  /// @dev Compared against the `maxFee` field of a burn intent, which bounds what the operator
  /// may charge. The Gateway wallet debits `value + fee`, so the fee is drawn from the invested
  /// balance on top of the amount withdrawn
  /// @return The maximum fee (in absolute terms)
  function maxFee() external view returns (uint256);

  /// @notice Returns the maximum amount that can be invested (in absolute terms) at any time
  /// @dev Can be set to zero to sunset ReinvestmentController
  /// @return The amount that can be invested
  function maxInvest() external view returns (uint256);

  /// @notice Returns the maximum amount that can be invested (in BPS) at any time
  /// @return The amount that can be invested (in BPS)
  function maxInvestBps() external view returns (uint256);

  /// @notice Returns the minimum amount that must remain uninvested in the Hub
  /// @return The amount that must remain uninvested (in BPS)
  function bufferBps() external view returns (uint256);

  /// @notice Returns the timestamp of the most recent pause, or zero if not paused
  /// @return The timestamp at which {pause} was last called
  function pausedAt() external view returns (uint256);
}
