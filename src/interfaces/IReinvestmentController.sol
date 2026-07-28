// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

interface IReinvestmentController {
    error BlockDelayNotElapsed();
    error BurnIntentExceedsBalance();
    error CrossChainTransferNotAllowed();
    error HashMismatch();
    error InvalidAmount();
    error InvalidDepositor();
    error InvalidDestinationToken();
    error InvalidHash();
    error InvalidMintAmount();
    error InvalidRecipient();
    error InvalidSignature();
    error InvalidSigner();
    error InvalidSourceToken();
    error InsufficientLiquidity();
    error InvalidZeroAddress();
    error MaximumDeployAmountExceeded();
    error WithdrawalInProcess();

    event Invested(uint256 amount);
    event Divested(uint256 amount);
    event SetGatewayTxLimit(uint256 oldLimit, uint256 limit);
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

    function setGatewayTxLimit(uint256 limit) external;

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

    function pendingWithdrawal() external view returns (uint256);

    function readyAtBlock() external view returns (uint256);
}
