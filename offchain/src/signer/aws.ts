import type {KmsBackend} from './types.js';

export function createAwsKmsBackend(keyId: string, region: string): KmsBackend {
  throw new Error('not implemented');
}
