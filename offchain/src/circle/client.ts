import type {Hex} from 'viem';
import type {BurnIntent} from './burnIntent.js';

export type TransferAttestation = {
  transferId: string;
  attestation: Hex;
  signature: Hex;
  expirationBlock: string;
};

export async function requestAttestation(
  apiUrl: string,
  burnIntent: BurnIntent,
  signature: Hex,
): Promise<TransferAttestation> {
  throw new Error('not implemented');
}
