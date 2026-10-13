import type {Address, PublicClient} from 'viem';
import {controllerAbi} from './abi/controller.js';

export type Deployment = {
  controller: Address;
  hub: Address;
  assetId: bigint;
  gatewayWallet: Address;
  gatewayMinter: Address;
  usdc: Address;
  domain: number;
};

/** Reads the controller's immutable wiring once at startup */
export async function readDeployment(
  client: PublicClient,
  controller: Address,
): Promise<Deployment> {
  const contract = {address: controller, abi: controllerAbi} as const;
  const [hub, assetId, gatewayWallet, gatewayMinter, usdc, domain] = await Promise.all([
    client.readContract({...contract, functionName: 'HUB'}),
    client.readContract({...contract, functionName: 'ASSET_ID'}),
    client.readContract({...contract, functionName: 'GATEWAY_WALLET'}),
    client.readContract({...contract, functionName: 'GATEWAY_MINTER'}),
    client.readContract({...contract, functionName: 'USDC'}),
    client.readContract({...contract, functionName: 'DOMAIN'}),
  ]);
  return {controller, hub, assetId, gatewayWallet, gatewayMinter, usdc, domain};
}
