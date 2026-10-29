import {mainnet, sepolia} from 'viem/chains';

export const chains = {mainnet, sepolia} as const;

export type ChainName = keyof typeof chains;

export const gatewayApiUrls: Record<ChainName, string> = {
  mainnet: 'https://gateway-api.circle.com',
  sepolia: 'https://gateway-api-testnet.circle.com',
};
