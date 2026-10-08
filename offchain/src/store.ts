import type {Hex} from 'viem';
import type {BurnIntent} from './circle/burnIntent.js';

export type PendingIntent = {
  burnIntent: BurnIntent;
  signature: Hex;
  createdAt: number;
};

export async function loadPendingIntent(stateDir: string): Promise<PendingIntent | undefined> {
  throw new Error('not implemented');
}

export async function savePendingIntent(stateDir: string, intent: PendingIntent): Promise<void> {
  throw new Error('not implemented');
}

export async function clearPendingIntent(stateDir: string): Promise<void> {
  throw new Error('not implemented');
}
