import type {Hex} from 'viem';
import {z} from 'zod';
import type {BurnIntent} from './burnIntent.js';

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

export type TransferAttestation = z.infer<typeof transferResponseSchema>;

export class GatewayApiError extends Error {
  constructor(
    readonly status: number,
    readonly body: string,
  ) {
    super(`Gateway API responded ${status}: ${body}`);
  }
}

export type RequestAttestationOptions = {
  fetch?: typeof fetch;
  timeoutMs?: number;
};

/** Submits a single signed burn intent to `POST /v1/transfer`, once, without retrying */
export async function requestAttestation(
  apiUrl: string,
  burnIntent: BurnIntent,
  signature: Hex,
  {fetch: fetchFn = fetch, timeoutMs = 30_000}: RequestAttestationOptions = {},
): Promise<TransferAttestation> {
  const response = await fetchFn(new URL('/v1/transfer', apiUrl), {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify([{burnIntent, signature}], (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value,
    ),
    signal: AbortSignal.timeout(timeoutMs),
  });

  const body = await response.text();
  if (!response.ok) throw new GatewayApiError(response.status, body);
  return transferResponseSchema.parse(JSON.parse(body));
}
