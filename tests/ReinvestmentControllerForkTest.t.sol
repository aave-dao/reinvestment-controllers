// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IGatewayMinter} from "../src/interfaces/IGatewayMinter.sol";
import {IGatewayWallet} from "../src/interfaces/IGatewayWallet.sol";
import {IHub} from "../src/interfaces/IHub.sol";
import {ReinvestmentController, IReinvestmentController} from "../src/ReinvestmentController.sol";

contract ReinvestmentControllerForkTest is Test {
    // https://etherscan.io/address/0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE
    address public constant GATEWAY_WALLET = 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;

    // https://etherscan.io/address/0x2222222d7164433c4C09B0b0D809a9b52C04C205
    address public constant GATEWAY_MINTER = 0x2222222d7164433c4C09B0b0D809a9b52C04C205;

    // https://etherscan.io/address/0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9
    address public constant HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;

    // https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // https://etherscan.io/address/0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A
    address public constant EXECUTOR_LVL_1 = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A; // governance

    // https://etherscan.io/address/0x1F0753480bB03EaA00863224602267B7E0525C3d
    address public constant HUB_CONFIGURATOR = 0x1F0753480bB03EaA00863224602267B7E0525C3d; // Holds the Hub's asset config role

    uint256 public constant DEPOSIT_TIMELOCK = 1 days;
    uint256 public constant MAX_INVEST = 100_000_000e6;
    uint256 public constant MAX_INVEST_BPS = 80_00; // 80%
    uint256 public constant BUFFER_BPS = 10_00; // 10%

    uint256 public constant GATEWAY_WITHDRAWAL_DELAY = 50_400;

    ReinvestmentController public controller;
    ReinvestmentController public implementation;
    TransparentUpgradeableProxy public proxy;

    uint256 public assetId;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 25726000);

        assetId = IHub(HUB).getAssetId(USDC);

        implementation = new ReinvestmentController(GATEWAY_WALLET, GATEWAY_MINTER, HUB, USDC);

        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            EXECUTOR_LVL_1,
            abi.encodeCall(
                ReinvestmentController.initialize,
                (EXECUTOR_LVL_1, DEPOSIT_TIMELOCK, MAX_INVEST, MAX_INVEST_BPS, BUFFER_BPS)
            )
        );

        controller = ReinvestmentController(address(proxy));
    }

    function _setReinvestmentController() internal {
        IHub.AssetConfig memory config = IHub(HUB).getAssetConfig(assetId);
        config.reinvestmentController = address(controller);

        vm.prank(HUB_CONFIGURATOR);
        IHub(HUB).updateAssetConfig(assetId, config, "");
    }

    function _invest(uint256 amount) internal {
        vm.prank(EXECUTOR_LVL_1);
        controller.invest(amount);
    }
}

contract ForkInvestTest is ReinvestmentControllerForkTest {
    /// @notice Thrown when an invalid reinvestment controller attempts to perform a `sweep` action.
    error OnlyReinvestmentController();

    function test_invest_revertsWith_unauthorizedUser() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), controller.INVESTOR_ROLE()
            )
        );
        controller.invest(100_000e6);
    }

    function test_invest_revertsWith_notReinvestmentController() public {
        vm.expectRevert(OnlyReinvestmentController.selector);
        _invest(100_000e6);
    }

    function test_invest_revertsWith_amountExceedsInvestable() public {
        _setReinvestmentController();

        uint256 amount = controller.getInvestableAmount() + 1;

        vm.expectRevert(IReinvestmentController.MaximumInvestAmountExceeded.selector);
        _invest(amount);
    }

    function test_invest_atFullInvestableAmount() public {
        _setReinvestmentController();

        uint256 investable = controller.getInvestableAmount();

        _invest(investable);

        assertEq(controller.getInvestedAmount(), investable);
        assertEq(controller.getInvestableAmount(), 0);
    }

    function test_invest_preservesLiquidityBuffer() public {
        _setReinvestmentController();

        uint256 supplied = IHub(HUB).getAddedAssets(assetId);

        _invest(controller.getInvestableAmount());

        assertGe(IHub(HUB).getAssetLiquidity(assetId), (supplied * BUFFER_BPS) / 100_00);
    }

    function test_invest_accumulatesAcrossDeposits() public {
        _setReinvestmentController();

        uint256 amount = controller.getInvestableAmount() / 4;

        _invest(amount);

        vm.warp(block.timestamp + DEPOSIT_TIMELOCK + 1);

        _invest(amount);

        assertEq(controller.getInvestedAmount(), amount * 2);
        assertEq(IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)), amount * 2);
    }

    function test_invest_successful(uint256 amount) public {
        _setReinvestmentController();

        uint256 availableLiquidity = IHub(HUB).getAssetLiquidity(assetId);
        uint256 suppliedBefore = IHub(HUB).getAddedAssets(assetId);
        uint256 investableBefore = controller.getInvestableAmount();
        uint256 hubBalanceBefore = IERC20(USDC).balanceOf(HUB);
        uint256 walletBalanceBefore = IERC20(USDC).balanceOf(GATEWAY_WALLET);

        amount = bound(amount, 1_000e6, investableBefore);

        vm.expectEmit(address(controller));
        emit IReinvestmentController.Invested(amount);

        _invest(amount);

        assertEq(IERC20(USDC).balanceOf(GATEWAY_WALLET), walletBalanceBefore + amount);
        assertEq(IERC20(USDC).balanceOf(HUB), hubBalanceBefore - amount);
        assertEq(IERC20(USDC).balanceOf(address(controller)), 0);

        assertEq(controller.getInvestedAmount(), amount);
        assertEq(IHub(HUB).getAssetLiquidity(assetId), availableLiquidity - amount);
        assertEq(IHub(HUB).getAddedAssets(assetId), suppliedBefore);

        assertEq(IERC20(USDC).allowance(address(controller), GATEWAY_WALLET), 0);
        assertEq(controller.getInvestableAmount(), investableBefore - amount);
        assertEq(IGatewayWallet(GATEWAY_WALLET).availableBalance(USDC, address(controller)), amount);
    }
}

contract ForkPreconditionsTest is ReinvestmentControllerForkTest {
    function test_preconditions_assetHasNoReinvestmentController() public view {
        assertEq(IHub(HUB).getAssetConfig(assetId).reinvestmentController, address(0));
        assertEq(IHub(HUB).getAssetSwept(assetId), 0);
    }

    function test_preconditions_gatewayWithdrawalDelayMatchesMock() public view {
        assertEq(IGatewayWallet(GATEWAY_WALLET).withdrawalDelay(), GATEWAY_WITHDRAWAL_DELAY);
    }
}
