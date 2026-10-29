import {randomBytes} from 'node:crypto';
import {
  bytesToHex,
  erc20Abi,
  type Hash,
  type Hex,
  type LocalAccount,
  type PublicClient,
  type WalletClient,
} from 'viem';
import {controllerAbi} from './abi/controller.js';
import {gatewayWalletAbi} from './abi/gatewayWallet.js';
import {hubAbi} from './abi/hub.js';
import {buildBurnIntent, signBurnIntent, type BurnIntent} from './circle/burnIntent.js';
import {
  GatewayApiError,
  getGatewayBalance,
  requestAttestation,
  type TransferAttestation,
} from './circle/client.js';
import type {Config} from './config.js';
import type {Deployment} from './deployment.js';

const PERCENTAGE_FACTOR = 10_000n;

export type PendingDivest = {
  burnIntent: BurnIntent;
  signature: Hex;
  createdAt: number;
  attestation?: TransferAttestation;
};

export type KeeperContext = {
  config: Config;
  account: LocalAccount;
  publicClient: PublicClient;
  walletClient: WalletClient;
  deployment: Deployment;
  pending?: PendingDivest;
};

export type KeeperState = {
  blockNumber: bigint;
  timestamp: bigint;
  paused: boolean;
  supplied: bigint;
  idle: bigint;
  swept: bigint;
  maxFee: bigint;
  liquidBufferBps: bigint;
  exposureCapAbs: bigint;
  exposureCapBps: bigint;
  investableAmount: bigint;
  lastInvestTimestamp: bigint;
  investMinDelay: bigint;
};

export type TickResult =
  | 'paused'
  | 'idle'
  | 'invested'
  | 'divested'
  | 'expired'
  | 'awaiting-balance';

const min = (...values: bigint[]) => values.reduce((a, b) => (b < a ? b : a));
const max = (...values: bigint[]) => values.reduce((a, b) => (b > a ? b : a));
const saturatingSub = (a: bigint, b: bigint) => (a > b ? a - b : 0n);
const percentMulUp = (value: bigint, bps: bigint) =>
  (value * bps + PERCENTAGE_FACTOR - 1n) / PERCENTAGE_FACTOR;

const getExposureCap = (state: KeeperState) =>
  min(state.exposureCapAbs, (state.supplied * state.exposureCapBps) / PERCENTAGE_FACTOR);

/** Amount that must return to the Hub to restore the liquid buffer and respect the exposure cap */
export function getShortfall(state: KeeperState): bigint {
  return max(
    saturatingSub(percentMulUp(state.supplied, state.liquidBufferBps), state.idle),
    saturatingSub(state.swept, getExposureCap(state)),
  );
}

/**
 * Sizes the next divest, whose `amount + maxFee` returns to the Hub, capped per transfer. Waits
 * until idle falls below the divest trigger, then restores the full liquid buffer, so withdrawals
 * right after a recall don't each start another. Over-exposure divests without waiting. A trigger
 * above the liquid buffer is clamped to it. Returns 0 when nothing should be divested
 */
export function planDivest(
  state: KeeperState,
  config: Pick<Config, 'MIN_DIVEST_AMOUNT' | 'MAX_DIVEST_AMOUNT' | 'DIVEST_TRIGGER_BPS'>,
): bigint {
  const triggerBps = min(config.DIVEST_TRIGGER_BPS ?? state.liquidBufferBps, state.liquidBufferBps);
  const overExposed = state.swept > getExposureCap(state);
  if (!overExposed && state.idle >= percentMulUp(state.supplied, triggerBps)) return 0n;

  const shortfall = getShortfall(state);
  if (shortfall === 0n || shortfall < config.MIN_DIVEST_AMOUNT) return 0n;

  const withdrawable = saturatingSub(state.swept, state.maxFee);
  return min(max(shortfall - state.maxFee, 1n), config.MAX_DIVEST_AMOUNT, withdrawable);
}

/**
 * Sizes the next invest below the investable amount read now, since interest accrued before the
 * transaction lands grows the liquid buffer and shrinks what `invest` will accept.
 * Returns 0 when nothing should be invested
 */
