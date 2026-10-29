import {createPublicKey} from 'node:crypto';
import type {KeyManagementServiceClient} from '@google-cloud/kms';
import {bytesToHex, hashTypedData, hexToBytes, type Hex} from 'viem';
import {generatePrivateKey, privateKeyToAccount} from 'viem/accounts';
import {describe, expect, it} from 'vitest';
import {toKmsAccount} from '../../src/signer/account.js';
import {createGcpKmsBackend} from '../../src/signer/gcp.js';
import {burnIntent, localBackend} from './helpers.js';

const KEY_NAME =
  'projects/aave/locations/global/keyRings/reinvestment/cryptoKeys/keeper/cryptoKeyVersions/1';

type SignRequest = {name: string; digest: {sha256: Uint8Array}};

function fakeClient(privateKey: Hex, {empty = false}: {empty?: boolean} = {}) {
  const key = localBackend(privateKey);
  const requests: unknown[] = [];
  const client = {
    async getPublicKey(request: {name: string}) {
      requests.push(request);
      if (empty) return [{}];
      const der = Buffer.from(await key.getPublicKey());
      const pem = createPublicKey({key: der, format: 'der', type: 'spki'}).export({
        type: 'spki',
        format: 'pem',
      });
      return [{pem}];
    },
    async asymmetricSign(request: SignRequest) {
      requests.push(request);
      if (empty) return [{}];
      return [{signature: await key.signDigest(bytesToHex(request.digest.sha256))}];
    },
  };
  return {client: client as unknown as KeyManagementServiceClient, requests};
}

describe('createGcpKmsBackend', () => {
  it('signs identically to a local key', async () => {
    const privateKey = generatePrivateKey();
    const {client} = fakeClient(privateKey);
    const account = await toKmsAccount(createGcpKmsBackend(KEY_NAME, client));
    const local = privateKeyToAccount(privateKey);

    expect(account.address).toBe(local.address);
    expect(await account.signTypedData(burnIntent)).toBe(await local.signTypedData(burnIntent));
  });

  it('requests a signature over the raw sha256 digest field', async () => {
    const {client, requests} = fakeClient(generatePrivateKey());
    const account = await toKmsAccount(createGcpKmsBackend(KEY_NAME, client));
    await account.signTypedData(burnIntent);

    expect(requests).toEqual([
      {name: KEY_NAME},
      {name: KEY_NAME, digest: {sha256: hexToBytes(hashTypedData(burnIntent))}},
    ]);
  });

  it('rejects an empty public key response', async () => {
    const {client} = fakeClient(generatePrivateKey(), {empty: true});
    await expect(createGcpKmsBackend(KEY_NAME, client).getPublicKey()).rejects.toThrow(
      'GCP KMS returned no public key',
    );
  });

  it('rejects an empty signature response', async () => {
    const {client} = fakeClient(generatePrivateKey(), {empty: true});
    await expect(
      createGcpKmsBackend(KEY_NAME, client).signDigest(hashTypedData(burnIntent)),
    ).rejects.toThrow('GCP KMS returned no signature');
  });
});
