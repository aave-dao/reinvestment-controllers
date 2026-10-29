import {setTimeout as sleep} from 'node:timers/promises';
import type {TickResult} from './keeper.js';
import {describeError, type Log} from './log.js';

export type RunLoopOptions = {
  tick: () => Promise<TickResult>;
  intervalMs: number;
  signal: AbortSignal;
  log: Log;
};

/** Ticks until aborted, re-running at once while a multi-part divest is still unwinding */
export async function runLoop({tick, intervalMs, signal, log}: RunLoopOptions): Promise<void> {
  while (!signal.aborted) {
    let result: TickResult | undefined;
    try {
      result = await tick();
      log('tick', {result});
    } catch (error) {
      log('tick_failed', {error: describeError(error)});
    }

    if (result === 'divested' || result === 'expired') continue;

    try {
      await sleep(intervalMs, undefined, {signal});
    } catch {
      return;
    }
  }
}
