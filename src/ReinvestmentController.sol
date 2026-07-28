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
import {Cursor} from "@circle-gateway/src/lib/Cursor.sol";

import {IGateway} from "./interfaces/IGateway.sol";
import {IHub} from "./interfaces/IHub.sol";
import {IReinvestmentController} from "./interfaces/IReinvestmentController.sol";

contract ReinvestmentController is IReinvestmentController, AccessControl {
    using SafeERC20 for IERC20;
    using AttestationLib for Cursor;
    using AttestationLib for bytes29;
    using BurnIntentLib for Cursor;
    using BurnIntentLib for bytes29;
    using TransferSpecLib for bytes29;

    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");

    bytes4 public constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant SEVEN_DAYS_IN_BLOCKS = 50_400;

    IHub public immutable HUB;
    IGateway public immutable GATEWAY;
    IERC20 public immutable USDC;

    uint256 public immutable ASSET_ID;

    uint256 private _gatewayTxLimit = 10_000_000e6;
    uint256 private _maxDeploy;
    uint256 private _maxDeployBps;
    uint256 private _bufferBps;

    uint256 private _pendingWithdrawal;
    uint256 private _readyAtBlock;

    constructor(
        address admin,
        address hub,
        address gateway,
        address usdc,
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

        require(maxDeploy_ > 0, InvalidAmount());
        require(maxDeployBps_ < MAX_BPS, InvalidAmount());
        require(bufferBps_ > 0, InvalidAmount());

        HUB = IHub(hub);
        GATEWAY = IGateway(gateway);
        USDC = IERC20(usdc);
        ASSET_ID = IHub(hub).getAssetId(usdc);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(INVESTOR_ROLE, admin);

        _maxDeploy = maxDeploy_;
        _maxDeployBps = maxDeployBps_;
        _bufferBps = bufferBps_;
    }

    function invest(uint256 amount) external onlyRole(INVESTOR_ROLE) {
        require(amount > 0, InvalidAmount());
        require(amount <= _getMaxDeploy(), MaximumDeployAmountExceeded());

        HUB.sweep(ASSET_ID, amount);
        USDC.forceApprove(address(GATEWAY), amount);
        GATEWAY.deposit(address(USDC), amount);

        emit Invested(amount);
    }

    function divest(
        uint256 amount,
        bytes memory attestationPayload,
        bytes memory signature
    ) external onlyRole(INVESTOR_ROLE) {
        require(amount > 0 && amount < _gatewayTxLimit, InvalidAmount());
        require(amount <= HUB.getAssetSwept(ASSET_ID), InsufficientLiquidity());

        _validateAttestation(attestationPayload, amount);

        GATEWAY.gatewayMint(attestationPayload, signature);
        HUB.reclaim(ASSET_ID, amount);

        emit Divested(amount);
    }

    function initiateWithdrawal(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, InvalidAmount());
        require(amount <= HUB.getAssetSwept(ASSET_ID), InsufficientLiquidity());
        require(_pendingWithdrawal == 0, WithdrawalInProcess());

        _pendingWithdrawal = amount;
        _readyAtBlock = block.number + SEVEN_DAYS_IN_BLOCKS;

        GATEWAY.initiateWithdrawal(address(USDC), amount);

        emit WithdrawalInitiated(amount, _readyAtBlock);
    }

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(block.number >= _readyAtBlock, BlockDelayNotElapsed());
        uint256 amount = _pendingWithdrawal;

        _pendingWithdrawal = 0;

        GATEWAY.withdraw(address(USDC));
        USDC.safeTransfer(address(HUB), amount);
        HUB.reclaim(ASSET_ID, amount);

        emit WithdrawalCompleted(amount);
    }

    function setGatewayTxLimit(
        uint256 limit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldLimit = _gatewayTxLimit;
        _gatewayTxLimit = limit;
        emit SetGatewayTxLimit(oldLimit, limit);
    }

    function getDeployableAmount() external view returns (uint256) {
        return _getMaxDeploy();
    }

    function getReinvestedAmount() external view returns (uint256) {
        return HUB.getAssetSwept(ASSET_ID);
    }

    function gatewayTxLimit() external view returns (uint256) {
        return _gatewayTxLimit;
    }

    function maxDeploy() external view returns (uint256) {
        return _maxDeploy;
    }

    function maxDeployBps() external view returns (uint256) {
        return _maxDeployBps;
    }

    function bufferBps() external view returns (uint256) {
        return _bufferBps;
    }

    function pendingWithdrawal() external view returns (uint256) {
        return _pendingWithdrawal;
    }

    function readyAtBlock() external view returns (uint256) {
        return _readyAtBlock;
    }

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

    function _validateAttestation(
        bytes memory attestationPayload,
        uint256 amount
    ) internal view {
        uint256 toMint = 0;

        Cursor memory cursor = AttestationLib.cursor(attestationPayload);
        bytes29 attestation;

        while (!cursor.done) {
            attestation = cursor.next();

            bytes29 spec = attestation.getTransferSpec();
            _validateTransferSpec(address(USDC), spec);
            toMint += spec.getValue();
        }

        require(toMint == amount, InvalidMintAmount());
    }

    function _validateBurnIntent(bytes memory burnIntentPayload) internal view {
        uint256 toWithdraw = 0;

        Cursor memory cursor = BurnIntentLib.cursor(burnIntentPayload);
        bytes29 burnIntent;

        while (!cursor.done) {
            burnIntent = cursor.next();

            bytes29 spec = burnIntent.getTransferSpec();

            _validateTransferSpec(address(USDC), spec);
            toWithdraw += spec.getValue();
        }

        require(
            toWithdraw <= HUB.getAssetSwept(ASSET_ID),
            BurnIntentExceedsBalance()
        );
    }

    function _validateTransferSpec(address token, bytes29 spec) internal view {
        require(
            spec.getSourceDomain() == spec.getDestinationDomain(),
            CrossChainTransferNotAllowed()
        );
        require(spec.getSourceToken() == token, InvalidSourceToken());
        require(spec.getDestinationToken() == token, InvalidDestinationToken());
        require(spec.getSourceDepositor() == address(this), InvalidDepositor());
        require(
            spec.getDestinationRecipient() == address(this),
            InvalidRecipient()
        );
        require(spec.getSourceSigner() == address(this), InvalidSigner());
    }
}
