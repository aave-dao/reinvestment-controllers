// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ReinvestmentController, IReinvestmentController} from "../src/ReinvestmentController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockHub} from "./mocks/MockHub.sol";

contract ReinvestmentControllerTest is Test {
    uint256 public constant ASSET_ID = 1;

    uint256 public constant DEPOSIT_TIMELOCK = 1 days;
    uint256 public constant MAX_INVEST = 100_000_000e6;
    uint256 public constant MAX_INVEST_BPS = 80_00; // 80%
    uint256 public constant BUFFER_BPS = 10_00; // 10%

    /// @dev Starting Hub state: everything supplied is idle, nothing swept yet
    uint256 public constant SUPPLIED = 1_000_000e6;

    /// @dev What `getInvestableAmount()` returns from the default state
    uint256 public constant INVESTABLE = 800_000e6; // 80% of liquidity

    ReinvestmentController public controller;
    ReinvestmentController public implementation;
    TransparentUpgradeableProxy public proxy;

    MockERC20 public usdc;
    MockGateway public gateway;
    MockHub public hub;

    address public admin = makeAddr("admin");
    address public proxyAdminOwner = makeAddr("proxyAdminOwner");

    function setUp() public virtual {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        gateway = new MockGateway();
        hub = new MockHub();

        hub.listAsset(address(usdc), ASSET_ID);

        implementation = new ReinvestmentController(
            address(gateway),
            address(hub),
            address(usdc)
        );

        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdminOwner,
            abi.encodeCall(
                ReinvestmentController.initialize,
                (
                    admin,
                    DEPOSIT_TIMELOCK,
                    MAX_INVEST,
                    MAX_INVEST_BPS,
                    BUFFER_BPS
                )
            )
        );

        controller = ReinvestmentController(address(proxy));

        _fundHub(SUPPLIED);

        // _depositLastUpdate starts at 0, so the first invest stays gated until the
        // timelock has elapsed against the block clock
        vm.warp(DEPOSIT_TIMELOCK + 1);
    }

    function _fundHub(uint256 amount) internal {
        usdc.mint(address(hub), amount);
        hub.setAddedAssets(ASSET_ID, amount);
        hub.setLiquidity(ASSET_ID, amount);
    }

    /// @dev Invests `amount` as the INVESTOR_ROLE holder and leaves the Gateway ready to
    /// mint it straight back
    function _invest(uint256 amount) internal {
        vm.prank(admin);
        controller.invest(amount);

        gateway.setNextMint(address(usdc), amount);
    }
}

contract ConstructorTest is Test {
    uint256 public constant ASSET_ID = 1;

    function test_constructor_revertsWith_gatewayIsZeroAddress() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockHub hub = new MockHub();

        vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
        new ReinvestmentController(address(0), address(hub), address(usdc));
    }

    function test_constructor_revertsWith_hubIsZeroAddress() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockGateway gateway = new MockGateway();

        vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
        new ReinvestmentController(address(gateway), address(0), address(usdc));
    }

    function test_constructor_revertsWith_usdcIsZeroAddress() public {
        MockGateway gateway = new MockGateway();
        MockHub hub = new MockHub();

        vm.expectRevert(IReinvestmentController.InvalidZeroAddress.selector);
        new ReinvestmentController(address(gateway), address(hub), address(0));
    }

    function test_constructor_revertsWith_assetNotListedOnHub() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockGateway gateway = new MockGateway();
        MockHub hub = new MockHub();

        vm.expectRevert(MockHub.AssetNotListed.selector);
        new ReinvestmentController(
            address(gateway),
            address(hub),
            address(usdc)
        );
    }

    function test_constructor_locksImplementation() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockGateway gateway = new MockGateway();
        MockHub hub = new MockHub();
        hub.listAsset(address(usdc), ASSET_ID);

        ReinvestmentController controller = new ReinvestmentController(
            address(gateway),
            address(hub),
            address(usdc)
        );

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        controller.initialize(address(this), 1 days, 1e6, 8_000, 1_000);
    }

    function test_constructor_successful() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockGateway gateway = new MockGateway();
        MockHub hub = new MockHub();
        hub.listAsset(address(usdc), ASSET_ID);

        ReinvestmentController controller = new ReinvestmentController(
            address(gateway),
            address(hub),
            address(usdc)
        );

        assertEq(address(controller.GATEWAY()), address(gateway));
        assertEq(address(controller.HUB()), address(hub));
        assertEq(address(controller.USDC()), address(usdc));
        assertEq(controller.ASSET_ID(), ASSET_ID);
    }
}

contract InitializeTest is ReinvestmentControllerTest {}

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

    function test_invest_revertsWith_invalidAmount() public {
        vm.prank(admin);
        vm.expectRevert(IReinvestmentController.InvalidAmount.selector);
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
}

contract DivestTest is ReinvestmentControllerTest {}

contract InitiateWithdrawalTest is ReinvestmentControllerTest {}

contract WithdrawTest is ReinvestmentControllerTest {}

contract SetDepositTimelockTest is ReinvestmentControllerTest {}

contract SetGatewayTxLimitTest is ReinvestmentControllerTest {}

contract SetBufferBpsTest is ReinvestmentControllerTest {}

contract SetMaxInvestTest is ReinvestmentControllerTest {}

contract SetMaxInvestBpsTest is ReinvestmentControllerTest {}

contract GetInvestableAmountTest is ReinvestmentControllerTest {}

contract IsValidSignatureTest is ReinvestmentControllerTest {}
