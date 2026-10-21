// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerGetInvestedAmountTest is ReinvestmentControllerTestBase {
  function test_getInvestedAmount() public view {
    assertEq(controller.getInvestedAmount(), 0);
  }

  function test_getInvestedAmount(uint256 swept) public {
    swept = bound(swept, 0, type(uint96).max);
    hub.setAccounting(SUPPLIED, SUPPLIED, swept);

    assertEq(controller.getInvestedAmount(), swept);
  }

  function test_getInvestedAmount_tracksTheHubSweptBalance() public {
    vm.prank(keeper);
    controller.invest(75_000e6);

    assertEq(controller.getInvestedAmount(), 75_000e6);
    assertEq(controller.getInvestedAmount(), hub.getAssetSwept(assetId));
  }

  function test_getInvestedAmount_reducedByDivest() public {
    vm.prank(keeper);
    controller.invest(75_000e6);

    vm.prank(keeper);
    controller.divest(25_000e6, _encodeAttestation(_defaultTransferSpec(25_000e6)), hex'1234');

    assertEq(controller.getInvestedAmount(), 50_000e6);
  }

  function test_getInvestedAmount_includesWithdrawingBalance() public {
    vm.prank(keeper);
    controller.invest(75_000e6);

    vm.prank(pauser);
    controller.pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    assertEq(wallet.availableBalance(address(usdc), address(controller)), 0);
    assertEq(controller.getInvestedAmount(), 75_000e6);
  }

  function test_getInvestedAmount_zeroAfterWithdrawalCompletes() public {
    vm.prank(keeper);
    controller.invest(75_000e6);

    vm.prank(pauser);
    controller.pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    vm.roll(block.number + WITHDRAWAL_DELAY);

    vm.prank(admin);
    controller.withdraw();

    assertEq(controller.getInvestedAmount(), 0);
  }
}
