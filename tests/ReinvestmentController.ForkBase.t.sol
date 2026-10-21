// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {Test} from 'forge-std/Test.sol';

import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {AttestationLib} from '@circle-gateway/src/lib/AttestationLib.sol';
import {Attestation} from '@circle-gateway/src/lib/Attestations.sol';
import {BurnIntentLib} from '@circle-gateway/src/lib/BurnIntentLib.sol';
import {BurnIntent} from '@circle-gateway/src/lib/BurnIntents.sol';
import {TransferSpec} from '@circle-gateway/src/lib/TransferSpec.sol';
import {TransferSpecLib} from '@circle-gateway/src/lib/TransferSpecLib.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';

import {ReinvestmentController} from '../src/ReinvestmentController.sol';
import {IGatewayWallet} from '../src/interfaces/IGatewayWallet.sol';
import {IReinvestmentController} from '../src/interfaces/IReinvestmentController.sol';
import {GatewayPayloads} from './utils/GatewayPayloads.sol';

interface IAttestationSigners {
  function addAttestationSigner(address signer) external;
}

interface IMintsErrors {
  error InvalidAttestationSigner();
}

interface ITransferSpecHashes {
  error TransferSpecHashUsed(bytes32 transferSpecHash);
}

interface IBurns {
  error InvalidIntentSourceSignerAtIndex(uint32 index, address intentSigner, address actualSigner);

  function addBurnSigner(address signer) external;

  function gatewayBurn(bytes calldata calldataBytes, bytes calldata signature) external;
}

interface IContractSignatureSigners {
  function addContractSignatureSigner(address signer) external;

  function isContractSignatureSigner(address signer) external view returns (bool);
}

interface IContractSignersAllowlist {
  function isAllowlistedContractSigner(address contractAddr) external view returns (bool);
}

