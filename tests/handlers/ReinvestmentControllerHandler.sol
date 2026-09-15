// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {CommonBase} from 'forge-std/Base.sol';
import {StdCheats} from 'forge-std/StdCheats.sol';
import {StdUtils} from 'forge-std/StdUtils.sol';
import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {BurnIntentLib} from '@circle-gateway/src/lib/BurnIntentLib.sol';
import {TransferSpec} from '@circle-gateway/src/lib/TransferSpec.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';

import {ReinvestmentController} from '../../src/ReinvestmentController.sol';

import {MockGatewayMinter} from '../mocks/MockGatewayMinter.sol';
import {MockGatewayWallet} from '../mocks/MockGatewayWallet.sol';
import {MockHub} from '../mocks/MockHub.sol';
import {MockUSDC} from '../mocks/MockUSDC.sol';
import {GatewayPayloads} from '../utils/GatewayPayloads.sol';

contract ReinvestmentControllerHandler is CommonBase, StdCheats, StdUtils, GatewayPayloads {
  error OnlySelf();

  ReinvestmentController internal immutable CONTROLLER;
  MockHub internal immutable HUB;
  MockGatewayWallet internal immutable WALLET;
  MockGatewayMinter internal immutable MINTER;
  MockUSDC internal immutable USDC;
  address internal immutable ADMIN;
  address internal immutable KEEPER;
  address internal immutable PAUSER;

  uint256 internal immutable KEEPER_PRIVATE_KEY;

  uint256 public fullExitFailures;
  uint256 public burnAfterDivestFailures;
  uint256 public successfulDivests;

  constructor(
    ReinvestmentController controller,
    MockHub hub,
    MockGatewayWallet wallet,
    MockUSDC usdc,
    address admin,
    address keeper,
    address pauser,
    uint256 keeperPrivateKey
  ) {
    CONTROLLER = controller;
    HUB = hub;
    WALLET = wallet;
    MINTER = MockGatewayMinter(address(controller.GATEWAY_MINTER()));
    USDC = usdc;
    ADMIN = admin;
    KEEPER = keeper;
    PAUSER = pauser;
    KEEPER_PRIVATE_KEY = keeperPrivateKey;

    _setPayloadContext(
      address(wallet),
      address(controller.GATEWAY_MINTER()),
      address(usdc),
      address(controller)
    );
  }

  function invest(uint256 amount) external {
    if (CONTROLLER.paused()) return;

    uint256 investable = CONTROLLER.getInvestableAmount();
    if (investable == 0) return;

    amount = bound(amount, 1, investable);

    vm.warp(block.timestamp + CONTROLLER.getInvestMinDelay() + 1);
    vm.prank(KEEPER);
    CONTROLLER.invest(amount);
  }

  function divest(uint256 amount, uint256 actualFee) external {
    if (CONTROLLER.paused()) return;

    uint256 maxFee = CONTROLLER.getMaxFee();
    uint256 swept = CONTROLLER.getInvestedAmount();
    if (swept <= maxFee) return;

    actualFee = bound(actualFee, 0, maxFee);

    uint256 available = WALLET.availableBalance(address(USDC), address(CONTROLLER));
    if (available <= actualFee) return;

    uint256 divestable = Math.min(swept - maxFee, available - actualFee);
    if (divestable == 0) return;

    amount = bound(amount, 1, divestable);

    _divestAndBurn(amount, actualFee, maxFee);
  }

  function _divestAndBurn(uint256 amount, uint256 actualFee, uint256 maxFee) internal {
    TransferSpec memory spec = _defaultTransferSpec(amount);
    bytes memory intent = _encodeBurnIntent(spec, maxFee);
    bytes32 digest = MessageHashUtils.toTypedDataHash(
      WALLET.domainSeparator(),
      BurnIntentLib.getTypedDataHash(intent)
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(KEEPER_PRIVATE_KEY, digest);
    bytes memory signature = abi.encode(abi.encodePacked(r, s, v), intent);
    require(CONTROLLER.isValidSignature(digest, signature) == IERC1271.isValidSignature.selector);

    vm.prank(KEEPER);
    CONTROLLER.divest(amount, _encodeAttestation(spec), 'signature');
    successfulDivests++;

    // Circle submits the source burn after the destination mint has finalized.
    try CONTROLLER.isValidSignature(digest, signature) returns (bytes4 result) {
      if (result != IERC1271.isValidSignature.selector) {
        burnAfterDivestFailures++;
        return;
      }
    } catch {
      burnAfterDivestFailures++;
      return;
    }
    vm.prank(address(MINTER));
    WALLET.gatewayBurn(address(USDC), address(CONTROLLER), amount, actualFee);
  }

  /// @dev A Gateway balance above what the Hub swept is a donation, or a fee {divest} pre-paid
  /// but Circle did not charge, and neither is reclaimable. Once swept reaches zero there is
  /// nothing left for the Hub to exit
  function fullExit(uint256 blocksAhead) external {
    uint256 available = WALLET.availableBalance(address(USDC), address(CONTROLLER));
    if (available == 0) return;
    if (CONTROLLER.getInvestedAmount() == 0) return;

    try this.executeFullExit(blocksAhead) {} catch {
      fullExitFailures++;
    }
  }

  function executeFullExit(uint256 blocksAhead) external {
    require(msg.sender == address(this), OnlySelf());

    vm.prank(PAUSER);
    CONTROLLER.pause();
    vm.prank(ADMIN);
    CONTROLLER.initiateWithdrawal();

    vm.roll(WALLET.withdrawalBlock(address(USDC), address(CONTROLLER)) + bound(blocksAhead, 0, 10));
    vm.prank(ADMIN);
    CONTROLLER.withdraw();
    vm.prank(ADMIN);
    CONTROLLER.unpause();
  }

  function supplyToHub(uint256 amount) external {
    HUB.add(bound(amount, 1, 10_000_000e6));
  }
}
