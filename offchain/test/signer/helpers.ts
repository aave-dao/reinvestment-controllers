import {concatHex, hexToBigInt, hexToBytes, numberToHex, toHex, type Hex} from 'viem';
import {privateKeyToAccount, sign} from 'viem/accounts';
import {burnIntentTypes, gatewayDomain} from '../../src/circle/burnIntent.js';
import type {KmsBackend} from '../../src/signer/types.js';

export const SECP256K1_SPKI_PREFIX = '0x3056301006072a8648ce3d020106052b8104000a034200';
export const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

function encodeDerInteger(value: bigint): Hex {
  let hex = value.toString(16);
  if (hex.length % 2) hex = `0${hex}`;
  if (parseInt(hex.slice(0, 2), 16) >= 0x80) hex = `00${hex}`;
  return concatHex(['0x02', numberToHex(hex.length / 2, {size: 1}), `0x${hex}`]);
}

export function encodeDerSignature(r: bigint, s: bigint): Uint8Array {
  const body = concatHex([encodeDerInteger(r), encodeDerInteger(s)]);
  return hexToBytes(concatHex(['0x30', numberToHex((body.length - 2) / 2, {size: 1}), body]));
}

/** Emulates a KMS key: returns its SPKI public key and DER signatures over raw digests */
export function localBackend(
  privateKey: Hex,
  {highS = false, signer = privateKey}: {highS?: boolean; signer?: Hex} = {},
): KmsBackend {
  return {
    async getPublicKey() {
      return hexToBytes(
        concatHex([SECP256K1_SPKI_PREFIX, privateKeyToAccount(privateKey).publicKey]),
      );
    },
    async signDigest(digest) {
      const {r, s} = await sign({hash: digest, privateKey: signer});
      const sValue = hexToBigInt(s);
      return encodeDerSignature(hexToBigInt(r), highS ? SECP256K1_N - sValue : sValue);
    },
  };
}

export const burnIntent = {
  types: burnIntentTypes,
  primaryType: 'BurnIntent',
  domain: gatewayDomain,
  message: {
    maxBlockHeight: 2n ** 256n - 1n,
    maxFee: 1_100_000n,
    spec: {
      version: 1,
      sourceDomain: 0,
      destinationDomain: 0,
      sourceContract: toHex(1, {size: 32}),
      destinationContract: toHex(2, {size: 32}),
      sourceToken: toHex(3, {size: 32}),
      destinationToken: toHex(3, {size: 32}),
      sourceDepositor: toHex(4, {size: 32}),
      destinationRecipient: toHex(4, {size: 32}),
      sourceSigner: toHex(4, {size: 32}),
      destinationCaller: toHex(4, {size: 32}),
      value: 1_000_000_000n,
      salt: toHex(5, {size: 32}),
      hookData: '0x',
    },
  },
} as const;