export function planInvest(
  state: KeeperState,
  config: Pick<Config, 'MIN_INVEST_AMOUNT' | 'INVEST_HAIRCUT_BPS'>,
): bigint {
  if (getShortfall(state) > 0n) return 0n;
  if (state.timestamp < state.lastInvestTimestamp + state.investMinDelay) return 0n;

  const haircut = (state.investableAmount * config.INVEST_HAIRCUT_BPS) / PERCENTAGE_FACTOR;
  const amount = state.investableAmount - haircut;
  return amount >= config.MIN_INVEST_AMOUNT ? amount : 0n;
}

export async function readState(ctx: KeeperContext): Promise<KeeperState> {
  const {publicClient: client, deployment} = ctx;
  const controller = {address: deployment.controller, abi: controllerAbi} as const;
  const hub = {address: deployment.hub, abi: hubAbi, args: [deployment.assetId]} as const;

  const [
    block,
    paused,
    supplied,
    idle,
    swept,
    maxFee,
    liquidBufferBps,
    exposureCapAbs,
    exposureCapBps,
    investableAmount,
    lastInvestTimestamp,
    investMinDelay,
  ] = await Promise.all([
    client.getBlock(),
    client.readContract({...controller, functionName: 'paused'}),
    client.readContract({...hub, functionName: 'getAddedAssets'}),
    client.readContract({...hub, functionName: 'getAssetLiquidity'}),
    client.readContract({...hub, functionName: 'getAssetSwept'}),
    client.readContract({...controller, functionName: 'getMaxFee'}),
    client.readContract({...controller, functionName: 'getLiquidBufferBps'}),
    client.readContract({...controller, functionName: 'getExposureCapAbs'}),
    client.readContract({...controller, functionName: 'getExposureCapBps'}),
    client.readContract({...controller, functionName: 'getInvestableAmount'}),
    client.readContract({...controller, functionName: 'getLastInvestTimestamp'}),
    client.readContract({...controller, functionName: 'getInvestMinDelay'}),
  ]);

  return {
    blockNumber: block.number,
    timestamp: block.timestamp,
    paused,
    supplied,
    idle,
    swept,
    maxFee,
    liquidBufferBps,
    exposureCapAbs,
    exposureCapBps,
    investableAmount,
    lastInvestTimestamp,
    investMinDelay,
  };
}

/**
 * Runs one keeper step: settles a pending divest, starts a new one, or invests. Only an attested
 * divest proceeds while the Gateway balance is unsettled, since its attestation expires
 */
export async function tick(ctx: KeeperContext): Promise<TickResult> {
  const state = await readState(ctx);
  if (state.paused) return 'paused';

  if (!ctx.pending?.attestation) {
    const balance = await getSettledGatewayBalance(ctx);
    if (balance === undefined) return 'awaiting-balance';

    if (!ctx.pending) {
      const amount = planDivest(state, ctx.config);
      if (amount > 0n) {
        if (balance < amount + state.maxFee) return 'awaiting-balance';
        ctx.pending = await createPendingDivest(ctx, state, amount);
      }
    } else if (balance < ctx.pending.burnIntent.spec.value + ctx.pending.burnIntent.maxFee) {
      return 'awaiting-balance';
    }
  }
  if (ctx.pending) return settlePendingDivest(ctx, ctx.pending, state.blockNumber);

  const amount = planInvest(state, ctx.config);
  if (amount === 0n) return 'idle';

  const {request} = await ctx.publicClient.simulateContract({
    account: ctx.account,
    address: ctx.deployment.controller,
    abi: controllerAbi,
    functionName: 'invest',
    args: [amount],
  });
  await confirm(ctx, 'invest', await ctx.walletClient.writeContract(request));
  return 'invested';
}

/**
 * The controller's Gateway balance, or undefined while Circle and the finalized chain disagree on
 * it. Circle counts only finalized blocks and nets out balance reserved by an attestation until
 * its burn lands or it expires, so a mismatch means a transfer is in flight
 */
