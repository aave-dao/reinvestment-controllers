import {parseAbi} from 'viem';

export const gatewayWalletAbi = parseAbi(['function withdrawalDelay() view returns (uint256)']);
