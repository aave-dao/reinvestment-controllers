import {decodeAbiParameters, type PublicClient, type WalletClient} from 'viem';
import {generatePrivateKey, privateKeyToAccount} from 'viem/accounts';
import {beforeEach, describe, expect, it, vi} from 'vitest';
import {encodeBurnIntent} from '../src/circle/burnIntent.js';
import {requestAttestation} from '../src/circle/client.js';
import type {Config} from '../src/config.js';
import type {Deployment} from '../src/controller.js';
import {
  getShortfall,
  planDivest,
  planInvest,
  tick,
  type KeeperContext,
  type KeeperState,
} from '../src/keeper.js';

vi.mock('../src/circle/client.js', () => ({requestAttestation: vi.fn()}));

const USDC = 1_000_000n;
const MAX_FEE = 1_100_000n;

const config: Config = {
  RPC_MAINNET: 'https://rpc.example',
  CONTROLLER_ADDRESS: '0x1111111111111111111111111111111111111111',
  CIRCLE_GATEWAY_API_URL: 'https://gateway-api.circle.com',
  POLL_INTERVAL_SECONDS: 300,
  MIN_INVEST_AMOUNT: 100_000n * USDC,
  MIN_DIVEST_AMOUNT: 1_000n * USDC,
  MAX_DIVEST_AMOUNT: 10_000_000n * USDC,
  BURN_INTENT_VALIDITY_BLOCKS: 7_200n,
  kms: {KMS_PROVIDER: 'aws', AWS_KMS_KEY_ID: 'alias/keeper', AWS_REGION: 'us-east-1'},
};

const deployment: Deployment = {
  controller: '0x1111111111111111111111111111111111111111',
  hub: '0x2222222222222222222222222222222222222222',
  assetId: 3n,
  gatewayWallet: '0x3333333333333333333333333333333333333333',
  gatewayMinter: '0x4444444444444444444444444444444444444444',
  usdc: '0x5555555555555555555555555555555555555555',
  domain: 0,
};

function balancedState(overrides: Partial<KeeperState> = {}): KeeperState {
  return {
    blockNumber: 24_000_000n,
    timestamp: 1_760_000_000n,
    paused: false,
    supplied: 100_000_000n * USDC,
    idle: 20_000_000n * USDC,
    swept: 30_000_000n * USDC,
    maxFee: MAX_FEE,
    liquidBufferBps: 2_000n,
    exposureCapAbs: 50_000_000n * USDC,
    exposureCapBps: 5_000n,
    investableAmount: 0n,
    lastInvestTimestamp: 0n,
    investMinDelay: 86_400n,
    ...overrides,
  };
}

describe('getShortfall', () => {
  it('is zero when idle covers the buffer and swept is within the cap', () => {
    expect(getShortfall(balancedState())).toBe(0n);
  });

  it('rounds the liquid buffer up like percentMulUp', () => {
    expect(
      getShortfall(
        balancedState({supplied: 100_001n, liquidBufferBps: 1_000n, idle: 10_000n, swept: 0n}),
      ),
    ).toBe(1n);
  });

  it('measures over-exposure against the lower of the absolute and relative caps', () => {
    expect(getShortfall(balancedState({exposureCapAbs: 25_000_000n * USDC}))).toBe(
      5_000_000n * USDC,
    );
    expect(getShortfall(balancedState({exposureCapBps: 2_000n}))).toBe(10_000_000n * USDC);
  });

  it('takes the larger of the liquidity and exposure shortfalls', () => {
    expect(getShortfall(balancedState({idle: 15_000_000n * USDC, exposureCapBps: 2_800n}))).toBe(
      5_000_000n * USDC,
    );
  });
});

describe('planDivest', () => {
  it('does nothing below the minimum divest', () => {
    expect(planDivest(balancedState({idle: 19_999_500n * USDC}), config)).toBeUndefined();
  });

  it('nets the pre-paid fee out of the shortfall', () => {
    expect(planDivest(balancedState({idle: 15_000_000n * USDC}), config)).toBe(
      5_000_000n * USDC - MAX_FEE,
    );
  });

  it('caps a single divest at the per-transfer maximum', () => {
    expect(planDivest(balancedState({idle: 5_000_000n * USDC}), config)).toBe(10_000_000n * USDC);
  });

  it('withdraws at least one unit when the fee alone covers the shortfall', () => {
    expect(
      planDivest(balancedState({idle: 20_000_000n * USDC - 500_000n}), {
        ...config,
        MIN_DIVEST_AMOUNT: 1n,
      }),
    ).toBe(1n);
  });

  it('never divests more than swept less the fee', () => {
    expect(planDivest(balancedState({idle: 0n, swept: 3_000_000n * USDC}), config)).toBe(
      3_000_000n * USDC - MAX_FEE,
    );
    expect(planDivest(balancedState({idle: 0n, swept: MAX_FEE}), config)).toBeUndefined();
  });
});

describe('planInvest', () => {
  const investable = balancedState({investableAmount: 500_000n * USDC});

  it('invests the full investable amount', () => {
    expect(planInvest(investable, config)).toBe(500_000n * USDC);
  });

  it('does nothing below the minimum invest', () => {
    expect(planInvest({...investable, investableAmount: 99_999n * USDC}, config)).toBeUndefined();
  });

  it('waits for the minimum delay', () => {
    expect(
      planInvest({...investable, lastInvestTimestamp: investable.timestamp - 86_399n}, config),
    ).toBeUndefined();
  });

  it('does not invest while there is a shortfall', () => {
    expect(planInvest({...investable, idle: 15_000_000n * USDC}, config)).toBeUndefined();
  });
});