async function getSettledGatewayBalance(ctx: KeeperContext): Promise<bigint | undefined> {
  const [indexed, onchain] = await Promise.all([
    getGatewayBalance(
      ctx.config.CIRCLE_GATEWAY_API_URL,
      ctx.deployment.domain,
      ctx.deployment.controller,
    ),
    ctx.publicClient.readContract({
      address: ctx.deployment.gatewayWallet,
      abi: gatewayWalletAbi,
      functionName: 'availableBalance',
      args: [ctx.deployment.usdc, ctx.deployment.controller],
      blockTag: 'finalized',
    }),
  ]);
  return indexed === onchain ? indexed : undefined;
}

async function createPendingDivest(
  ctx: KeeperContext,
  state: KeeperState,
  amount: bigint,
): Promise<PendingDivest> {
  await assertFeeFunding(ctx, state.maxFee);

  const withdrawalDelay = await ctx.publicClient.readContract({
    address: ctx.deployment.gatewayWallet,
    abi: gatewayWalletAbi,
    functionName: 'withdrawalDelay',
  });
  const burnIntent = buildBurnIntent({
    ...ctx.deployment,
    value: amount,
    maxFee: state.maxFee,
    maxBlockHeight: state.blockNumber + withdrawalDelay + ctx.config.BURN_INTENT_VALIDITY_BLOCKS,
    salt: bytesToHex(randomBytes(32)),
  });

  return {
    burnIntent,
    signature: await signBurnIntent(ctx.account, burnIntent),
    createdAt: Date.now(),
  };
}

/**
 * Attests and submits the pending divest. A 400 means Circle rejected the intent or already
 * attested it, so it is dropped and the next divest uses a new salt once the reserved balance is
 * released
 */
async function settlePendingDivest(
  ctx: KeeperContext,
  pending: PendingDivest,
  blockNumber: bigint,
): Promise<TickResult> {
  try {
    pending.attestation ??= await requestAttestation(
      ctx.config.CIRCLE_GATEWAY_API_URL,
      pending.burnIntent,
      pending.signature,
    );
  } catch (error) {
    if (error instanceof GatewayApiError && error.status === 400) ctx.pending = undefined;
    throw error;
  }

  if (blockNumber >= BigInt(pending.attestation.expirationBlock)) {
    ctx.pending = undefined;
    return 'expired';
  }

  const {request} = await ctx.publicClient.simulateContract({
    account: ctx.account,
    address: ctx.deployment.controller,
    abi: controllerAbi,
    functionName: 'divest',
    args: [
      pending.burnIntent.spec.value,
      pending.attestation.attestation,
      pending.attestation.signature,
    ],
  });
  const hash = await ctx.walletClient.writeContract(request);
  ctx.pending = undefined;
  await confirm(ctx, 'divest', hash);
  return 'divested';
}

async function assertFeeFunding(ctx: KeeperContext, maxFee: bigint): Promise<void> {
  if (maxFee === 0n) return;

  const usdc = {address: ctx.deployment.usdc, abi: erc20Abi} as const;
  const [balance, allowance] = await Promise.all([
    ctx.publicClient.readContract({
      ...usdc,
      functionName: 'balanceOf',
      args: [ctx.account.address],
    }),
    ctx.publicClient.readContract({
      ...usdc,
      functionName: 'allowance',
      args: [ctx.account.address, ctx.deployment.controller],
    }),
  ]);

  if (balance < maxFee) {
    throw new Error(`Keeper holds ${balance} USDC, below the ${maxFee} divest fee`);
  }
  if (allowance < maxFee) {
    throw new Error(`Keeper allowance of ${allowance} USDC is below the ${maxFee} divest fee`);
  }
}

async function confirm(ctx: KeeperContext, label: string, hash: Hash): Promise<void> {
  const receipt = await ctx.publicClient.waitForTransactionReceipt({hash});
  if (receipt.status !== 'success') throw new Error(`${label} reverted in ${hash}`);
}
