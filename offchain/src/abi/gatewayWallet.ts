import {parseAbi} from 'viem';

export const gatewayWalletAbi = parseAbi([
  'function withdrawalDelay() view returns (uint256)',
  'function availableBalance(address token, address depositor) view returns (uint256)',
]);
