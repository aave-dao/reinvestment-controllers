// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IGateway} from "./IGateway.sol";
import {IHub} from "./IHub.sol";

interface IReinvestmentController {
    error BlockDelayNotElapsed();
    error BurnIntentExceedsBalance();
    error CrossChainTransferNotAllowed();
    error DepositTimelock();
    error HashMismatch();
    error InvalidAmount();
    error InvalidDepositor();
    error InvalidDestinationToken();
    error InvalidMintAmount();
    error InvalidRecipient();
    error InvalidSignature();
    error InvalidSigner();
    error InvalidSourceToken();
    error InsufficientLiquidity();
    error InvalidZeroAddress();
    error MaximumDeployAmountExceeded();
    error NoWithdrawalInProcess();
    error WithdrawalInProcess();

    event Invested(uint256 amount);
    event Divested(uint256 amount);
    event SetGatewayTxLimit(uint256 oldLimit, uint256 limit);
    event SetDepositTimelock(
        uint256 oldDepositTimelock,
        uint256 depositTimelock
    );
    event SetMaxDeploy(uint256 oldMaxDeploy, uint256 maxDeploy);
    event SetMaxDeployBps(uint256 oldMaxDeployBps, uint256 maxDeployBps);
    event SetBufferBps(uint256 oldBufferBps, uint256 bufferBps);
    event WithdrawalCompleted(uint256 amount);
    event WithdrawalInitiated(uint256 amount, uint256 readyAtBlock);

    function invest(uint256 amount) external;

    function divest(
        uint256 amount,
        bytes calldata attestationPayload,
        bytes calldata signature
    ) external;

    function initiateWithdrawal(uint256 amount) external;

    function withdraw() external;

    function setDepositTimelock(uint256 depositTimelock) external;

    function setGatewayTxLimit(uint256 limit) external;

    function setMaxDeploy(uint256 maxDeploy_) external;

    function setMaxDeployBps(uint256 maxDeployBps_) external;

    function setBufferBps(uint256 bufferBps_) external;

    function INVESTOR_ROLE() external view returns (bytes32);

    function ERC1271_MAGIC_VALUE() external view returns (bytes4);

    function HUB() external view returns (IHub);

    function GATEWAY() external view returns (IGateway);

    function USDC() external view returns (IERC20);

    function ASSET_ID() external view returns (uint256);

    function getDeployableAmount() external view returns (uint256);

    function getReinvestedAmount() external view returns (uint256);

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);

    function gatewayTxLimit() external view returns (uint256);

    function maxDeploy() external view returns (uint256);

    function maxDeployBps() external view returns (uint256);

    function bufferBps() external view returns (uint256);

    function pendingWithdrawalAmount() external view returns (uint256);

    function readyAtBlock() external view returns (uint256);
}
