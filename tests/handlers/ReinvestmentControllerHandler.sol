// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {CommonBase} from 'forge-std/Base.sol';
import {StdCheats} from 'forge-std/StdCheats.sol';
import {StdUtils} from 'forge-std/StdUtils.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';

import {ReinvestmentController} from '../../src/ReinvestmentController.sol';

import {MockGatewayWallet} from '../mocks/MockGatewayWallet.sol';
import {MockHub} from '../mocks/MockHub.sol';
import {MockUSDC} from '../mocks/MockUSDC.sol';
import {GatewayPayloads} from '../utils/GatewayPayloads.sol';

contract ReinvestmentControllerHandler is CommonBase, StdCheats, StdUtils, GatewayPayloads {
  uint256 internal constant PERCENTAGE_FACTOR = 100_00;

  ReinvestmentController internal immutable CONTROLLER;
  MockHub internal immutable HUB;
  MockGatewayWallet internal immutable WALLET;
  MockUSDC internal immutable USDC;
  address internal immutable ADMIN;
  address internal immutable KEEPER;
  address internal immutable PAUSER;

  uint256 public investCalls;
  uint256 public divestCalls;
  uint256 public initiateWithdrawalCalls;
  uint256 public withdrawCalls;
  uint256 public totalInvested;
  uint256 public totalDivested;

  constructor(
    ReinvestmentController controller,
    MockHub hub,
    MockGatewayWallet wallet,
    MockUSDC usdc,
    address admin,
    address keeper,
    address pauser
  ) {
    CONTROLLER = controller;
    HUB = hub;
    WALLET = wallet;
    USDC = usdc;
    ADMIN = admin;
    KEEPER = keeper;
    PAUSER = pauser;

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

    investCalls++;
    totalInvested += amount;
  }

  function divest(uint256 amount) external {
    if (CONTROLLER.paused()) return;

    uint256 divestable = Math.min(
      CONTROLLER.getInvestedAmount(),
      WALLET.availableBalance(address(USDC), address(CONTROLLER))
    );
    if (divestable == 0) return;

    amount = bound(amount, 1, divestable);

    vm.prank(KEEPER);
    CONTROLLER.divest(amount, _encodeAttestation(_defaultTransferSpec(amount)), 'signature');

    divestCalls++;
    totalDivested += amount;
  }

  function pause() external {
    if (CONTROLLER.paused()) return;

    vm.prank(PAUSER);
    CONTROLLER.pause();
  }

  function unpause() external {
    if (!CONTROLLER.paused()) return;
    if (WALLET.withdrawingBalance(address(USDC), address(CONTROLLER)) > 0) return;

    vm.prank(ADMIN);
    CONTROLLER.unpause();
  }

  function initiateWithdrawal() external {
    if (!CONTROLLER.paused()) return;
    if (WALLET.withdrawingBalance(address(USDC), address(CONTROLLER)) > 0) return;

    uint256 available = WALLET.availableBalance(address(USDC), address(CONTROLLER));
    if (available == 0 || available > CONTROLLER.getInvestedAmount()) return;

    vm.prank(ADMIN);
    CONTROLLER.initiateWithdrawal();

    initiateWithdrawalCalls++;
  }

  function withdraw(uint256 blocksAhead) external {
    if (WALLET.withdrawingBalance(address(USDC), address(CONTROLLER)) == 0) return;

    vm.roll(WALLET.withdrawalBlock(address(USDC), address(CONTROLLER)) + bound(blocksAhead, 0, 10));
    vm.prank(ADMIN);
    CONTROLLER.withdraw();

    withdrawCalls++;
  }

  function setBufferBps(uint256 bufferBps) external {
    vm.prank(ADMIN);
    CONTROLLER.setBufferBps(bound(bufferBps, 1, PERCENTAGE_FACTOR - 1));
  }

  function setMaxInvest(uint256 maxInvest) external {
    vm.prank(ADMIN);
    CONTROLLER.setMaxInvest(bound(maxInvest, 0, type(uint96).max));
  }

  function setMaxInvestBps(uint256 maxInvestBps) external {
    vm.prank(ADMIN);
    CONTROLLER.setMaxInvestBps(bound(maxInvestBps, 1, PERCENTAGE_FACTOR - 1));
  }

  function setInvestMinDelay(uint256 investMinDelay) external {
    vm.prank(ADMIN);
    CONTROLLER.setInvestMinDelay(bound(investMinDelay, 1, 30 days));
  }

  function supplyToHub(uint256 amount) external {
    HUB.add(bound(amount, 1, 10_000_000e6));
  }
}
