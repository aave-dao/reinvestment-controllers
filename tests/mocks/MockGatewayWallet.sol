// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGatewayWallet} from "../../src/interfaces/IGatewayWallet.sol";

/// @dev Stand-in for Circle's `GatewayWallet`. Custodies deposited tokens and mirrors the
/// real two-bucket balance model: `availableBalance` moves into `withdrawingBalance` on
/// `initiateWithdrawal`, and `withdraw` pays the latter out.
///
/// Getter names and argument order match the real contract (`token`, `depositor`) so the
/// mock cannot teach a wrong API. Two deliberate omissions:
/// - No withdrawal delay. The seven-day wait under test is the controller's own
///   `SEVEN_DAYS_IN_BLOCKS`, not the wallet's `withdrawalDelay`.
/// - No `gatewayBurn`. On the real system Circle burns the wallet balance out-of-band
///   after attesting a burn intent; the controller never triggers it, so a divest leaves
///   this contract's balances untouched. Use {simulateGatewayBurn} to model it.
contract MockGatewayWallet is IGatewayWallet {
    using SafeERC20 for IERC20;

    mapping(address token => mapping(address depositor => uint256 amount))
        private _availableBalances;

    mapping(address token => mapping(address depositor => uint256 amount))
        private _withdrawingBalances;

    bytes32 private _domainSeparator;

    constructor() {
        _domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId)"),
                keccak256("MockGatewayWallet"),
                block.chainid
            )
        );
    }

    /// @dev Overrides the EIP-712 domain separator so ERC-1271 tests can build a digest
    /// that matches whatever they signed
    function setDomainSeparator(bytes32 domainSeparator_) external {
        _domainSeparator = domainSeparator_;
    }

    /// @dev Models Circle burning an attested balance out-of-band, which the controller
    /// has no way to trigger itself
    function simulateGatewayBurn(
        address token,
        address depositor,
        uint256 value
    ) external {
        _availableBalances[token][depositor] -= value;
        IERC20(token).safeTransfer(address(0xdead), value);
    }

    /// @inheritdoc IGatewayWallet
    function deposit(address token, uint256 value) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), value);
        _availableBalances[token][msg.sender] += value;
    }

    /// @inheritdoc IGatewayWallet
    function initiateWithdrawal(address token, uint256 value) external {
        _availableBalances[token][msg.sender] -= value;
        _withdrawingBalances[token][msg.sender] += value;
    }

    /// @inheritdoc IGatewayWallet
    function withdraw(address token) external {
        uint256 amount = _withdrawingBalances[token][msg.sender];
        _withdrawingBalances[token][msg.sender] = 0;

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc IGatewayWallet
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator;
    }

    function availableBalance(
        address token,
        address depositor
    ) external view returns (uint256) {
        return _availableBalances[token][depositor];
    }

    function withdrawingBalance(
        address token,
        address depositor
    ) external view returns (uint256) {
        return _withdrawingBalances[token][depositor];
    }

    function totalBalance(
        address token,
        address depositor
    ) external view returns (uint256) {
        return
            _availableBalances[token][depositor] +
            _withdrawingBalances[token][depositor];
    }
}
