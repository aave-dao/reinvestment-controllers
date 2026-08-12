// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IHub} from "../../src/interfaces/IHub.sol";

/// @dev Stand-in for the Hub. Tracks the three balances `_getInvestableAmount` reads
/// (added / liquidity / swept) and moves real tokens on `sweep`, so the controller's
/// custody path can be exercised end to end.
contract MockHub is IHub {
    using SafeERC20 for IERC20;

    /// @dev Asset not listed
    error AssetNotListed();

    mapping(uint256 assetId => address underlying) public underlyingOf;

    mapping(address underlying => uint256 assetId) private _assetIds;
    mapping(address underlying => bool listed) private _listed;

    mapping(uint256 assetId => uint256 amount) private _addedAssets;
    mapping(uint256 assetId => uint256 amount) private _liquidity;
    mapping(uint256 assetId => uint256 amount) private _swept;

    mapping(uint256 assetId => AssetConfig config) private _configs;

    /// @dev Registers `underlying` under `assetId`. Must be called before deploying the
    /// controller, whose constructor reads `getAssetId`.
    function listAsset(address underlying, uint256 assetId) external {
        _assetIds[underlying] = assetId;
        _listed[underlying] = true;
        underlyingOf[assetId] = underlying;
    }

    /// @dev Sets total assets supplied to the Hub, the base for buffer and BPS caps
    function setAddedAssets(uint256 assetId, uint256 amount) external {
        _addedAssets[assetId] = amount;
    }

    /// @dev Sets idle (uninvested) liquidity held by the Hub
    function setLiquidity(uint256 assetId, uint256 amount) external {
        _liquidity[assetId] = amount;
    }

    /// @dev Sets the amount already swept out to the controller
    function setSwept(uint256 assetId, uint256 amount) external {
        _swept[assetId] = amount;
    }

    /// @inheritdoc IHub
    function sweep(uint256 assetId, uint256 amount) external {
        _liquidity[assetId] -= amount;
        _swept[assetId] += amount;

        IERC20(underlyingOf[assetId]).safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc IHub
    /// @dev Accounting only. The controller pushes the tokens back with `safeTransfer`
    /// immediately before calling this, so the mock must not pull them again.
    function reclaim(uint256 assetId, uint256 amount) external {
        _swept[assetId] -= amount;
        _liquidity[assetId] += amount;
    }

    /// @inheritdoc IHub
    function getAssetConfig(uint256 assetId) external view returns (AssetConfig memory) {
        return _configs[assetId];
    }

    /// @inheritdoc IHub
    /// @dev Unrestricted here; the real Hub gates this behind its access manager
    function updateAssetConfig(uint256 assetId, AssetConfig calldata config, bytes calldata) external {
        _configs[assetId] = config;
    }

    /// @inheritdoc IHub
    function getAddedAssets(uint256 assetId) external view returns (uint256) {
        return _addedAssets[assetId];
    }

    /// @inheritdoc IHub
    function getAssetId(address underlying) external view returns (uint256) {
        require(_listed[underlying], AssetNotListed());
        return _assetIds[underlying];
    }

    /// @inheritdoc IHub
    function getAssetLiquidity(uint256 assetId) external view returns (uint256) {
        return _liquidity[assetId];
    }

    /// @inheritdoc IHub
    function getAssetSwept(uint256 assetId) external view returns (uint256) {
        return _swept[assetId];
    }
}
