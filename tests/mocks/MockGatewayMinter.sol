// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.30;

import {IGatewayMinter} from "../../src/interfaces/IGatewayMinter.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Stand-in for Circle's `GatewayMinter`, a separate deployment from the wallet.
///
/// Performs no attestation or signature verification — the payload is ignored and
/// {setNextMint} decides what the next call delivers. The controller validates the
/// attestation itself before calling, so payload parsing belongs in those tests.
///
/// Mints new tokens rather than transferring held ones, matching the real minter's mint
/// authority. It holds no balance of its own.
contract MockGatewayMinter is IGatewayMinter {
    address private _nextMintToken;
    uint256 private _nextMintValue;

    /// @dev Configures what the next `gatewayMint` delivers to its caller
    function setNextMint(address token, uint256 value) external {
        _nextMintToken = token;
        _nextMintValue = value;
    }

    /// @inheritdoc IGatewayMinter
    function gatewayMint(bytes memory, bytes memory) external {
        MockERC20(_nextMintToken).mint(msg.sender, _nextMintValue);
    }
}
