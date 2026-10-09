import {
  encodeAbiParameters,
  encodePacked,
  keccak256,
  pad,
  size,
  type Address,
  type Hex,
  type LocalAccount,
  type TypedDataDefinition,
} from 'viem';

const BURN_INTENT_MAGIC = '0x070afbc2';
const TRANSFER_SPEC_MAGIC = '0xca85def7';
const TRANSFER_SPEC_VERSION = 1;

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

/** Builds a same-domain withdrawal with every party pinned to the controller */
export function buildBurnIntent(params: BuildBurnIntentParams): BurnIntent {
  const controller = pad(params.controller);
  const usdc = pad(params.usdc);

  return {
    maxBlockHeight: params.maxBlockHeight,
    maxFee: params.maxFee,
    spec: {
      version: TRANSFER_SPEC_VERSION,
      sourceDomain: params.domain,
      destinationDomain: params.domain,
      sourceContract: pad(params.gatewayWallet),
      destinationContract: pad(params.gatewayMinter),
      sourceToken: usdc,
      destinationToken: usdc,
      sourceDepositor: controller,
      destinationRecipient: controller,
      sourceSigner: controller,
      destinationCaller: controller,
      value: params.value,
      salt: params.salt,
      hookData: '0x',
    },
  };
}

/** Encodes a transfer spec in Gateway's packed format, matching `TransferSpecLib.encodeTransferSpec` */
export function encodeTransferSpec(spec: BurnIntent['spec']): Hex {
  return encodePacked(
    [
      'bytes4',
      'uint32',
      'uint32',
      'uint32',
      'bytes32',
      'bytes32',
      'bytes32',
      'bytes32',
      'bytes32',
      'bytes32',
      'bytes32',
      'bytes32',
      'uint256',
      'bytes32',
      'uint32',
      'bytes',
    ],
    [
      TRANSFER_SPEC_MAGIC,
      spec.version,
      spec.sourceDomain,
      spec.destinationDomain,
      spec.sourceContract,
      spec.destinationContract,
      spec.sourceToken,
      spec.destinationToken,
      spec.sourceDepositor,
      spec.destinationRecipient,
      spec.sourceSigner,
      spec.destinationCaller,
      spec.value,
      spec.salt,
      size(spec.hookData),
      spec.hookData,
    ],
  );
}

/** Encodes a burn intent in Gateway's packed format, matching `BurnIntentLib.encodeBurnIntent` */
export function encodeBurnIntent(intent: BurnIntent): Hex {
  const spec = encodeTransferSpec(intent.spec);
  return encodePacked(
    ['bytes4', 'uint256', 'uint256', 'uint32', 'bytes'],
    [BURN_INTENT_MAGIC, intent.maxBlockHeight, intent.maxFee, size(spec), spec],
  );
}

/** The cross-chain identifier Gateway uses for replay protection */
export function getTransferSpecHash(intent: BurnIntent): Hex {
  return keccak256(encodeTransferSpec(intent.spec));
}

/** Signs a burn intent with the keeper and wraps it as the controller's {isValidSignature} expects */
export async function signBurnIntent(account: LocalAccount, intent: BurnIntent): Promise<Hex> {
  const keeperSignature = await account.signTypedData({
    domain: gatewayDomain,
    types: burnIntentTypes,
    primaryType: 'BurnIntent',
    message: intent,
  });
  return encodeAbiParameters(
    [{type: 'bytes'}, {type: 'bytes'}],
    [keeperSignature, encodeBurnIntent(intent)],
  );
}
