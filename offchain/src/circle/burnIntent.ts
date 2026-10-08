import type {Address, Hex, TypedDataDefinition} from 'viem';

export const gatewayDomain = {name: 'GatewayWallet', version: '1'} as const;

export const burnIntentTypes = {
  TransferSpec: [
    {name: 'version', type: 'uint32'},
    {name: 'sourceDomain', type: 'uint32'},
    {name: 'destinationDomain', type: 'uint32'},
    {name: 'sourceContract', type: 'bytes32'},
    {name: 'destinationContract', type: 'bytes32'},
    {name: 'sourceToken', type: 'bytes32'},
    {name: 'destinationToken', type: 'bytes32'},
    {name: 'sourceDepositor', type: 'bytes32'},
    {name: 'destinationRecipient', type: 'bytes32'},
    {name: 'sourceSigner', type: 'bytes32'},
    {name: 'destinationCaller', type: 'bytes32'},
    {name: 'value', type: 'uint256'},
    {name: 'salt', type: 'bytes32'},
    {name: 'hookData', type: 'bytes'},
  ],
  BurnIntent: [
    {name: 'maxBlockHeight', type: 'uint256'},
    {name: 'maxFee', type: 'uint256'},
    {name: 'spec', type: 'TransferSpec'},
  ],
} as const;

export type BurnIntent = TypedDataDefinition<typeof burnIntentTypes, 'BurnIntent'>['message'];

export type BuildBurnIntentParams = {
  controller: Address;
  gatewayWallet: Address;
  gatewayMinter: Address;
  usdc: Address;
  domain: number;
  value: bigint;
  maxFee: bigint;
  maxBlockHeight: bigint;
  salt: Hex;
};

export function buildBurnIntent(params: BuildBurnIntentParams): BurnIntent {
  throw new Error('not implemented');
}