describe('tick', () => {
  const account = privateKeyToAccount(generatePrivateKey());
  const attestation = {
    transferId: 'id',
    attestation: '0xa77e57' as const,
    signature: '0x5167' as const,
    expirationBlock: '24000050',
  };

  let state: KeeperState;
  let writes: {functionName: string; args: readonly unknown[]}[];
  let fee: {balance: bigint; allowance: bigint};
  let ctx: KeeperContext;

  beforeEach(() => {
    state = balancedState();
    writes = [];
    fee = {balance: 10n * USDC, allowance: 10n * USDC};
    vi.mocked(requestAttestation).mockReset().mockResolvedValue(attestation);

    const views: Record<string, () => unknown> = {
      paused: () => state.paused,
      getAddedAssets: () => state.supplied,
      getAssetLiquidity: () => state.idle,
      getAssetSwept: () => state.swept,
      getMaxFee: () => state.maxFee,
      getLiquidBufferBps: () => state.liquidBufferBps,
      getExposureCapAbs: () => state.exposureCapAbs,
      getExposureCapBps: () => state.exposureCapBps,
      getInvestableAmount: () => state.investableAmount,
      getLastInvestTimestamp: () => state.lastInvestTimestamp,
      getInvestMinDelay: () => state.investMinDelay,
      withdrawalDelay: () => 100n,
      balanceOf: () => fee.balance,
      allowance: () => fee.allowance,
    };

    const publicClient = {
      getBlock: async () => ({number: state.blockNumber, timestamp: state.timestamp}),
      readContract: async ({functionName}: {functionName: string}) => views[functionName]!(),
      simulateContract: async (request: {functionName: string; args: readonly unknown[]}) => ({
        request,
      }),
      waitForTransactionReceipt: async () => ({status: 'success'}),
    };
    const walletClient = {
      writeContract: async (request: {functionName: string; args: readonly unknown[]}) => {
        writes.push({functionName: request.functionName, args: request.args});
        return '0xhash';
      },
    };

    ctx = {
      config,
      account,
      deployment,
      publicClient: publicClient as unknown as PublicClient,
      walletClient: walletClient as unknown as WalletClient,
    };
  });

  it('does nothing while the controller is paused', async () => {
    state = balancedState({paused: true, idle: 0n});
    expect(await tick(ctx)).toBe('paused');
    expect(writes).toEqual([]);
  });

  it('invests when nothing needs divesting', async () => {
    state = balancedState({investableAmount: 500_000n * USDC});
    expect(await tick(ctx)).toBe('invested');
    expect(writes).toEqual([{functionName: 'invest', args: [500_000n * USDC]}]);
  });

  it('divests the shortfall through a signed, attested burn intent', async () => {
    state = balancedState({idle: 15_000_000n * USDC, investableAmount: 500_000n * USDC});
    expect(await tick(ctx)).toBe('divested');

    const [burnIntent, signature] = vi.mocked(requestAttestation).mock.calls[0]!.slice(1) as [
      Parameters<typeof encodeBurnIntent>[0],
      `0x${string}`,
    ];
    expect(burnIntent.spec.value).toBe(5_000_000n * USDC - MAX_FEE);
    expect(burnIntent.maxFee).toBe(MAX_FEE);
    expect(burnIntent.maxBlockHeight).toBe(state.blockNumber + 100n + 7_200n);
    expect(decodeAbiParameters([{type: 'bytes'}, {type: 'bytes'}], signature)[1]).toBe(
      encodeBurnIntent(burnIntent),
    );
    expect(writes).toEqual([
      {
        functionName: 'divest',
        args: [5_000_000n * USDC - MAX_FEE, attestation.attestation, attestation.signature],
      },
    ]);
    expect(ctx.pending).toBeUndefined();
  });

  it('resends the same burn intent after a failed attestation request', async () => {
    state = balancedState({idle: 15_000_000n * USDC});
    vi.mocked(requestAttestation).mockRejectedValueOnce(new Error('timeout'));

    await expect(tick(ctx)).rejects.toThrow('timeout');
    const pending = ctx.pending;
    expect(pending).toBeDefined();
    expect(writes).toEqual([]);

    expect(await tick(ctx)).toBe('divested');
    const [first, second] = vi.mocked(requestAttestation).mock.calls;
    expect(second).toEqual(first);
    expect(writes).toHaveLength(1);
  });

  it('drops an attestation that has expired', async () => {
    state = balancedState({idle: 15_000_000n * USDC, blockNumber: 24_000_050n});
    expect(await tick(ctx)).toBe('expired');
    expect(writes).toEqual([]);
    expect(ctx.pending).toBeUndefined();
  });

  it('refuses to sign when the keeper cannot fund the fee', async () => {
    state = balancedState({idle: 15_000_000n * USDC});
    fee.allowance = 0n;

    await expect(tick(ctx)).rejects.toThrow('allowance');
    expect(requestAttestation).not.toHaveBeenCalled();
    expect(ctx.pending).toBeUndefined();
  });

  it('throws when the transaction reverts', async () => {
    state = balancedState({investableAmount: 500_000n * USDC});
    ctx.publicClient.waitForTransactionReceipt = (async () => ({
      status: 'reverted',
    })) as unknown as PublicClient['waitForTransactionReceipt'];

    await expect(tick(ctx)).rejects.toThrow('invest reverted in 0xhash');
  });
});
