import {describe, expect, it} from 'vitest';
import {GatewayApiError, requestAttestation} from '../../src/circle/client.js';
import {burnIntent} from '../signer/helpers.js';

const API_URL = 'https://gateway-api.circle.com';
const SIGNATURE = '0xabcdef';

const transferResponse = {
  transferId: '0b7c9e3a-6c3e-4d1f-9a55-2f7c4c1b8e10',
  attestation: '0x1234',
  signature: '0x5678',
  fees: {total: '1.0', token: 'USDC', perIntent: []},
  expirationBlock: '24000000',
};

function fakeFetch(status: number, body: unknown) {
  const requests: {url: string; init: RequestInit}[] = [];
  const fetch = async (url: string | URL | Request, init?: RequestInit) => {
    requests.push({url: String(url), init: init!});
    return new Response(typeof body === 'string' ? body : JSON.stringify(body), {status});
  };
  return {fetch: fetch as typeof globalThis.fetch, requests};
}

describe('requestAttestation', () => {
  it('posts the signed intent with uint256 fields as decimal strings', async () => {
    const {fetch, requests} = fakeFetch(201, transferResponse);
    await requestAttestation(API_URL, burnIntent.message, SIGNATURE, {fetch});

    expect(requests).toHaveLength(1);
    expect(requests[0]!.url).toBe('https://gateway-api.circle.com/v1/transfer');
    expect(requests[0]!.init.method).toBe('POST');
    expect(requests[0]!.init.headers).toEqual({'Content-Type': 'application/json'});
    expect(JSON.parse(requests[0]!.init.body as string)).toEqual([
      {
        burnIntent: {
          maxBlockHeight: (2n ** 256n - 1n).toString(),
          maxFee: '1100000',
          spec: {...burnIntent.message.spec, value: '1000000000'},
        },
        signature: SIGNATURE,
      },
    ]);
  });

  it('returns the attestation and Circle signature', async () => {
    const {fetch} = fakeFetch(201, transferResponse);
    expect(await requestAttestation(API_URL, burnIntent.message, SIGNATURE, {fetch})).toEqual({
      transferId: transferResponse.transferId,
      attestation: '0x1234',
      signature: '0x5678',
      expirationBlock: '24000000',
    });
  });

  it('throws a GatewayApiError on a non-2xx response', async () => {
    const {fetch} = fakeFetch(400, '{"message":"invalid burn intent"}');
    const request = requestAttestation(API_URL, burnIntent.message, SIGNATURE, {fetch});

    await expect(request).rejects.toBeInstanceOf(GatewayApiError);
    await expect(request).rejects.toMatchObject({
      status: 400,
      body: '{"message":"invalid burn intent"}',
    });
  });

  it('rejects a response without a hex attestation', async () => {
    const {fetch} = fakeFetch(201, {...transferResponse, attestation: 'not-hex'});
    await expect(
      requestAttestation(API_URL, burnIntent.message, SIGNATURE, {fetch}),
    ).rejects.toThrow();
  });

  it('aborts after the timeout', async () => {
    const fetch = ((_url: string, init: RequestInit) =>
      new Promise((_resolve, reject) => {
        init.signal!.addEventListener('abort', () => reject(init.signal!.reason));
      })) as unknown as typeof globalThis.fetch;

    await expect(
      requestAttestation(API_URL, burnIntent.message, SIGNATURE, {fetch, timeoutMs: 10}),
    ).rejects.toMatchObject({name: 'TimeoutError'});
  });
});
