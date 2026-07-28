// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IGateway} from "./interfaces/IGateway.sol";
import {IHub} from "./interfaces/IHub.sol";
import {IReinvestmentController} from "./interfaces/IReinvestmentController.sol";

contract ReinvestmentController is
    IReinvestmentController,
    AccessControl,
    Pausable
{
    using SafeERC20 for IERC20;

    IHub public immutable HUB;
    IGateway public immutable GATEWAY;
    IERC20 public immutable USDC;

    uint256 public immutable ASSET_ID;

    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");

    uint256 public _invested;
    uint256 public _gatewayTxLimit = 10_000_000e6;

    constructor(address admin, address hub, address gateway, address usdc) {
        HUB = IHub(hub);
        GATEWAY = IGateway(gateway);
        USDC = IERC20(usdc);
        ASSET_ID = IHub(hub).getAssetId(usdc);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(INVESTOR_ROLE, admin);
    }

    function invest(uint256 amount) external onlyRole(INVESTOR_ROLE) {
        require(amount > 0, InvalidAmount());
        _validateInvestability(amount);

        _invested += amount;

        HUB.sweep(ASSET_ID, amount);
        USDC.forceApprove(address(GATEWAY), amount);
        GATEWAY.deposit(address(USDC), amount);

        emit Invested(amount);
    }

    function divest(
        uint256 amount,
        bytes memory attestationPayload,
        bytes memory signature
    ) external onlyRole(INVESTOR_ROLE) {
        require(amount > 0 && amount < _gatewayTxLimit, InvalidAmount());
        require(amount <= _invested, InsufficientLiquidity());

        _invested -= amount;

        emit Divested(amount);
    }

    function initiateWithdrawal() external onlyRole(DEFAULT_ADMIN_ROLE) {}

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setGatewayTxLimit(
        uint256 limit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldLimit = _gatewayTxLimit;
        _gatewayTxLimit = limit;
        emit SetGatewayTxLimit(oldLimit, limit);
    }

    function deployable() external view returns (uint256) {}

    function _validateInvestability(uint256 amount) internal {}
}
