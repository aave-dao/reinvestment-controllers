// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity 0.8.28;

interface IHub {
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

    /// @notice Returns the asset identifier for the specified underlying asset.
    /// @dev Reverts with `AssetNotListed` if the underlying is not listed.
    /// @param underlying The address of the underlying asset.
    function getAssetId(address underlying) external view returns (uint256);
}
