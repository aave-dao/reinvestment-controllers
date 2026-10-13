import {describe, expect, it, vi} from 'vitest';
import type {TickResult} from '../src/keeper.js';
import {runLoop} from '../src/loop.js';

const HOUR = 3_600_000;

function ticks(results: (TickResult | Error)[], shutdown: AbortController) {
  return vi.fn(async () => {
    const next = results.shift();
    if (results.length === 0) shutdown.abort();
    if (next instanceof Error) throw next;
    return next!;
  });
}

describe('runLoop', () => {
  it('does not tick once aborted', async () => {
    const shutdown = new AbortController();
    shutdown.abort();
    const tick = vi.fn();

    await runLoop({tick, intervalMs: HOUR, signal: shutdown.signal, log: vi.fn()});
    expect(tick).not.toHaveBeenCalled();
  });

  it('stops while sleeping between ticks when aborted', async () => {
    const shutdown = new AbortController();
    const tick = vi.fn(async (): Promise<TickResult> => 'idle');
    setTimeout(() => shutdown.abort(), 10);

    await runLoop({tick, intervalMs: HOUR, signal: shutdown.signal, log: vi.fn()});
    expect(tick).toHaveBeenCalledTimes(1);
  });

  it('ticks again without waiting while a divest is unwinding', async () => {
    const shutdown = new AbortController();
    const tick = ticks(['divested', 'expired', 'divested', 'idle'], shutdown);
    const log = vi.fn();

    await runLoop({tick, intervalMs: HOUR, signal: shutdown.signal, log});
    expect(tick).toHaveBeenCalledTimes(4);
    expect(log.mock.calls.map(([, fields]) => fields.result)).toEqual([
      'divested',
      'expired',
      'divested',
      'idle',
    ]);
  });

  it('logs a failed tick and keeps running', async () => {
    const shutdown = new AbortController();
    const tick = ticks([new Error('rpc down'), 'idle'], shutdown);
    const log = vi.fn();

    await runLoop({tick, intervalMs: 1, signal: shutdown.signal, log});
    expect(log.mock.calls).toEqual([
      ['tick_failed', {error: 'rpc down'}],
      ['tick', {result: 'idle'}],
    ]);
  });
});
