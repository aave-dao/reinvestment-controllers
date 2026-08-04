// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGateway} from "../../src/interfaces/IGateway.sol";

/// @dev Stand-in for the Circle USDC Gateway. Holds real tokens and tracks per-depositor
/// balances, but performs no attestation or signature verification.
///
/// Two deliberate simplifications:
/// - `gatewayMint` ignores the payload and delivers whatever `setNextMint` configured.
///   The controller validates the attestation itself before calling, so payload parsing
///   belongs in those tests, not here.
/// - `withdraw` enforces no delay. The seven-day wait under test is the controller's own
///   `SEVEN_DAYS_IN_BLOCKS`, not the Gateway's.
contract MockGateway is IGateway {
    using SafeERC20 for IERC20;

    mapping(address depositor => mapping(address token => uint256 amount))
        public balanceOf;

    mapping(address depositor => mapping(address token => uint256 amount))
        public pendingWithdrawalOf;

    address private _nextMintToken;
    uint256 private _nextMintValue;
    bytes32 private _domainSeparator;

    constructor() {
        _domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId)"),
                keccak256("MockGateway"),
                block.chainid
            )
        );
    }

    /// @dev Overrides the EIP-712 domain separator so ERC-1271 tests can build a digest
    /// that matches whatever they signed
    function setDomainSeparator(bytes32 domainSeparator_) external {
        _domainSeparator = domainSeparator_;
    }

    /// @dev Configures what the next `gatewayMint` delivers to its caller. Fund this
    /// contract with `value` of `token` first.
    function setNextMint(address token, uint256 value) external {
        _nextMintToken = token;
        _nextMintValue = value;
    }

    /// @inheritdoc IGateway
    function deposit(address token, uint256 value) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), value);
        balanceOf[msg.sender][token] += value;
    }

    /// @inheritdoc IGateway
    function gatewayMint(bytes memory, bytes memory) external {
        address token = _nextMintToken;
        uint256 value = _nextMintValue;

        balanceOf[msg.sender][token] -= value;
        IERC20(token).safeTransfer(msg.sender, value);
    }

    /// @inheritdoc IGateway
    function initiateWithdrawal(address token, uint256 value) external {
        balanceOf[msg.sender][token] -= value;
        pendingWithdrawalOf[msg.sender][token] += value;
    }

    /// @inheritdoc IGateway
    function withdraw(address token) external {
        uint256 amount = pendingWithdrawalOf[msg.sender][token];
        pendingWithdrawalOf[msg.sender][token] = 0;

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc IGateway
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator;
    }
}
