import {describe, expect, it} from 'vitest';
import {loadConfig} from '../src/config.js';

const env = {
  CHAIN: 'mainnet',
  RPC_URL: 'https://rpc.example',
  CONTROLLER_ADDRESS: '0x1111111111111111111111111111111111111111',
  MIN_INVEST_AMOUNT: '100000000000',
  MIN_DIVEST_AMOUNT: '1000000000',
  KMS_PROVIDER: 'aws',
  AWS_KMS_KEY_ID: 'alias/keeper',
  AWS_REGION: 'us-east-1',
};

describe('loadConfig', () => {
  it('parses amounts as bigints and fills the defaults', () => {
    expect(loadConfig(env)).toEqual({
      CHAIN: 'mainnet',
      RPC_URL: 'https://rpc.example',
      CONTROLLER_ADDRESS: '0x1111111111111111111111111111111111111111',
      CIRCLE_GATEWAY_API_URL: 'https://gateway-api.circle.com',
      POLL_INTERVAL_SECONDS: 300,
      MIN_INVEST_AMOUNT: 100_000_000_000n,
      INVEST_HAIRCUT_BPS: 10n,
      MIN_DIVEST_AMOUNT: 1_000_000_000n,
      MAX_DIVEST_AMOUNT: 10_000_000_000_000n,
      BURN_INTENT_VALIDITY_BLOCKS: 7_200n,
      kms: {KMS_PROVIDER: 'aws', AWS_KMS_KEY_ID: 'alias/keeper', AWS_REGION: 'us-east-1'},
    });
  });

  it('uses the testnet Gateway API on sepolia', () => {
    expect(loadConfig({...env, CHAIN: 'sepolia'}).CIRCLE_GATEWAY_API_URL).toBe(
      'https://gateway-api-testnet.circle.com',
    );
  });

  it('lets the Gateway API URL be overridden', () => {
    expect(
      loadConfig({...env, CIRCLE_GATEWAY_API_URL: 'https://gateway.example'})
        .CIRCLE_GATEWAY_API_URL,
    ).toBe('https://gateway.example');
  });

  it('requires a supported chain', () => {
    const {CHAIN: _chain, ...withoutChain} = env;
    expect(() => loadConfig(withoutChain)).toThrow();
    expect(() => loadConfig({...env, CHAIN: 'base'})).toThrow();
  });

  it('parses a GCP key', () => {
    const {AWS_KMS_KEY_ID: _id, AWS_REGION: _region, ...rest} = env;
    expect(
      loadConfig({...rest, KMS_PROVIDER: 'gcp', GCP_KMS_KEY_NAME: 'projects/p/keys/k'}).kms,
    ).toEqual({KMS_PROVIDER: 'gcp', GCP_KMS_KEY_NAME: 'projects/p/keys/k'});
  });

  it('accepts a private key on a testnet', () => {
    const {AWS_KMS_KEY_ID: _id, AWS_REGION: _region, ...rest} = env;
    const privateKey = `0x${'11'.repeat(32)}`;
    expect(
      loadConfig({...rest, CHAIN: 'sepolia', KMS_PROVIDER: 'private-key', PRIVATE_KEY: privateKey})
        .kms,
    ).toEqual({KMS_PROVIDER: 'private-key', PRIVATE_KEY: privateKey});
  });

  it('refuses a private key on mainnet', () => {
    const {AWS_KMS_KEY_ID: _id, AWS_REGION: _region, ...rest} = env;
    expect(() =>
      loadConfig({...rest, KMS_PROVIDER: 'private-key', PRIVATE_KEY: `0x${'11'.repeat(32)}`}),
    ).toThrow('KMS_PROVIDER=private-key is only allowed on testnets');
  });

  it('rejects a malformed private key', () => {
    const {AWS_KMS_KEY_ID: _id, AWS_REGION: _region, ...rest} = env;
    expect(() =>
      loadConfig({...rest, CHAIN: 'sepolia', KMS_PROVIDER: 'private-key', PRIVATE_KEY: '0x1234'}),
    ).toThrow();
  });

  it('rejects a haircut above 100%', () => {
    expect(() => loadConfig({...env, INVEST_HAIRCUT_BPS: '10001'})).toThrow();
  });
});
