import {generatePrivateKey, privateKeyToAccount} from 'viem/accounts';
import {describe, expect, it} from 'vitest';
import {createKeeperAccount} from '../../src/signer/index.js';
import {burnIntent} from './helpers.js';

describe('createKeeperAccount', () => {
  it('signs with the configured private key', async () => {
    const privateKey = generatePrivateKey();
    const account = await createKeeperAccount({
      KMS_PROVIDER: 'private-key',
      PRIVATE_KEY: privateKey,
    });
    const local = privateKeyToAccount(privateKey);

    expect(account.address).toBe(local.address);
    expect(await account.signTypedData(burnIntent)).toBe(await local.signTypedData(burnIntent));
  });
});
