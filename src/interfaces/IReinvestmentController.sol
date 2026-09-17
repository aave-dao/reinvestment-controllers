// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {IGatewayMinter} from './IGatewayMinter.sol';
import {IGatewayWallet} from './IGatewayWallet.sol';

interface IReinvestmentController is IERC1271, IAccessControl {
  /// @dev Burn intent exceeds the invested amount
  error BurnIntentExceedsBalance();

  /// @dev Withdrawals are only allowed on the same network as invested
  error CrossChainTransferNotAllowed();

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

  /// @dev Invalid destination contract provided in transfer specification
  error InvalidDestinationContract();

  /// @dev Invalid destination token provided in transfer specification
  error InvalidDestinationToken();

  /// @dev Transfer specification domain does not match the Gateway domain of this chain
  error InvalidDomain();

  /// @dev Transfer specification carries hook data, which is not supported
  error InvalidHookData();

  /// @dev Invalid mint amount provided in attestation
  error InvalidMintAmount();

  /// @dev Invalid recipient provided in transfer specification
  error InvalidRecipient();

  /// @dev Signer does not have KEEPER_ROLE to sign transaction
  error InvalidSignature();

  /// @dev Invalid signer provided in transfer specification
  error InvalidSigner();

  /// @dev Invalid source contract provided in transfer specification
  error InvalidSourceContract();

  /// @dev Invalid source token provided in transfer specification
  error InvalidSourceToken();

  /// @dev Amount exceeds the invested amount
  error InsufficientLiquidity();

  /// @dev Provided address cannot be the zero-address
  error InvalidZeroAddress();

  /// @dev Minimum delay between invests has not elapsed
  error InvestMinDelayNotElapsed();

  /// @dev Fee in the burn intent exceeds the maximum allowed fee
  error MaxFeeExceeded();

  /// @dev Amount to be deposited cannot exceed the configured exposure caps
  error ExposureCapExceeded();

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

  /// @dev Emitted when the minimum delay between invests is updated
  /// @param oldInvestMinDelay The old minimum delay
  /// @param investMinDelay The new minimum delay
  event SetInvestMinDelay(uint256 oldInvestMinDelay, uint256 investMinDelay);

  /// @dev Emitted when the maximum allowed burn intent fee is updated
  /// @param oldMaxFee The old maximum fee
  /// @param maxFee The new maximum fee
  event SetMaxFee(uint256 oldMaxFee, uint256 maxFee);

  /// @dev Emitted when the exposure cap (in absolute terms) is updated
  /// @param oldExposureCapAbs The old exposure cap
  /// @param exposureCapAbs The new exposure cap
  event SetExposureCapAbs(uint256 oldExposureCapAbs, uint256 exposureCapAbs);

  /// @dev Emitted when the exposure cap (in BPS of supplied assets) is updated
  /// @param oldExposureCapBps The old exposure cap
  /// @param exposureCapBps The new exposure cap
  event SetExposureCapBps(uint256 oldExposureCapBps, uint256 exposureCapBps);

  /// @dev Emitted when the liquid buffer (in BPS) is updated
  /// @param oldLiquidBufferBps The old liquid buffer
  /// @param liquidBufferBps The new liquid buffer
  event SetLiquidBufferBps(uint256 oldLiquidBufferBps, uint256 liquidBufferBps);

  /// @dev Emitted when an on-chain withdrawal is completed
  /// @param amount The amount of funds withdrawn
  event WithdrawalCompleted(uint256 amount);

  /// @dev Emitted when an on-chain withdrawal is initiated
  /// @param amount The amount of funds withdrawn
  event WithdrawalInitiated(uint256 amount);

  /// @notice Initializes the controller's roles and investment limits
  /// @dev Callable once, on a proxy. The implementation itself is locked at construction,
  /// and the protocol addresses (GATEWAY_WALLET, GATEWAY_MINTER, HUB, USDC, ASSET_ID, DOMAIN) are
  /// fixed there rather than
  /// here, so changing one requires deploying a new implementation and upgrading to it.
  /// @param admin The address granted both DEFAULT_ADMIN_ROLE and KEEPER_ROLE
  /// @param investMinDelay_ The initial minimum delay between invests (in seconds)
  /// @param exposureCapAbs_ The initial exposure cap (in absolute terms)
  /// @param exposureCapBps_ The initial exposure cap (in BPS of supplied assets)
  /// @param maxFee_ The initial maximum fee payable on a withdrawal (in absolute terms)
  /// @param liquidBufferBps_ The initial liquid buffer (in BPS)
  function initialize(
    address admin,
    uint256 investMinDelay_,
    uint256 exposureCapAbs_,
    uint256 exposureCapBps_,
    uint256 maxFee_,
    uint256 liquidBufferBps_
  ) external;

