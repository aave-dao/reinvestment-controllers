// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {ReinvestmentControllerTestBase} from './ReinvestmentController.Base.t.sol';

contract ReinvestmentControllerGetDriftTest is ReinvestmentControllerTestBase {
  function test_getDrift() public view {
    assertEq(controller.getDrift(), 0);
  }

  function test_getDrift(uint256 swept) public {
    swept = bound(swept, 0, type(uint96).max);
    hub.setAccounting(SUPPLIED, SUPPLIED, swept);

    assertEq(controller.getDrift(), swept);
  }

  function test_getDrift_zeroWhileTheGatewayBalanceMatchesSwept() public {
    _invest(100_000e6);

    assertEq(hub.getAssetSwept(assetId), wallet.totalBalance(address(usdc), address(controller)));
    assertEq(controller.getDrift(), 0);
  }

  function test_getDrift_sweptAboveTheGatewayBalance() public {
    _invest(100_000e6);
    hub.setAccounting(SUPPLIED, SUPPLIED - 101_000e6, 101_000e6);

    assertEq(controller.getDrift(), 1_000e6);
  }

  function test_getDrift_zeroWhenTheGatewayBalanceExceedsSwept() public {
    _invest(100_000e6);
    hub.setAccounting(SUPPLIED, SUPPLIED - 99_000e6, 99_000e6);

    assertEq(controller.getDrift(), 0);
  }

  function test_getDrift_countsTheWithdrawingBalanceAsHeld() public {
    _invest(100_000e6);
    _pause();

    vm.prank(admin);
    controller.initiateWithdrawal();

    assertEq(wallet.availableBalance(address(usdc), address(controller)), 0);
    assertEq(wallet.withdrawingBalance(address(usdc), address(controller)), 100_000e6);
    assertEq(controller.getDrift(), 0);
  }

  function test_getDrift_zeroAfterDivest() public {
    _invest(100_000e6);

    vm.prank(keeper);
    controller.divest(100_000e6, _encodeAttestation(_defaultTransferSpec(100_000e6)), hex'1234');

    assertEq(controller.getDrift(), 0);
  }
}
