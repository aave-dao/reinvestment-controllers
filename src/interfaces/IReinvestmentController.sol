// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IGatewayMinter} from "./IGatewayMinter.sol";
import {IGatewayWallet} from "./IGatewayWallet.sol";
import {IHub} from "./IHub.sol";

interface IReinvestmentController {
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

    /// @dev Invalid depositor provided in transfer specification
    error InvalidDepositor();

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
    event Divested(uint256 amount);

    /// @dev Emitted when the Gateway transaction limit is updated
    /// @param oldLimit The old transaction limit
    /// @param limit The new transaction limit
    event SetGatewayTxLimit(uint256 oldLimit, uint256 limit);

    /// @dev Emitted when the deposit timelock is updated
    /// @param oldDepositTimelock The old deposit timelock
    /// @param depositTimelock The new deposit timelock
    event SetDepositTimelock(uint256 oldDepositTimelock, uint256 depositTimelock);

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
    /// @param bufferBps_ The initial minimum uninvested buffer (in BPS)
    function initialize(
        address admin,
        uint256 depositTimelock_,
        uint256 maxInvest_,
        uint256 maxInvestBps_,
        uint256 bufferBps_
    ) external;

    /// @notice Invests amount of funds into USDC Gateway
    /// @dev Amount can be greater than Gateway transaction limit
    /// @param amount Amount of USDC to invest
    function invest(uint256 amount) external;

    /// @notice Divests amount of funds from USDC Gateway
    /// @dev Cannot exceeds Gateway transaction limit
    /// @param amount The amount of funds to withdraw
    /// @param attestationPayload The specification of the withdrawal
    /// @param signature The signature that validates attestation was originated by authorized entity
    function divest(uint256 amount, bytes calldata attestationPayload, bytes calldata signature) external;

    /// @notice Initiates an on-chain withdrawal
    /// @dev Amount can be greater than Gateway transaction limit
    /// @param amount The amount to withdraw
    function initiateWithdrawal(uint256 amount) external;

    /// @notice Finalizes a pending withdrawal after required time has elapsed
    function withdraw() external;

    /// @notice Sets a new deposit timelock (in seconds)
    /// @param depositTimelock_ The new deposit timelock amount (in seconds)
    function setDepositTimelock(uint256 depositTimelock_) external;

    /// @notice Sets the Circle Gateway's transaction limit
    /// @param limit The new transaction limit
    function setGatewayTxLimit(uint256 limit) external;

    /// @dev Sets the minimum amount of buffer that must be left on the Hub uninvested (in BPS)
    /// @param buffer New buffer amount (in BPS)
    function setBufferBps(uint256 buffer) external;

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

    /// @notice Returns the ERC-1271 magic value returned by a successful isValidSignature call
    /// @return The bytes4 magic value (0x1626ba7e)
    function ERC1271_MAGIC_VALUE() external view returns (bytes4);

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

    /// @notice Validates an ERC-1271 signature over a Circle Gateway burn intent
    /// @dev Called by the Gateway to confirm this contract authorized a withdrawal, as the
    /// contract is the depositor, recipient and signer of every burn intent it submits.
    /// The burn intent is re-hashed against the Gateway's domain separator and must match
    /// `hash`, the recovered signer must hold INVESTOR_ROLE, and the intent itself must pass
    /// the same-chain, token, counterparty and balance checks applied on submission.
    /// Reverts on any failure rather than returning a non-magic selector, so a call that
    /// returns at all returns ERC1271_MAGIC_VALUE.
    /// @param hash The EIP-712 digest the Gateway expects to have been signed
    /// @param signature abi.encode(bytes adminSignature, bytes burnIntentPayload), where
    /// `adminSignature` is an ECDSA signature over `hash` and `burnIntentPayload` is the
    /// burn intent that signature authorizes
    /// @return ERC1271_MAGIC_VALUE when the signature is valid
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);

    /// @notice Returns the deposit timelock
    /// @return The timelock (in seconds)
    function depositTimelock() external view returns (uint256);

    /// @notice Returns the Circle USDC Gateway transaction limit for instant withdrawals
    /// @return The transaction size limit
    function gatewayTxLimit() external view returns (uint256);

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

    /// @notice Returns the current amount pending an on-chain withdrawal
    /// @return The amount is pending withdrawal
    function pendingWithdrawalAmount() external view returns (uint256);
}
