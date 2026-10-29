import {generateKeyPairSync, sign as nodeSign} from 'node:crypto';
import {bytesToHex, concatHex, hexToBytes, numberToHex, recoverAddress, sha256, toHex} from 'viem';
import {generatePrivateKey, privateKeyToAccount, publicKeyToAddress} from 'viem/accounts';
import {describe, expect, it} from 'vitest';
import {parseDerSignature, parseSpkiPublicKey, toKmsAccount} from '../../src/signer/account.js';
import type {KmsBackend} from '../../src/signer/types.js';
import {burnIntent, encodeDerSignature, localBackend, SECP256K1_N} from './helpers.js';

describe('toKmsAccount', () => {
  it('derives the address of the KMS key', async () => {
    const privateKey = generatePrivateKey();
    const account = await toKmsAccount(localBackend(privateKey));
    expect(account.address).toBe(privateKeyToAccount(privateKey).address);
  });

  it('signs typed data identically to a local key', async () => {
    const privateKey = generatePrivateKey();
    const account = await toKmsAccount(localBackend(privateKey));
    expect(await account.signTypedData(burnIntent)).toBe(
      await privateKeyToAccount(privateKey).signTypedData(burnIntent),
    );
  });

  it('normalizes a high-s signature', async () => {
    const privateKey = generatePrivateKey();
    const account = await toKmsAccount(localBackend(privateKey, {highS: true}));
    expect(await account.signTypedData(burnIntent)).toBe(
      await privateKeyToAccount(privateKey).signTypedData(burnIntent),
    );
  });

  it('signs transactions identically to a local key', async () => {
    const privateKey = generatePrivateKey();
    const account = await toKmsAccount(localBackend(privateKey));
    const transaction = {
      chainId: 1,
      type: 'eip1559',
      to: privateKeyToAccount(privateKey).address,
      nonce: 7,
      gas: 300_000n,
      maxFeePerGas: 30_000_000_000n,
      maxPriorityFeePerGas: 1_000_000_000n,
      data: '0x1234',
    } as const;
    expect(await account.signTransaction(transaction)).toBe(
      await privateKeyToAccount(privateKey).signTransaction(transaction),
    );
  });

  it('rejects a signature from a different key', async () => {
    const account = await toKmsAccount(
      localBackend(generatePrivateKey(), {signer: generatePrivateKey()}),
    );
    await expect(account.signTypedData(burnIntent)).rejects.toThrow(
      'KMS signature does not recover to the key address',
    );
  });

  it('rejects a non-secp256k1 key', async () => {
    const {publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
    const backend: KmsBackend = {
      async getPublicKey() {
        return publicKey.export({type: 'spki', format: 'der'});
      },
      async signDigest() {
        throw new Error('unreachable');
      },
    };
    await expect(toKmsAccount(backend)).rejects.toThrow(
      'KMS key is not an uncompressed secp256k1 public key',
    );
  });
});

describe('parseDerSignature', () => {
  it('parses signatures produced by OpenSSL', async () => {
    const {publicKey, privateKey} = generateKeyPairSync('ec', {namedCurve: 'secp256k1'});
    const address = publicKeyToAddress(
      parseSpkiPublicKey(publicKey.export({type: 'spki', format: 'der'})),
    );

    for (let i = 0; i < 16; i++) {
      const data = hexToBytes(toHex(`message ${i}`));
      const {r, s} = parseDerSignature(nodeSign('sha256', data, privateKey));
      const recovered = await Promise.all(
        [0, 1].map((yParity) =>
          recoverAddress({
            hash: sha256(data),
            signature: {r: numberToHex(r, {size: 32}), s: numberToHex(s, {size: 32}), yParity},
          }),
        ),
      );
      expect(recovered).toContain(address);
    }
  });

  it('rejects trailing bytes', () => {
    const der = encodeDerSignature(1n, 1n);
    const padded = hexToBytes(concatHex([bytesToHex(der), '0x00']));
    expect(() => parseDerSignature(padded)).toThrow('Malformed DER signature');
  });

  it('rejects values outside the curve order', () => {
    expect(() => parseDerSignature(encodeDerSignature(SECP256K1_N, 1n))).toThrow(
      'Malformed DER signature',
    );
  });
});
