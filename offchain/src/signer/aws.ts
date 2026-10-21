import {GetPublicKeyCommand, KMSClient, SignCommand} from '@aws-sdk/client-kms';
import {hexToBytes} from 'viem';
import type {KmsBackend} from './types.js';

export function createAwsKmsBackend(
  keyId: string,
  region: string,
  client: KMSClient = new KMSClient({region}),
): KmsBackend {
  return {
    async getPublicKey() {
      const {PublicKey} = await client.send(new GetPublicKeyCommand({KeyId: keyId}));
      if (!PublicKey) throw new Error('AWS KMS returned no public key');
      return PublicKey;
    },
    async signDigest(digest) {
      const {Signature} = await client.send(
        new SignCommand({
          KeyId: keyId,
          Message: hexToBytes(digest),
          MessageType: 'DIGEST',
          SigningAlgorithm: 'ECDSA_SHA_256',
        }),
      );
      if (!Signature) throw new Error('AWS KMS returned no signature');
      return Signature;
    },
  };
}
