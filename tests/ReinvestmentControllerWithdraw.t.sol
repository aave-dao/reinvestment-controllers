// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IReinvestmentController} from "../src/ReinvestmentController.sol";
import {ReinvestmentControllerTest} from "./ReinvestmentControllerBase.t.sol";

uint256 constant SEVEN_DAYS_IN_BLOCKS = 50_400;
uint256 constant WITHDRAW_AMOUNT = 100_000e6;

contract InitiateWithdrawalTest is ReinvestmentControllerTest {
    function test_initiateWithdrawal_revertsWith_callerIsNotAdmin() public {
        _invest(INVESTABLE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                controller.DEFAULT_ADMIN_ROLE()
            )
        );
        controller.initiateWithdrawal(WITHDRAW_AMOUNT);
    }

    function test_initiateWithdrawal_revertsWith_amountIsZero() public {
        _invest(INVESTABLE);

        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
        controller.initiateWithdrawal(0);
    }

    function test_initiateWithdrawal_revertsWith_insufficientLiquidity()
        public
    {
        _invest(INVESTABLE);

        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.InsufficientLiquidity.selector);
        controller.initiateWithdrawal(INVESTABLE + 1);
    }

    function test_initiateWithdrawal_revertsWith_withdrawalInProcess() public {
        _invest(INVESTABLE);

        vm.prank(admin);
        controller.initiateWithdrawal(WITHDRAW_AMOUNT);

        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.WithdrawalInProcess.selector);
        controller.initiateWithdrawal(WITHDRAW_AMOUNT);
    }

    function test_initiateWithdrawal_successful() public {
        _invest(INVESTABLE);

        uint256 expectedReadyAtBlock = block.number + SEVEN_DAYS_IN_BLOCKS;

        vm.expectEmit(address(controller));
        emit IReinvestmentController.WithdrawalInitiated(
            WITHDRAW_AMOUNT,
            expectedReadyAtBlock
        );

        vm.prank(admin);
        controller.initiateWithdrawal(WITHDRAW_AMOUNT);

        assertEq(controller.pendingWithdrawalAmount(), WITHDRAW_AMOUNT);
        assertEq(controller.readyAtBlock(), expectedReadyAtBlock);

        assertEq(
            gatewayWallet.withdrawingBalance(
                address(usdc),
                address(controller)
            ),
            WITHDRAW_AMOUNT
        );
        assertEq(
            gatewayWallet.availableBalance(address(usdc), address(controller)),
            INVESTABLE - WITHDRAW_AMOUNT
        );

        assertEq(usdc.balanceOf(address(gatewayWallet)), INVESTABLE);
        assertEq(controller.getInvestedAmount(), INVESTABLE);
    }
}

contract WithdrawTest is ReinvestmentControllerTest {
    function test_withdraw_revertsWith_callerIsNotAdmin() public {
        _invest(INVESTABLE);
        _initiateWithdrawal(WITHDRAW_AMOUNT);

        vm.roll(controller.readyAtBlock());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                controller.DEFAULT_ADMIN_ROLE()
            )
        );
        controller.withdraw();
    }

    function test_withdraw_revertsWith_noWithdrawalInProcess() public {
        _invest(INVESTABLE);

        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.NoWithdrawalInProcess.selector);
        controller.withdraw();
    }

    function test_withdraw_revertsWith_blockDelayNotElapsed() public {
        _invest(INVESTABLE);
        _initiateWithdrawal(WITHDRAW_AMOUNT);

        vm.roll(controller.readyAtBlock() - 1);

        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.BlockDelayNotElapsed.selector);
        controller.withdraw();
    }

    function test_withdraw_atExactReadyBlock() public {
        _invest(INVESTABLE);
        _initiateWithdrawal(WITHDRAW_AMOUNT);

        vm.roll(controller.readyAtBlock());

        vm.prank(admin);
        controller.withdraw();

        assertEq(controller.pendingWithdrawalAmount(), 0);
    }

    function test_withdraw_allowsNewWithdrawalAfterCompletion() public {
        _invest(INVESTABLE);
        _initiateWithdrawal(WITHDRAW_AMOUNT);

        vm.roll(controller.readyAtBlock());

        vm.prank(admin);
        controller.withdraw();

        _initiateWithdrawal(WITHDRAW_AMOUNT);

        assertEq(controller.pendingWithdrawalAmount(), WITHDRAW_AMOUNT);
    }

    function test_withdraw_successful() public {
        _invest(INVESTABLE);
        _initiateWithdrawal(WITHDRAW_AMOUNT);

        vm.roll(controller.readyAtBlock() + 1);

        vm.expectEmit(address(controller));
        emit IReinvestmentController.WithdrawalCompleted(WITHDRAW_AMOUNT);

        vm.prank(admin);
        controller.withdraw();

        assertEq(controller.pendingWithdrawalAmount(), 0);
        assertEq(controller.readyAtBlock(), 0);

        assertEq(
            usdc.balanceOf(address(hub)),
            SUPPLIED - INVESTABLE + WITHDRAW_AMOUNT
        );
        assertEq(
            usdc.balanceOf(address(gatewayWallet)),
            INVESTABLE - WITHDRAW_AMOUNT
        );
        assertEq(usdc.balanceOf(address(controller)), 0);

        assertEq(controller.getInvestedAmount(), INVESTABLE - WITHDRAW_AMOUNT);
        assertEq(
            hub.getAssetLiquidity(ASSET_ID),
            SUPPLIED - INVESTABLE + WITHDRAW_AMOUNT
        );
        assertEq(
            gatewayWallet.withdrawingBalance(
                address(usdc),
                address(controller)
            ),
            0
        );
    }

    function _initiateWithdrawal(uint256 amount) internal {
        vm.prank(admin);
        controller.initiateWithdrawal(amount);
    }
}