  /// @notice Invests amount of funds into USDC Gateway
  /// @param amount Amount of USDC to invest
  function invest(uint256 amount) external;

  /// @notice Divests amount of funds from USDC Gateway
  /// @dev Bounded only by the swept balance. Circle caps attestation size off-chain, and the
  /// Gateway contracts impose no on-chain limit
  /// @dev The attestation names this contract as recipient, so the mint lands here and is then
  /// transferred on to the Hub, rather than naming the Hub directly and letting {reclaim} find
  /// the funds already there. {reclaim} only requires the Hub's aggregate balance to cover the
  /// reclaimed amount, a floor any unrelated USDC satisfies, so routing the mint through this
  /// contract is what proves the funds returned are the funds withdrawn. It also keeps every
  /// field of the transfer spec pinned to `self`
  /// @dev The caller must hold and have approved {maxFee} of USDC. It is forwarded to the Hub
  /// alongside the minted amount, because the Gateway debits `amount + fee` when Circle later
  /// burns. Circle charges a flat fee equal to {maxFee} today, so the two match and nothing is
  /// left behind. Were it ever to charge less, that lower fee would not be knowable here, since
  /// Circle may settle the burn only after issuing the attestation. {maxFee} is charged
  /// regardless, which errs toward over-funding the Hub rather than under-funding it, and
  /// strands the difference in the Gateway
  /// @param amount The amount of funds to withdraw
  /// @param attestationPayload The specification of the withdrawal
  /// @param signature The signature that validates attestation was originated by authorized entity
  function divest(
    uint256 amount,
    bytes calldata attestationPayload,
    bytes calldata signature
  ) external;

  /// @notice Initiates an on-chain withdrawal of the Gateway balance, capped at the swept amount
  /// @dev Only while paused, so no new burn intent validates and no attestation is consumed
  /// against the balance being moved. It does not stop a burn Circle has already vouched for, as
  /// the Gateway draws a burn from the withdrawing balance once the available one is exhausted.
  /// The available balance can exceed what the Hub swept, either
  /// through a third-party `depositFor`, which is permissionless, or through {divest} pre-paying
  /// a fee higher than Circle charged. Neither is reclaimable, since the Hub can only take back
  /// what it swept, so the excess is left in the Gateway
  function initiateWithdrawal() external;

  /// @notice Finalizes a pending withdrawal after required time has elapsed
  function withdraw() external;

  /// @notice Halts {invest}, {divest} and {isValidSignature}
  /// @dev Blocking {isValidSignature} stops new burn intents from validating, and blocking {divest}
  /// stops attestations from being consumed. It cannot cancel a burn Circle has already vouched
  /// for: the Gateway does not call {isValidSignature} at burn time, but accepts a registered TEE
  /// signer's signature as proof the TEE validated the intent against a quorum of RPCs. RPC lag may
  /// also let the TEE briefly approve against pre-pause state. Withdrawal paths stay open so funds
  /// can always be returned to the Hub
  function pause() external;

  /// @notice Resumes {invest}, {divest} and {isValidSignature}
  /// @dev Restricted to DEFAULT_ADMIN_ROLE, so a PAUSER_ROLE holder cannot undo its own halt.
  /// Blocked while an on-chain withdrawal is in flight, since those funds have left the
  /// Gateway's available balance and can no longer back a burn until {withdraw} completes
  function unpause() external;

  /// @notice Sets a new minimum delay between invests (in seconds)
  /// @param investMinDelay_ The new minimum delay between invests (in seconds)
  function setInvestMinDelay(uint256 investMinDelay_) external;

  /// @notice Sets the liquid buffer that must be left on the Hub uninvested (in BPS)
  /// @param liquidBufferBps The new liquid buffer (in BPS)
  function setLiquidBufferBps(uint256 liquidBufferBps) external;

