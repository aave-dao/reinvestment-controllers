import type {KmsBackend} from './types.js';

export function createGcpKmsBackend(keyName: string): KmsBackend {
  throw new Error('not implemented');
}
