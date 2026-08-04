// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ReinvestmentController} from "../src/ReinvestmentController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockHub} from "./mocks/MockHub.sol";

contract ReinvestmentControllerTest is Test {
    uint256 public constant ASSET_ID = 1;

    uint256 public constant DEPOSIT_TIMELOCK = 1 days;
    uint256 public constant MAX_INVEST = 100_000_000e6;
    uint256 public constant MAX_INVEST_BPS = 8_000;
    uint256 public constant BUFFER_BPS = 1_000;

    /// @dev Starting Hub state: everything supplied is idle, nothing swept yet
    uint256 public constant SUPPLIED = 1_000_000e6;

    /// @dev What `getInvestableAmount()` returns from the default state. The BPS cap
    /// (80% of 1M = 800k) binds before the buffer does (1M less 10% = 900k free idle).
    uint256 public constant INVESTABLE = 800_000e6;

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

    /// @dev Adds `amount` USDC in the Hub and marks it all as supplied and idle
    function _fundHub(uint256 amount) internal {
        usdc.mint(address(hub), amount);
        hub.setAddedAssets(ASSET_ID, amount);
        hub.setLiquidity(ASSET_ID, amount);
    }

    /// @dev Invests `amount` as the INVESTOR_ROLE holder and leaves the Gateway ready to
    /// mint it straight back, which is the precondition for exercising divest
    function _invest(uint256 amount) internal {
        vm.prank(admin);
        controller.invest(amount);

        gateway.setNextMint(address(usdc), amount);
    }
}

contract ConstructorTest is Test {}

contract InitializeTest is ReinvestmentControllerTest {}

contract InvestTest is ReinvestmentControllerTest {}

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
