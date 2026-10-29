import {parseAbi} from 'viem';

export const hubAbi = parseAbi([
  'function getAddedAssets(uint256 assetId) view returns (uint256)',
  'function getAssetLiquidity(uint256 assetId) view returns (uint256)',
  'function getAssetSwept(uint256 assetId) view returns (uint256)',
]);