  /// @notice Sets the maximum fee that can be paid to the Gateway operator on a withdrawal
  /// Can be set to 0 to reject any fee-bearing withdrawal
  /// @dev Only while paused. {divest} pre-pays the current {maxFee}, but Circle charges up to the
  /// `maxFee` of the burn intent it attested, which {isValidSignature} checked against the cap at
  /// signing time. An attestation carries no fee field, so {divest} cannot detect a cap that moved
  /// in between. Pausing stops new intents validating and stops {divest} consuming attestations
  /// while the change lands
  /// @dev Pausing does not invalidate intents already attested. To lower the cap: let outstanding
  /// intents settle through {divest} first, then pause, then lower. That order matters, as {divest}
  /// is itself `whenNotPaused`, so pausing first blocks the settlement that has to happen. A lower
  /// cap otherwise makes {divest} pre-pay less than Circle can still charge against an intent
  /// signed under the old one. Raising the cap needs no draining: it only makes {divest}
  /// over-pay, which cannot leave the Hub's `swept` overstated
  /// @param maxFee_ The new maximum fee (in absolute terms)
  function setMaxFee(uint256 maxFee_) external;

  /// @notice Sets the exposure cap (in absolute terms)
  /// Can be set to 0 to sunset ReinvestmentController
  /// @param newExposureCapAbs The new exposure cap
  function setExposureCapAbs(uint256 newExposureCapAbs) external;

  /// @notice Sets the exposure cap (in BPS of supplied assets)
  /// @param newExposureCapBps The new exposure cap
  function setExposureCapBps(uint256 newExposureCapBps) external;

  /// @notice Returns the identifier of the KEEPER Role
  /// @return The bytes32 id hash of the KEEPER_ROLE
  function KEEPER_ROLE() external view returns (bytes32);

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

  /// @notice Returns the Circle Gateway domain of this chain, read from the Gateway wallet
  /// @return The Gateway domain
  function DOMAIN() external view returns (uint32);

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

  /// @notice Validates an ERC-1271 signature over a Circle Gateway burn intent
  /// @dev Called off-chain by Circle's TEE, against a quorum of RPCs, to confirm this contract
  /// authorized a withdrawal, as the contract is the depositor, recipient and signer of every burn
  /// intent it submits. The Gateway does not call it again at burn time, as the TEE's signature
  /// stands as proof the check passed.
  /// The burn intent is re-hashed against the Gateway's domain separator and must match
  /// `hash`, the recovered signer must hold KEEPER_ROLE, and the intent itself must pass
  /// the non-zero value, empty hook data, domain, Gateway contract, token, counterparty and
  /// balance checks applied on submission.
  /// Reverts on any failure rather than returning a non-magic selector, so a call that
  /// returns at all returns `IERC1271.isValidSignature.selector`.
  /// @param hash The EIP-712 digest the Gateway expects to have been signed
  /// @param signature abi.encode(bytes adminSignature, bytes burnIntentPayload), where
  /// `adminSignature` is an ECDSA signature over `hash` and `burnIntentPayload` is the
  /// burn intent that signature authorizes
  /// @return `IERC1271.isValidSignature.selector` when the signature is valid
  function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);

  /// @notice Returns the minimum delay between invests
  /// @return The minimum delay (in seconds)
  function getInvestMinDelay() external view returns (uint256);

  /// @notice Returns the timestamp of the most recent invest, or zero if never invested
  /// @dev The next {invest} is allowed once `getLastInvestTimestamp() + getInvestMinDelay()`
  /// has been reached
  /// @return The timestamp at which {invest} was last called
  function getLastInvestTimestamp() external view returns (uint256);

  /// @notice Returns the maximum fee payable to the Gateway operator on a withdrawal
  /// @dev Compared against the `maxFee` field of a burn intent, which bounds what the operator
  /// may charge. The Gateway wallet debits `value + fee`, so the fee is drawn from the invested
  /// balance on top of the amount withdrawn
  /// @return The maximum fee (in absolute terms)
  function getMaxFee() external view returns (uint256);

  /// @notice Returns the exposure cap (in absolute terms)
  /// @dev Can be set to zero to sunset ReinvestmentController
  /// @return The exposure cap
  function getExposureCapAbs() external view returns (uint256);

  /// @notice Returns the exposure cap (in BPS of supplied assets)
  /// @return The exposure cap
  function getExposureCapBps() external view returns (uint256);

  /// @notice Returns the minimum amount that must remain uninvested in the Hub
  /// @return The amount that must remain uninvested (in BPS)
  function getLiquidBufferBps() external view returns (uint256);
}
