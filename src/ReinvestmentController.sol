// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AttestationLib} from "@circle-gateway/src/lib/AttestationLib.sol";
import {BurnIntentLib} from "@circle-gateway/src/lib/BurnIntentLib.sol";
import {TransferSpecLib} from "@circle-gateway/src/lib/TransferSpecLib.sol";
import {AddressLib} from "@circle-gateway/src/lib/AddressLib.sol";
import {Cursor} from "@circle-gateway/src/lib/Cursor.sol";

import {IGateway} from "./interfaces/IGateway.sol";
import {IHub} from "./interfaces/IHub.sol";
import {IReinvestmentController} from "./interfaces/IReinvestmentController.sol";

contract ReinvestmentController is IReinvestmentController, AccessControl {
    using SafeERC20 for IERC20;
    using TransferSpecLib for bytes29;

    /// @inheritdoc IReinvestmentController
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");

    /// @inheritdoc IReinvestmentController
    bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// @dev Maximum value of BPS representing 100%
    uint256 private constant MAX_BPS = 10_000;

    /// @dev Seconds until on-chain withdrawal can be finalized
    uint256 private constant SEVEN_DAYS_IN_BLOCKS = 7 days;

    /// @inheritdoc IReinvestmentController
    IHub public immutable HUB;

    /// @inheritdoc IReinvestmentController
    IGateway public immutable GATEWAY;

    /// @inheritdoc IReinvestmentController
    IERC20 public immutable USDC;

    /// @inheritdoc IReinvestmentController
    uint256 public immutable ASSET_ID;

    /// @dev Time before a new deposit can be performed (in seconds)
    uint256 private _depositTimelock;

    /// @dev Timestamp of last deposit
    uint256 private _depositLastUpdate;

    /// @dev Transaction size limit imposed by Gateway for instant withdrawals
    uint256 private _gatewayTxLimit;

    /// @dev Buffer of uninvested funds on Hub (in BPS)
    uint256 private _bufferBps;

    /// @dev Maximum amount of Hub funds that can be reinvested (in absolute terms)
    uint256 private _maxDeploy;

    /// @dev Maximum amount of Hub funds that can be reinvested (in BPS)
    uint256 private _maxDeployBps;

    /// @dev Pending amount to be withdrawn on-chain
    uint256 private _pendingWithdrawalAmount;

    /// @dev Timestamp when pending withdrawal can be finalized
    uint256 private _readyAtBlock;

    constructor(
        address admin,
        address hub,
        address gateway,
        address usdc,
        uint256 depositTimelock_,
        uint256 maxDeploy_,
        uint256 maxDeployBps_,
        uint256 bufferBps_
    ) {
        require(
            admin != address(0) &&
                hub != address(0) &&
                gateway != address(0) &&
                usdc != address(0),
            InvalidZeroAddress()
        );

        HUB = IHub(hub);
        GATEWAY = IGateway(gateway);
        USDC = IERC20(usdc);
        ASSET_ID = IHub(hub).getAssetId(usdc);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(INVESTOR_ROLE, admin);

        _setDepositTimelock(depositTimelock_);
        _setGatewayTxLimit(10_000_000e6);
        _setMaxDeploy(maxDeploy_);
        _setMaxDeployBps(maxDeployBps_);
        _setBufferBps(bufferBps_);
    }

    /// @inheritdoc IReinvestmentController
    function invest(uint256 amount) external onlyRole(INVESTOR_ROLE) {
        require(
            block.timestamp > _depositLastUpdate + _depositTimelock,
            DepositTimelock()
        );
        require(amount > 0, InvalidAmount());
        require(amount <= _getMaxDeploy(), MaximumDeployAmountExceeded());

        _depositLastUpdate = block.timestamp;

        HUB.sweep(ASSET_ID, amount);
        USDC.forceApprove(address(GATEWAY), amount);
        GATEWAY.deposit(address(USDC), amount);

        emit Invested(amount);
    }

    /// @inheritdoc IReinvestmentController
    function divest(
        uint256 amount,
        bytes memory attestationPayload,
        bytes memory signature
    ) external onlyRole(INVESTOR_ROLE) {
        require(amount > 0 && amount <= _gatewayTxLimit, InvalidAmount());
        require(amount <= HUB.getAssetSwept(ASSET_ID), InsufficientLiquidity());

        _validateAttestation(attestationPayload, amount);

        GATEWAY.gatewayMint(attestationPayload, signature);
        USDC.safeTransfer(address(HUB), amount);
        HUB.reclaim(ASSET_ID, amount);

        emit Divested(amount);
    }

    /// @inheritdoc IReinvestmentController
    function initiateWithdrawal(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, InvalidAmount());
        require(amount <= HUB.getAssetSwept(ASSET_ID), InsufficientLiquidity());
        require(_pendingWithdrawalAmount == 0, WithdrawalInProcess());

        _pendingWithdrawalAmount = amount;
        _readyAtBlock = block.number + SEVEN_DAYS_IN_BLOCKS;

        GATEWAY.initiateWithdrawal(address(USDC), amount);

        emit WithdrawalInitiated(amount, _readyAtBlock);
    }

    /// @inheritdoc IReinvestmentController
    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = _pendingWithdrawalAmount;

        require(amount > 0, NoWithdrawalInProcess());
        require(block.number >= _readyAtBlock, BlockDelayNotElapsed());

        _pendingWithdrawalAmount = 0;
        _readyAtBlock = 0;

        GATEWAY.withdraw(address(USDC));
        USDC.safeTransfer(address(HUB), amount);
        HUB.reclaim(ASSET_ID, amount);

        emit WithdrawalCompleted(amount);
    }

    /// @inheritdoc IReinvestmentController
    function setDepositTimelock(
        uint256 depositTimelock
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDepositTimelock(depositTimelock);
    }

    /// @inheritdoc IReinvestmentController
    function setGatewayTxLimit(
        uint256 limit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setGatewayTxLimit(limit);
    }

    /// @inheritdoc IReinvestmentController
    function setBufferBps(
        uint256 bufferBps_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBufferBps(bufferBps_);
    }

    /// @inheritdoc IReinvestmentController
    function setMaxDeploy(
        uint256 maxDeploy_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxDeploy(maxDeploy_);
    }

    /// @inheritdoc IReinvestmentController
    function setMaxDeployBps(
        uint256 maxDeployBps_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxDeployBps(maxDeployBps_);
    }

    /// @inheritdoc IReinvestmentController
    function getDeployableAmount() external view returns (uint256) {
        return _getMaxDeploy();
    }

    /// @inheritdoc IReinvestmentController
    function getReinvestedAmount() external view returns (uint256) {
        return HUB.getAssetSwept(ASSET_ID);
    }

    /// @inheritdoc IReinvestmentController
    function gatewayTxLimit() external view returns (uint256) {
        return _gatewayTxLimit;
    }

    /// @inheritdoc IReinvestmentController
    function maxDeploy() external view returns (uint256) {
        return _maxDeploy;
    }

    /// @inheritdoc IReinvestmentController
    function maxDeployBps() external view returns (uint256) {
        return _maxDeployBps;
    }

    function bufferBps() external view returns (uint256) {
        return _bufferBps;
    }

    /// @inheritdoc IReinvestmentController
    function pendingWithdrawalAmount() external view returns (uint256) {
        return _pendingWithdrawalAmount;
    }

    /// @inheritdoc IReinvestmentController
    function readyAtBlock() external view returns (uint256) {
        return _readyAtBlock;
    }

    /// @inheritdoc IReinvestmentController
    function isValidSignature(
        bytes32 hash_,
        bytes memory signature
    ) external view returns (bytes4) {
        (bytes memory adminSignature, bytes memory burnIntentPayload) = abi
            .decode(signature, (bytes, bytes));

        bytes32 structHash = BurnIntentLib.getTypedDataHash(burnIntentPayload);
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            GATEWAY.domainSeparator(),
            structHash
        );
        require(digest == hash_, HashMismatch());

        address recoveredSigner = ECDSA.recover(digest, adminSignature);
        require(hasRole(INVESTOR_ROLE, recoveredSigner), InvalidSignature());

        _validateBurnIntent(burnIntentPayload);

        return ERC1271_MAGIC_VALUE;
    }

    /// @dev Sets a new deposit timelock (in seconds)
    /// @param depositTimelock The new deposit timelock amount (in seconds)
    function _setDepositTimelock(uint256 depositTimelock) internal {
        require(depositTimelock > 0, InvalidAmount());

        uint256 oldDepositTimelock = _depositTimelock;
        _depositTimelock = depositTimelock;
        emit SetDepositTimelock(oldDepositTimelock, depositTimelock);
    }

    /// @dev Sets the Cricle Gateway's transaction limit
    /// @param limit The new transaction limit
    function _setGatewayTxLimit(uint256 limit) internal {
        uint256 oldLimit = _gatewayTxLimit;
        _gatewayTxLimit = limit;
        emit SetGatewayTxLimit(oldLimit, limit);
    }

    /// @dev Sets the maximum amount of invesetable
    /// Can be set to 0 to sunset ReinvestmentController
    /// @param maxAmount The new maximum amount (in absolute terms)
    function _setMaxDeploy(uint256 maxAmount) internal {
        uint256 oldMaxDeploy = _maxDeploy;
        _maxDeploy = maxAmount;
        emit SetMaxDeploy(oldMaxDeploy, maxAmount);
    }

    /// @dev Sets the maximum amount that can be reinvested (in BPS)
    /// @dev maxBps New maximum amount (in BPS)
    function _setMaxDeployBps(uint256 maxBps) internal {
        require(maxBps > 0 && maxBps < MAX_BPS, InvalidAmount());

        uint256 oldMaxDeployBps = _maxDeployBps;
        _maxDeployBps = maxBps;
        emit SetMaxDeployBps(oldMaxDeployBps, maxBps);
    }

    /// @dev Sets the minimum amount of buffer that must be left on the Hub uninvested (in BPS)
    /// @param buffer New buffer amount (in BPS)
    function _setBufferBps(uint256 buffer) internal {
        require(buffer > 0 && buffer < MAX_BPS, InvalidAmount());

        uint256 oldBufferBps = _bufferBps;
        _bufferBps = buffer;
        emit SetBufferBps(oldBufferBps, buffer);
    }

    /// @dev Calculates the maximum amount available to reinvest
    function _getMaxDeploy() internal view returns (uint256) {
        uint256 supplied = HUB.getAddedAssets(ASSET_ID);
        uint256 idle = HUB.getAssetLiquidity(ASSET_ID);
        uint256 swept = HUB.getAssetSwept(ASSET_ID);
        uint256 buffer = (supplied * _bufferBps) / MAX_BPS;

        if (idle <= buffer) return 0;

        uint256 freeIdle = idle - buffer;
        uint256 capLimit = Math.min(
            _maxDeploy,
            (supplied * _maxDeployBps) / MAX_BPS
        );
        uint256 capRoom = capLimit > swept ? capLimit - swept : 0;

        return Math.min(freeIdle, capRoom);
    }

    /// @dev Validates an attestation that was signed to withdraw funds
    /// @param attestationPayload Payload containing signed transfer specification
    /// @param amount Amount of token to withdraw
    function _validateAttestation(
        bytes memory attestationPayload,
        uint256 amount
    ) internal view {
        uint256 toMint = 0;

        Cursor memory cursor = AttestationLib.cursor(attestationPayload);
        bytes29 attestation;

        while (!cursor.done) {
            attestation = AttestationLib.next(cursor);

            bytes29 spec = AttestationLib.getTransferSpec(attestation);
            _validateTransferSpec(address(USDC), spec);
            toMint += spec.getValue();
        }

        require(toMint == amount, InvalidMintAmount());
    }

    /// @dev Validates a withdrawal (BurnIntent) prior to signing an attestation
    /// @param burnIntentPayload Payload containing withdrawal specification
    function _validateBurnIntent(bytes memory burnIntentPayload) internal view {
        uint256 toWithdraw = 0;

        Cursor memory cursor = BurnIntentLib.cursor(burnIntentPayload);
        bytes29 burnIntent;

        while (!cursor.done) {
            burnIntent = BurnIntentLib.next(cursor);

            bytes29 spec = BurnIntentLib.getTransferSpec(burnIntent);

            _validateTransferSpec(address(USDC), spec);
            toWithdraw += spec.getValue();
        }

        require(
            toWithdraw <= HUB.getAssetSwept(ASSET_ID),
            BurnIntentExceedsBalance()
        );
    }

    /// @dev Validates the parameters of a withdrawal (BurnIntent)
    /// @param token Address of the token to withdraw
    /// @param spec The bytes29 representation of the burn intent
    function _validateTransferSpec(address token, bytes29 spec) internal view {
        bytes32 expectedToken = AddressLib._addressToBytes32(token);
        bytes32 self = AddressLib._addressToBytes32(address(this));

        require(
            spec.getSourceDomain() == spec.getDestinationDomain(),
            CrossChainTransferNotAllowed()
        );
        require(spec.getSourceToken() == expectedToken, InvalidSourceToken());
        require(
            spec.getDestinationToken() == expectedToken,
            InvalidDestinationToken()
        );
        require(spec.getSourceDepositor() == self, InvalidDepositor());
        require(spec.getDestinationRecipient() == self, InvalidRecipient());
        require(spec.getSourceSigner() == self, InvalidSigner());
    }
}
