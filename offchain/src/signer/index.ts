import type {LocalAccount} from 'viem';
import {privateKeyToAccount} from 'viem/accounts';
import type {CloudKmsConfig, KmsConfig} from '../config.js';
import {toKmsAccount} from './account.js';
import type {KmsBackend} from './types.js';

export async function createKmsBackend(config: CloudKmsConfig): Promise<KmsBackend> {
  switch (config.KMS_PROVIDER) {
    case 'aws': {
      const {createAwsKmsBackend} = await import('./aws.js');
      return createAwsKmsBackend(config.AWS_KMS_KEY_ID, config.AWS_REGION);
    }
    case 'gcp': {
      const {createGcpKmsBackend} = await import('./gcp.js');
      return createGcpKmsBackend(config.GCP_KMS_KEY_NAME);
    }
  }
}

export async function createKeeperAccount(config: KmsConfig): Promise<LocalAccount> {
  if (config.KMS_PROVIDER === 'private-key') return privateKeyToAccount(config.PRIVATE_KEY);
  return toKmsAccount(await createKmsBackend(config));
}
