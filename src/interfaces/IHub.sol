// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.29;

interface IHub {
  /// @notice Asset configuration. Subset of the Hub's `Asset` struct.
  struct AssetConfig {
    address feeReceiver;
    uint16 liquidityFee;
    address irStrategy;
    address reinvestmentController;
  }

  /// @notice Returns the current configuration of the specified asset.
  /// @param assetId The identifier of the asset.
  /// @return The asset configuration.
  function getAssetConfig(uint256 assetId) external view returns (AssetConfig memory);

  /// @notice Updates the configuration of the specified asset.
  /// @dev Governance-restricted, and the only path that sets `reinvestmentController`.
  /// Writes the whole config, so read it first and change only the intended field.
  /// Clearing the controller is rejected while the asset still has a swept balance.
  /// @param assetId The identifier of the asset.
  /// @param config The full configuration to apply.
  /// @param irData Interest rate data, which must be empty unless `irStrategy` changes.
  function updateAssetConfig(
    uint256 assetId,
    AssetConfig calldata config,
    bytes calldata irData
  ) external;

  /// @notice Sweeps an amount of liquidity of the corresponding asset and sends it to the configured reinvestment controller.
  /// @dev The controller handles the actual reinvestment of funds, redistribution of interest, and investment caps.
  /// @param assetId The identifier of the asset.
  /// @param amount The amount to sweep.
  function sweep(uint256 assetId, uint256 amount) external;

  /// @notice Reclaims an amount of liquidity of the corresponding asset from the configured reinvestment controller.
  /// @dev The controller can only reclaim up to swept amount. All accrued interest is distributed offchain.
  /// @param assetId The identifier of the asset.
  /// @param amount The amount to reclaim.
  function reclaim(uint256 assetId, uint256 amount) external;

  /// @notice Returns the total amount of the specified asset added to the Hub.
  /// @param assetId The identifier of the asset.
  /// @return The amount of the asset added.
  function getAddedAssets(uint256 assetId) external view returns (uint256);

  /// @notice Returns the asset identifier for the specified underlying asset.
  /// @dev Reverts with `AssetNotListed` if the underlying is not listed.
  /// @param underlying The address of the underlying asset.
  function getAssetId(address underlying) external view returns (uint256);

  /// @notice Returns the amount of available liquidity for the specified asset.
  /// @param assetId The identifier of the asset.
  /// @return The amount of available liquidity.
  function getAssetLiquidity(uint256 assetId) external view returns (uint256);

  /// @notice Returns the amount of liquidity swept by the reinvestment controller for the specified asset.
  /// @param assetId The identifier of the asset.
  /// @return The amount of liquidity swept.
  function getAssetSwept(uint256 assetId) external view returns (uint256);
}
