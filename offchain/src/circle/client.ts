import {parseUnits, type Address, type Hex} from 'viem';
import {z} from 'zod';
import type {BurnIntent} from './burnIntent.js';

const USDC_DECIMALS = 6;

const hex = z
  .string()
  .regex(/^0x[0-9a-fA-F]+$/)
  .transform((value) => value as Hex);

const transferResponseSchema = z.object({
  transferId: z.string(),
  attestation: hex,
  signature: hex,
  expirationBlock: z.string(),
});

const balancesResponseSchema = z.object({
  balances: z.array(
    z.object({
      domain: z.number(),
      balance: z.string().regex(/^\d+(\.\d+)?$/),
    }),
  ),
});

export type TransferAttestation = z.infer<typeof transferResponseSchema>;

export class GatewayApiError extends Error {
  constructor(
    readonly status: number,
    readonly body: string,
  ) {
    super(`Gateway API responded ${status}: ${body}`);
  }
}

export type GatewayRequestOptions = {
  fetch?: typeof fetch;
  timeoutMs?: number;
};

async function post(
  apiUrl: string,
  path: string,
  payload: unknown,
  {fetch: fetchFn = fetch, timeoutMs = 30_000}: GatewayRequestOptions,
): Promise<unknown> {
  const response = await fetchFn(new URL(path, apiUrl), {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(payload, (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value,
    ),
    signal: AbortSignal.timeout(timeoutMs),
  });

  const body = await response.text();
  if (!response.ok) throw new GatewayApiError(response.status, body);
  return JSON.parse(body);
}

/**
 * Submits a single signed burn intent to `POST /v1/transfer`, once, without retrying. The
 * controller signs through ERC-1271, so `contractSigner` makes Gateway verify the signature with
 * its `isValidSignature` rather than as an ECDSA signature
 */
export async function requestAttestation(
  apiUrl: string,
  burnIntent: BurnIntent,
  signature: Hex,
  options: GatewayRequestOptions = {},
): Promise<TransferAttestation> {
  const response = await post(
    apiUrl,
    '/v1/transfer',
    [{burnIntent, signature, contractSigner: true}],
    options,
  );
  return transferResponseSchema.parse(response);
}

/**
 * Reads the depositor's available USDC balance as Circle has indexed it, in base units. Circle
 * only counts finalized blocks, so this lags the on-chain Gateway balance by about two epochs
 */
export async function getGatewayBalance(
  apiUrl: string,
  domain: number,
  depositor: Address,
  options: GatewayRequestOptions = {},
): Promise<bigint> {
  const response = await post(
    apiUrl,
    '/v1/balances',
    {token: 'USDC', sources: [{domain, depositor}]},
    options,
  );
  const entry = balancesResponseSchema
    .parse(response)
    .balances.find((balance) => balance.domain === domain);
  return entry ? parseUnits(entry.balance, USDC_DECIMALS) : 0n;
}
