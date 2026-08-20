// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {AccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {AttestationLib} from '@circle-gateway/src/lib/AttestationLib.sol';
import {BurnIntentLib} from '@circle-gateway/src/lib/BurnIntentLib.sol';
import {TransferSpecLib} from '@circle-gateway/src/lib/TransferSpecLib.sol';
import {AddressLib} from '@circle-gateway/src/lib/AddressLib.sol';
import {Cursor} from '@circle-gateway/src/lib/Cursor.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';

import {IGatewayMinter} from './interfaces/IGatewayMinter.sol';
import {IGatewayWallet} from './interfaces/IGatewayWallet.sol';
import {IReinvestmentController} from './interfaces/IReinvestmentController.sol';

contract ReinvestmentController is
  IReinvestmentController,
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable
{
  using SafeERC20 for IERC20;
  using TransferSpecLib for bytes29;
  using PercentageMath for uint256;

  /// @inheritdoc IReinvestmentController
  bytes32 public constant INVESTOR_ROLE = keccak256('INVESTOR_ROLE');

  /// @inheritdoc IReinvestmentController
  bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

  /// @inheritdoc IReinvestmentController
  IGatewayWallet public immutable GATEWAY_WALLET;

  /// @inheritdoc IReinvestmentController
  IGatewayMinter public immutable GATEWAY_MINTER;

  /// @inheritdoc IReinvestmentController
  IHub public immutable HUB;

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

  /// @dev Maximum amount of Hub funds that can be invested (in absolute terms)
  uint256 private _maxInvest;

  /// @dev Maximum amount of Hub funds that can be invested (in BPS)
  uint256 private _maxInvestBps;

  /// @dev Timestamp of the most recent pause, zeroed on unpause
  uint256 private _pausedAt;

  /// @dev Sets the immutable protocol addresses and locks the implementation. The
  /// resulting contract is inert until {initialize} is called on a proxy in front of it.
  /// @param gatewayWallet The address of the Circle Gateway wallet
  /// @param gatewayMinter The address of the Circle Gateway minter
  /// @param hub The address of the Hub
  /// @param usdc The address of the USDC token
  constructor(address gatewayWallet, address gatewayMinter, address hub, address usdc) {
    require(
      gatewayWallet != address(0) &&
        gatewayMinter != address(0) &&
        hub != address(0) &&
        usdc != address(0),
      InvalidZeroAddress()
    );

    GATEWAY_WALLET = IGatewayWallet(gatewayWallet);
    GATEWAY_MINTER = IGatewayMinter(gatewayMinter);
    HUB = IHub(hub);
    USDC = IERC20(usdc);
    ASSET_ID = IHub(hub).getAssetId(usdc);

    _disableInitializers();
  }

  /// @inheritdoc IReinvestmentController
  function initialize(
    address admin,
    uint256 depositTimelock_,
    uint256 maxInvest_,
    uint256 maxInvestBps_,
    uint256 bufferBps_
  ) external initializer {
    require(admin != address(0), InvalidZeroAddress());

    __AccessControl_init();
    __Pausable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(INVESTOR_ROLE, admin);
    _grantRole(PAUSER_ROLE, admin);

    _setDepositTimelock(depositTimelock_);
    _setGatewayTxLimit(10_000_000e6);
    _setMaxInvest(maxInvest_);
    _setMaxInvestBps(maxInvestBps_);
    _setBufferBps(bufferBps_);
  }

  /// @inheritdoc IReinvestmentController
  function invest(uint256 amount) external onlyRole(INVESTOR_ROLE) whenNotPaused {
    require(block.timestamp > _depositLastUpdate + _depositTimelock, DepositTimelock());
    require(amount > 0, InvalidAmount());
    require(amount <= _getInvestableAmount(), MaximumInvestAmountExceeded());

    _depositLastUpdate = block.timestamp;

    HUB.sweep(ASSET_ID, amount);
    USDC.forceApprove(address(GATEWAY_WALLET), amount);
    GATEWAY_WALLET.deposit(address(USDC), amount);

    emit Invested(amount);
  }

  /// @inheritdoc IReinvestmentController
  function divest(
    uint256 amount,
    bytes memory attestationPayload,
    bytes memory signature
  ) external onlyRole(INVESTOR_ROLE) whenNotPaused {
    require(amount > 0 && amount <= _gatewayTxLimit, InvalidAmount());
    require(amount <= HUB.getAssetSwept(ASSET_ID), InsufficientLiquidity());

    _validateAttestation(attestationPayload, amount);

    GATEWAY_MINTER.gatewayMint(attestationPayload, signature);
    USDC.safeTransfer(address(HUB), amount);
    HUB.reclaim(ASSET_ID, amount);

    emit Divested(amount);
  }

  /// @inheritdoc IReinvestmentController
  function initiateWithdrawal() external onlyRole(DEFAULT_ADMIN_ROLE) whenPaused {
    require(
      GATEWAY_WALLET.withdrawingBalance(address(USDC), address(this)) == 0,
      WithdrawalInProcess()
    );

    uint256 amount = GATEWAY_WALLET.availableBalance(address(USDC), address(this));

    require(amount > 0, InvalidAmount());
    require(amount <= HUB.getAssetSwept(ASSET_ID), InsufficientLiquidity());

    GATEWAY_WALLET.initiateWithdrawal(address(USDC), amount);

    emit WithdrawalInitiated(amount);
  }

  /// @inheritdoc IReinvestmentController
  function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 amount = GATEWAY_WALLET.withdrawingBalance(address(USDC), address(this));

    require(amount > 0, NoWithdrawalInProcess());

    GATEWAY_WALLET.withdraw(address(USDC));
    USDC.safeTransfer(address(HUB), amount);
    HUB.reclaim(ASSET_ID, amount);

    emit WithdrawalCompleted(amount);
  }

  /// @inheritdoc IReinvestmentController
  function pause() external onlyRole(PAUSER_ROLE) {
    _pausedAt = block.timestamp;
    _pause();
  }

  /// @inheritdoc IReinvestmentController
  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(
      GATEWAY_WALLET.withdrawingBalance(address(USDC), address(this)) == 0,
      WithdrawalInProcess()
    );

    _pausedAt = 0;
    _unpause();
  }

  /// @inheritdoc IReinvestmentController
  function setDepositTimelock(uint256 depositTimelock_) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setDepositTimelock(depositTimelock_);
  }

  /// @inheritdoc IReinvestmentController
  function setGatewayTxLimit(uint256 limit) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setGatewayTxLimit(limit);
  }

  /// @inheritdoc IReinvestmentController
  function setBufferBps(uint256 bufferBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setBufferBps(bufferBps_);
  }

  /// @inheritdoc IReinvestmentController
  function setMaxInvest(uint256 maxAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setMaxInvest(maxAmount);
  }

  /// @inheritdoc IReinvestmentController
  function setMaxInvestBps(uint256 maxBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setMaxInvestBps(maxBps);
  }

  /// @inheritdoc IReinvestmentController
  function getInvestableAmount() external view returns (uint256) {
    return _getInvestableAmount();
  }

  /// @inheritdoc IReinvestmentController
  function getInvestedAmount() external view returns (uint256) {
    return HUB.getAssetSwept(ASSET_ID);
  }

  /// @inheritdoc IReinvestmentController
  function depositTimelock() external view returns (uint256) {
    return _depositTimelock;
  }

  /// @inheritdoc IReinvestmentController
  function gatewayTxLimit() external view returns (uint256) {
    return _gatewayTxLimit;
  }

  /// @inheritdoc IReinvestmentController
  function maxInvest() external view returns (uint256) {
    return _maxInvest;
  }

  /// @inheritdoc IReinvestmentController
  function maxInvestBps() external view returns (uint256) {
    return _maxInvestBps;
  }

  function bufferBps() external view returns (uint256) {
    return _bufferBps;
  }

  /// @inheritdoc IReinvestmentController
  function pausedAt() external view returns (uint256) {
    return _pausedAt;
  }

  /// @inheritdoc IReinvestmentController
  function isValidSignature(
    bytes32 hash_,
    bytes memory signature
  ) external view whenNotPaused returns (bytes4) {
    (bytes memory adminSignature, bytes memory burnIntentPayload) = abi.decode(
      signature,
      (bytes, bytes)
    );

    bytes32 structHash = BurnIntentLib.getTypedDataHash(burnIntentPayload);
    bytes32 digest = MessageHashUtils.toTypedDataHash(GATEWAY_WALLET.domainSeparator(), structHash);
    require(digest == hash_, HashMismatch());

    address recoveredSigner = ECDSA.recover(digest, adminSignature);
    require(hasRole(INVESTOR_ROLE, recoveredSigner), InvalidSignature());

    _validateBurnIntent(burnIntentPayload);

    return IERC1271.isValidSignature.selector;
  }

  /// @dev Sets a new deposit timelock (in seconds)
  /// @param depositTimelock_ The new deposit timelock amount (in seconds)
  function _setDepositTimelock(uint256 depositTimelock_) internal {
    require(depositTimelock_ > 0, InvalidAmount());

    uint256 oldDepositTimelock = _depositTimelock;
    _depositTimelock = depositTimelock_;
    emit SetDepositTimelock(oldDepositTimelock, depositTimelock_);
  }

  /// @dev Sets the Circle Gateway's transaction limit
  /// @param limit The new transaction limit
  function _setGatewayTxLimit(uint256 limit) internal {
    uint256 oldLimit = _gatewayTxLimit;
    _gatewayTxLimit = limit;
    emit SetGatewayTxLimit(oldLimit, limit);
  }

  /// @dev Sets the minimum amount of buffer that must be left on the Hub uninvested (in BPS)
  /// @param buffer New buffer amount (in BPS)
  function _setBufferBps(uint256 buffer) internal {
    require(buffer > 0 && buffer < PercentageMath.PERCENTAGE_FACTOR, InvalidAmount());

    uint256 oldBufferBps = _bufferBps;
    _bufferBps = buffer;
    emit SetBufferBps(oldBufferBps, buffer);
  }

  /// @dev Sets the maximum amount that can be invested (in absolute terms)
  /// Can be set to 0 to sunset ReinvestmentController
  /// @param maxAmount The new maximum amount (in absolute terms)
  function _setMaxInvest(uint256 maxAmount) internal {
    uint256 oldMaxInvest = _maxInvest;
    _maxInvest = maxAmount;
    emit SetMaxInvest(oldMaxInvest, maxAmount);
  }

  /// @dev Sets the maximum amount that can be invested (in BPS)
  /// @dev maxBps New maximum amount (in BPS)
  function _setMaxInvestBps(uint256 maxBps) internal {
    require(maxBps > 0 && maxBps < PercentageMath.PERCENTAGE_FACTOR, InvalidAmount());

    uint256 oldMaxInvestBps = _maxInvestBps;
    _maxInvestBps = maxBps;
    emit SetMaxInvestBps(oldMaxInvestBps, maxBps);
  }

  /// @dev Calculates the amount currently available to invest
  function _getInvestableAmount() internal view returns (uint256) {
    uint256 supplied = HUB.getAddedAssets(ASSET_ID);
    uint256 idle = HUB.getAssetLiquidity(ASSET_ID);
    uint256 swept = HUB.getAssetSwept(ASSET_ID);
    uint256 buffer = supplied.percentMulUp(_bufferBps);

    if (idle <= buffer) return 0;

    uint256 freeIdle = idle - buffer;
    uint256 capLimit = Math.min(_maxInvest, supplied.percentMulDown(_maxInvestBps));
    uint256 capRoom = capLimit > swept ? capLimit - swept : 0;

    return Math.min(freeIdle, capRoom);
  }

  /// @dev Validates an attestation that was signed to withdraw funds
  /// @param attestationPayload Payload containing signed transfer specification
  /// @param amount Amount of token to withdraw
  function _validateAttestation(bytes memory attestationPayload, uint256 amount) internal view {
    Cursor memory cursor = AttestationLib.cursor(attestationPayload);
    require(cursor.numElements == 1, InvalidElementCount());

    bytes29 spec = AttestationLib.getTransferSpec(AttestationLib.next(cursor));
    _validateTransferSpec(address(USDC), spec);

    require(spec.getValue() == amount, InvalidMintAmount());
  }

  /// @dev Validates a withdrawal (BurnIntent) prior to signing an attestation
  /// @param burnIntentPayload Payload containing withdrawal specification
  function _validateBurnIntent(bytes memory burnIntentPayload) internal view {
    Cursor memory cursor = BurnIntentLib.cursor(burnIntentPayload);
    require(cursor.numElements == 1, InvalidElementCount());

    bytes29 spec = BurnIntentLib.getTransferSpec(BurnIntentLib.next(cursor));
    _validateTransferSpec(address(USDC), spec);

    require(spec.getValue() <= HUB.getAssetSwept(ASSET_ID), BurnIntentExceedsBalance());
  }

  /// @dev Validates the parameters of a withdrawal (BurnIntent)
  /// @param token Address of the token to withdraw
  /// @param spec The bytes29 representation of the burn intent
  function _validateTransferSpec(address token, bytes29 spec) internal view {
    bytes32 expectedToken = AddressLib._addressToBytes32(token);
    bytes32 self = AddressLib._addressToBytes32(address(this));

    require(spec.getSourceDomain() == spec.getDestinationDomain(), CrossChainTransferNotAllowed());
    require(spec.getSourceToken() == expectedToken, InvalidSourceToken());
    require(spec.getDestinationToken() == expectedToken, InvalidDestinationToken());
    require(spec.getSourceDepositor() == self, InvalidDepositor());
    require(spec.getDestinationRecipient() == self, InvalidRecipient());
    require(spec.getSourceSigner() == self, InvalidSigner());
    require(spec.getDestinationCaller() == self, InvalidDestinationCaller());
  }
}
