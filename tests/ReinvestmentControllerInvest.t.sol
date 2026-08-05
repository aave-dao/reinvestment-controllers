// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IReinvestmentController} from "../src/ReinvestmentController.sol";

import {ReinvestmentControllerTest} from "./ReinvestmentControllerBase.t.sol";

contract InvestTest is ReinvestmentControllerTest {
    function test_invest_revertsWith_callerIsNotInvestorBeforeAmountCheck()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                controller.INVESTOR_ROLE()
            )
        );
        controller.invest(0);
    }

    function test_invest_revertsWith_callerIsNotInvestor() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                controller.INVESTOR_ROLE()
            )
        );
        controller.invest(1e6);
    }

    function test_invest_revertsWith_depositTimelockNotElapsed() public {
        _invest(1_000e6);

        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.DepositTimelock.selector);
        controller.invest(1_000e6);
    }

    function test_invest_revertsWith_depositTimelockAtExactBoundary() public {
        _invest(1_000e6);

        vm.warp(block.timestamp + DEPOSIT_TIMELOCK);

        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.DepositTimelock.selector);
        controller.invest(1_000e6);
    }

    function test_invest_revertsWith_invalidAmount() public {
        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
        controller.invest(0);
    }

    function test_invest_revertsWith_amountExceedsInvestable() public {
        vm.prank(admin);
        vm.expectRevert(
            IReinvestmentController.MaximumInvestAmountExceeded.selector
        );
        controller.invest(INVESTABLE + 1);
    }

    function test_invest_revertsWith_idleLiquidityAtBuffer() public {
        hub.setLiquidity(ASSET_ID, (SUPPLIED * BUFFER_BPS) / 10_000);

        assertEq(controller.getInvestableAmount(), 0);

        vm.prank(admin);
        vm.expectRevert(
            IReinvestmentController.MaximumInvestAmountExceeded.selector
        );
        controller.invest(1);
    }

    function test_invest_revertsWith_maxInvestSetToZero() public {
        vm.prank(admin);
        controller.setMaxInvest(0);

        vm.prank(admin);
        vm.expectRevert(
            IReinvestmentController.MaximumInvestAmountExceeded.selector
        );
        controller.invest(1);
    }

    function test_invest_partialAmountLeavesRemainingHeadroom() public {
        uint256 amount = 100_000e6;
        _invest(amount);

        assertEq(controller.getInvestedAmount(), amount);
        assertEq(controller.getInvestableAmount(), INVESTABLE - amount);
    }

    function test_invest_succeedsAgainAfterTimelockElapses() public {
        uint256 amount = 100_000e6;
        _invest(amount);

        vm.warp(block.timestamp + DEPOSIT_TIMELOCK + 1);

        vm.prank(admin);
        controller.invest(amount);

        assertEq(controller.getInvestedAmount(), amount * 2);
    }

    function test_invest_successful() public {
        vm.expectEmit(address(controller));
        emit IReinvestmentController.Invested(INVESTABLE);
        _invest(INVESTABLE);

        assertEq(usdc.balanceOf(address(gateway)), INVESTABLE);
        assertEq(usdc.balanceOf(address(hub)), SUPPLIED - INVESTABLE);
        assertEq(usdc.balanceOf(address(controller)), 0);

        assertEq(controller.getInvestedAmount(), INVESTABLE);
        assertEq(hub.getAssetLiquidity(ASSET_ID), SUPPLIED - INVESTABLE);
        assertEq(hub.getAddedAssets(ASSET_ID), SUPPLIED);

        assertEq(usdc.allowance(address(controller), address(gateway)), 0);
        assertEq(
            gateway.balanceOf(address(controller), address(usdc)),
            INVESTABLE
        );

        assertEq(controller.getInvestableAmount(), 0);
    }
}
