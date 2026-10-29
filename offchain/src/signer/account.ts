import {
  bytesToHex,
  hashTypedData,
  isAddressEqual,
  keccak256,
  numberToHex,
  recoverAddress,
  serializeSignature,
  serializeTransaction,
  type Address,
  type Hex,
  type LocalAccount,
  type Signature,
} from 'viem';
import {publicKeyToAddress, toAccount} from 'viem/accounts';
import type {KmsBackend} from './types.js';

const SECP256K1_SPKI_PREFIX = '0x3056301006072a8648ce3d020106052b8104000a034200';
const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

/** Extracts the uncompressed public key from a DER-encoded secp256k1 SubjectPublicKeyInfo */
export function parseSpkiPublicKey(spki: Uint8Array): Hex {
  if (spki.length !== 88 || bytesToHex(spki.subarray(0, 23)) !== SECP256K1_SPKI_PREFIX) {
    throw new Error('KMS key is not an uncompressed secp256k1 public key');
  }
  return bytesToHex(spki.subarray(23));
}

/** Decodes a DER-encoded ECDSA signature into its `r` and `s` components */
export function parseDerSignature(der: Uint8Array): {r: bigint; s: bigint} {
  let offset = 0;

  const readByte = (): number => {
    const byte = der[offset++];
    if (byte === undefined) throw new Error('Malformed DER signature');
    return byte;
  };

  const readInteger = (): bigint => {
    if (readByte() !== 0x02) throw new Error('Malformed DER signature');
    const length = readByte();
    const value = der.subarray(offset, offset + length);
    if (length === 0 || length > 33 || value.length !== length) {
      throw new Error('Malformed DER signature');
    }
    offset += length;
    return BigInt(bytesToHex(value));
  };

  if (readByte() !== 0x30 || readByte() !== der.length - 2) {
    throw new Error('Malformed DER signature');
  }
  const r = readInteger();
  const s = readInteger();
  if (offset !== der.length || r === 0n || r >= SECP256K1_N || s === 0n || s >= SECP256K1_N) {
    throw new Error('Malformed DER signature');
  }
  return {r, s};
}

async function signHash(backend: KmsBackend, address: Address, hash: Hex): Promise<Signature> {
  const {r, s} = parseDerSignature(await backend.signDigest(hash));
  const lowS = s > SECP256K1_N / 2n ? SECP256K1_N - s : s;

  for (const yParity of [0, 1]) {
    const signature = {
      r: numberToHex(r, {size: 32}),
      s: numberToHex(lowS, {size: 32}),
      yParity,
    };
    if (isAddressEqual(await recoverAddress({hash, signature}), address)) return signature;
  }
  throw new Error('KMS signature does not recover to the key address');
}

/** Wraps a KMS backend as a viem account that signs digests remotely */
export async function toKmsAccount(backend: KmsBackend): Promise<LocalAccount> {
  const address = publicKeyToAddress(parseSpkiPublicKey(await backend.getPublicKey()));

  return toAccount({
    address,
    async sign({hash}) {
      return serializeSignature(await signHash(backend, address, hash));
    },
    async signMessage() {
      throw new Error('signMessage is not supported');
    },
    async signTransaction(transaction, options) {
      const serializer = options?.serializer ?? serializeTransaction;
      const hash = keccak256(await serializer(transaction));
      return serializer(transaction, await signHash(backend, address, hash));
    },
    async signTypedData(typedData) {
      return serializeSignature(await signHash(backend, address, hashTypedData(typedData)));
    },
  });
}
