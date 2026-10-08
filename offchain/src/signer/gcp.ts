import {createPublicKey} from 'node:crypto';
import {KeyManagementServiceClient} from '@google-cloud/kms';
import {hexToBytes} from 'viem';
import type {KmsBackend} from './types.js';

export function createGcpKmsBackend(
  keyName: string,
  client: KeyManagementServiceClient = new KeyManagementServiceClient(),
): KmsBackend {
  return {
    async getPublicKey() {
      const [{pem}] = await client.getPublicKey({name: keyName});
      if (!pem) throw new Error('GCP KMS returned no public key');
      return createPublicKey(pem).export({type: 'spki', format: 'der'});
    },
    async signDigest(digest) {
      const [{signature}] = await client.asymmetricSign({
        name: keyName,
        digest: {sha256: hexToBytes(digest)},
      });
      if (!signature) throw new Error('GCP KMS returned no signature');
      return typeof signature === 'string' ? Buffer.from(signature, 'base64') : signature;
    },
  };
}
