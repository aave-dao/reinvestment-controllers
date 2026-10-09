import {parseAbi, type Address, type PublicClient} from 'viem';

export const controllerAbi = parseAbi([
  'function invest(uint256 amount)',
  'function divest(uint256 amount, bytes attestationPayload, bytes signature)',
  'function getInvestableAmount() view returns (uint256)',
  'function getInvestedAmount() view returns (uint256)',
  'function getMaxFee() view returns (uint256)',
  'function getLastInvestTimestamp() view returns (uint256)',
  'function getInvestMinDelay() view returns (uint256)',
  'function getExposureCapAbs() view returns (uint256)',
  'function getExposureCapBps() view returns (uint256)',
  'function getLiquidBufferBps() view returns (uint256)',
  'function paused() view returns (bool)',
  'function HUB() view returns (address)',
  'function ASSET_ID() view returns (uint256)',
  'function GATEWAY_WALLET() view returns (address)',
  'function GATEWAY_MINTER() view returns (address)',
  'function DOMAIN() view returns (uint32)',
  'function USDC() view returns (address)',
]);

export const hubAbi = parseAbi([
  'function getAddedAssets(uint256 assetId) view returns (uint256)',
  'function getAssetLiquidity(uint256 assetId) view returns (uint256)',
  'function getAssetSwept(uint256 assetId) view returns (uint256)',
]);

export const gatewayWalletAbi = parseAbi(['function withdrawalDelay() view returns (uint256)']);

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
