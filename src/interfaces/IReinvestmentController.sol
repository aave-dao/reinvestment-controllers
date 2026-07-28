// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.28;

interface IReinvestmentController {
    error InvalidAmount();
    error InsufficientLiquidity();

    event Invested(uint256 amount);
    event Divested(uint256 amount);
    event SetGatewayTxLimit(uint256 oldLimit, uint256 limit);
}