/// @dev Forks mainnet against the live Gateway. Burns follow Gateway's TEE-backed ERC-1271 flow:
/// the TEE evaluates {isValidSignature} with an eth_call against a quorum of RPCs, signs the burn
/// intent with its own key if the check passed, and the Gateway accepts that signature at burn
/// time without calling back into the controller. The controller is never allowlisted as a
/// contract signer, so the on-chain ERC-1271 fallback is unreachable.
abstract contract ReinvestmentControllerForkBase is Test, GatewayPayloads {
  struct Authorization {
    uint256 amount;
    bytes32 transferSpecHash;
    bytes intent;
    bytes32 digest;
    bytes keeperSignature;
    bytes teeSignature;
    bytes attestation;
    bytes attestationSignature;
  }

  uint256 internal constant FORK_BLOCK = 25_796_690;

  // https://etherscan.io/address/0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE
  address public constant GATEWAY_WALLET = 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;

  // https://etherscan.io/address/0x2222222d7164433c4C09B0b0D809a9b52C04C205
  address public constant GATEWAY_MINTER = 0x2222222d7164433c4C09B0b0D809a9b52C04C205;

  // https://etherscan.io/address/0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9
  address public constant HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;

  // https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  uint256 internal constant INVEST_MIN_DELAY = 1 days;
  uint256 internal constant EXPOSURE_CAP_ABS = 10_000_000e6;
  uint256 internal constant EXPOSURE_CAP_BPS = 8_000;
  uint256 internal constant LIQUID_BUFFER_BPS = 1_000;
  uint256 internal constant MAX_FEE = 1e6;
  uint256 internal constant FEE_FUNDING = 1_000e6;

  /// @dev Blocks an authorization's burn intent and attestation stay valid for. Longer than the
  /// Gateway's withdrawal delay, so a settlement can straddle a full on-chain withdrawal
  uint256 internal constant AUTHORIZATION_VALIDITY = 100_000;

  address internal admin = makeAddr('admin');
  address internal proxyAdminOwner = makeAddr('proxyAdminOwner');
  address internal alice = makeAddr('alice');

  address internal keeper;
  uint256 internal keeperPrivateKey;
  address internal circleSigner;
  uint256 internal circleSignerPrivateKey;
  address internal burnSigner;
  uint256 internal burnSignerPrivateKey;
  address internal teeSigner;
  uint256 internal teeSignerPrivateKey;

  ReinvestmentController internal controller;
  uint256 internal assetId;

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('mainnet'), FORK_BLOCK);

    (keeper, keeperPrivateKey) = makeAddrAndKey('keeper');
    (circleSigner, circleSignerPrivateKey) = makeAddrAndKey('circleSigner');
    (burnSigner, burnSignerPrivateKey) = makeAddrAndKey('burnSigner');
    (teeSigner, teeSignerPrivateKey) = makeAddrAndKey('teeSigner');

    controller = ReinvestmentController(
      address(
        new TransparentUpgradeableProxy(
          address(new ReinvestmentController(GATEWAY_WALLET, GATEWAY_MINTER, HUB, USDC)),
          proxyAdminOwner,
          abi.encodeCall(
            IReinvestmentController.initialize,
            (
              admin,
              INVEST_MIN_DELAY,
              EXPOSURE_CAP_ABS,
              EXPOSURE_CAP_BPS,
              MAX_FEE,
              LIQUID_BUFFER_BPS
            )
          )
        )
      )
    );

    deal(USDC, keeper, FEE_FUNDING);
    vm.prank(keeper);
    IERC20(USDC).approve(address(controller), type(uint256).max);

    assetId = controller.ASSET_ID();
    _setPayloadContext(GATEWAY_WALLET, GATEWAY_MINTER, USDC, address(controller));

    bytes32 keeperRole = controller.KEEPER_ROLE();
    vm.prank(admin);
    controller.grantRole(keeperRole, keeper);

    _pointHubAtTheController();
    _allowCircleSigner();
    _allowBurnSigner();
    _allowTeeSigner();

    vm.warp(block.timestamp + INVEST_MIN_DELAY + 1);
  }

  function _investAll() internal returns (uint256 invested) {
    invested = controller.getInvestableAmount();
    vm.prank(keeper);
    controller.invest(invested);
  }

  /// @dev Models Circle's TEE authorizing a burn intent: the quorum's eth_call to
  /// {isValidSignature} must pass against current state, after which the TEE signs the digest
  /// with its own key and Circle attests the same transfer spec. Nothing is recorded on-chain
  function _authorize(
    uint256 amount,
    bytes32 salt
  ) internal view returns (Authorization memory auth) {
    TransferSpec memory spec = _defaultTransferSpec(amount);
    spec.salt = salt;
    uint256 maxBlockHeight = block.number + AUTHORIZATION_VALIDITY;

    auth.amount = amount;
    auth.transferSpecHash = keccak256(TransferSpecLib.encodeTransferSpec(spec));
    auth.intent = BurnIntentLib.encodeBurnIntent(
      BurnIntent({maxBlockHeight: maxBlockHeight, maxFee: controller.getMaxFee(), spec: spec})
    );
    (auth.digest, auth.keeperSignature) = _signBurnIntent(keeperPrivateKey, auth.intent);

    assertEq(
      controller.isValidSignature(auth.digest, auth.keeperSignature),
      IERC1271.isValidSignature.selector
    );

    auth.teeSignature = _sign(teeSignerPrivateKey, auth.digest);
    auth.attestation = AttestationLib.encodeAttestation(
      Attestation({maxBlockHeight: maxBlockHeight, spec: spec})
    );
    auth.attestationSignature = _sign(
      circleSignerPrivateKey,
      MessageHashUtils.toEthSignedMessageHash(keccak256(auth.attestation))
    );
  }

  /// @dev Submits the burn as Circle's operator does, carrying the TEE's signature. Circle only
  /// burns after observing the intent's mint in a finalized block, so call this after {_mint}
  function _teeBurn(Authorization memory auth, uint256 fee) internal {
    _gatewayBurn(auth.intent, auth.teeSignature, fee);
  }

  /// @dev Mints the authorization's attestation through {divest}
  function _mint(Authorization memory auth, address caller) internal {
    vm.prank(caller);
    controller.divest(auth.amount, auth.attestation, auth.attestationSignature);
  }

  /// @dev Settles an authorization in the order Circle guarantees: mint, then burn
  function _settle(Authorization memory auth, address caller, uint256 fee) internal {
    _mint(auth, caller);
    _teeBurn(auth, fee);
  }

  /// @dev Asserts that nothing from here to the end of the test calls the controller's
  /// ERC-1271 check, so any fresh check a test makes must come before this
  function _expectNoSignatureRecheck() internal {
    vm.expectCall(
      address(controller),
      abi.encodeWithSelector(IERC1271.isValidSignature.selector),
      0
    );
  }

  /// @dev Reproduces the transaction Circle's operator sends on the source domain. The Gateway
  /// debits `amount + fee`, burning what it can if the balance falls short
  function _gatewayBurn(bytes memory intent, bytes memory intentSignature, uint256 fee) internal {
    bytes[] memory intents = new bytes[](1);
    intents[0] = intent;

    bytes[] memory signatures = new bytes[](1);
    signatures[0] = intentSignature;

    uint256[][] memory fees = new uint256[][](1);
    fees[0] = new uint256[](1);
    fees[0][0] = fee;

    bytes memory calldataBytes = abi.encode(intents, signatures, fees);
    IBurns(GATEWAY_WALLET).gatewayBurn(
      calldataBytes,
      _sign(burnSignerPrivateKey, MessageHashUtils.toEthSignedMessageHash(keccak256(calldataBytes)))
    );
  }

  function _attest(
    uint256 amount
  ) internal view returns (bytes memory attestation, bytes memory signature) {
    attestation = _encodeAttestation(_defaultTransferSpec(amount));
    signature = _sign(
      circleSignerPrivateKey,
      MessageHashUtils.toEthSignedMessageHash(keccak256(attestation))
    );
  }

  function _signBurnIntent(
    uint256 privateKey,
    bytes memory burnIntentPayload
  ) internal view returns (bytes32 digest, bytes memory signature) {
    digest = MessageHashUtils.toTypedDataHash(
      IGatewayWallet(GATEWAY_WALLET).domainSeparator(),
      BurnIntentLib.getTypedDataHash(burnIntentPayload)
    );
    signature = abi.encode(_sign(privateKey, digest), burnIntentPayload);
  }

  function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    return abi.encodePacked(r, s, v);
  }

  function _swept() internal view returns (uint256) {
    return IHub(HUB).getAssetSwept(assetId);
  }

  function _available() internal view returns (uint256) {
    return IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller));
  }

  function _withdrawing() internal view returns (uint256) {
    return IGatewayWallet(GATEWAY_WALLET).withdrawingBalance(USDC, address(controller));
  }

  /// @dev Listing a reinvestment controller is an access-managed governance action, so the
  /// authority is short-circuited for the single configuration call and then restored.
  function _pointHubAtTheController() internal {
    _pointHubAt(address(controller));
  }

  function _pointHubAt(address reinvestmentController) internal {
    IHub.AssetConfig memory config = IHub(HUB).getAssetConfig(assetId);
    config.reinvestmentController = reinvestmentController;

    vm.mockCall(
      IHub(HUB).authority(),
      abi.encodeWithSignature('canCall(address,address,bytes4)'),
      abi.encode(true, uint32(0))
    );
    vm.prank(admin);
    IHub(HUB).updateAssetConfig(assetId, config, '');
    vm.clearMockedCalls();
  }

  function _allowCircleSigner() internal {
    vm.prank(Ownable(GATEWAY_MINTER).owner());
    IAttestationSigners(GATEWAY_MINTER).addAttestationSigner(circleSigner);
  }

  function _allowBurnSigner() internal {
    vm.prank(Ownable(GATEWAY_WALLET).owner());
    IBurns(GATEWAY_WALLET).addBurnSigner(burnSigner);
  }

  /// @dev Registers a stand-in for Circle's TEE, whose ECDSA signature the Gateway accepts as
  /// proof that the controller's ERC-1271 check passed
  function _allowTeeSigner() internal {
    vm.prank(Ownable(GATEWAY_WALLET).owner());
    IContractSignatureSigners(GATEWAY_WALLET).addContractSignatureSigner(teeSigner);
  }
}
