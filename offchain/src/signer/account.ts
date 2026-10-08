import type {LocalAccount} from 'viem';
import type {KmsBackend} from './types.js';

export async function toKmsAccount(backend: KmsBackend): Promise<LocalAccount> {
  throw new Error('not implemented');
}
