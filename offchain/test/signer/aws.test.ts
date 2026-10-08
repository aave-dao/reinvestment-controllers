import {GetPublicKeyCommand, SignCommand, type KMSClient} from '@aws-sdk/client-kms';
import {bytesToHex, hashTypedData, hexToBytes, type Hex} from 'viem';
import {generatePrivateKey, privateKeyToAccount} from 'viem/accounts';
import {describe, expect, it} from 'vitest';
import {toKmsAccount} from '../../src/signer/account.js';
import {createAwsKmsBackend} from '../../src/signer/aws.js';
import {burnIntent, localBackend} from './helpers.js';

const KEY_ID = 'alias/reinvestment-keeper';

function fakeClient(privateKey: Hex, {empty = false}: {empty?: boolean} = {}) {
  const key = localBackend(privateKey);
  const requests: unknown[] = [];
  const client = {
    async send(command: GetPublicKeyCommand | SignCommand) {
      requests.push(command.input);
      if (empty) return {};
      if (command instanceof GetPublicKeyCommand) return {PublicKey: await key.getPublicKey()};
      return {Signature: await key.signDigest(bytesToHex(command.input.Message!))};
    },
  };
  return {client: client as unknown as KMSClient, requests};
}

describe('createAwsKmsBackend', () => {
  it('signs identically to a local key', async () => {
    const privateKey = generatePrivateKey();
    const {client} = fakeClient(privateKey);
    const account = await toKmsAccount(createAwsKmsBackend(KEY_ID, 'us-east-1', client));
    const local = privateKeyToAccount(privateKey);

    expect(account.address).toBe(local.address);
    expect(await account.signTypedData(burnIntent)).toBe(await local.signTypedData(burnIntent));
  });

  it('requests an ECDSA_SHA_256 signature over the raw digest', async () => {
    const {client, requests} = fakeClient(generatePrivateKey());
    const account = await toKmsAccount(createAwsKmsBackend(KEY_ID, 'us-east-1', client));
    await account.signTypedData(burnIntent);

    expect(requests).toEqual([
      {KeyId: KEY_ID},
      {
        KeyId: KEY_ID,
        Message: hexToBytes(hashTypedData(burnIntent)),
        MessageType: 'DIGEST',
        SigningAlgorithm: 'ECDSA_SHA_256',
      },
    ]);
  });

  it('rejects an empty public key response', async () => {
    const {client} = fakeClient(generatePrivateKey(), {empty: true});
    await expect(createAwsKmsBackend(KEY_ID, 'us-east-1', client).getPublicKey()).rejects.toThrow(
      'AWS KMS returned no public key',
    );
  });

  it('rejects an empty signature response', async () => {
    const {client} = fakeClient(generatePrivateKey(), {empty: true});
    await expect(
      createAwsKmsBackend(KEY_ID, 'us-east-1', client).signDigest(hashTypedData(burnIntent)),
    ).rejects.toThrow('AWS KMS returned no signature');
  });
});
