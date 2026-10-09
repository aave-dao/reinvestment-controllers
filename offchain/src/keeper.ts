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
import {buildBurnIntent, signBurnIntent, type BurnIntent} from './circle/burnIntent.js';
import {requestAttestation, type TransferAttestation} from './circle/client.js';
import type {Config} from './config.js';
import {controllerAbi, gatewayWalletAbi, hubAbi, type Deployment} from './controller.js';

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

export type TickResult = 'paused' | 'idle' | 'invested' | 'divested' | 'expired';

const min = (...values: bigint[]) => values.reduce((a, b) => (b < a ? b : a));
const max = (...values: bigint[]) => values.reduce((a, b) => (b > a ? b : a));
const saturatingSub = (a: bigint, b: bigint) => (a > b ? a - b : 0n);

/** Amount that must return to the Hub to restore the liquid buffer and respect the exposure cap */
export function getShortfall(state: KeeperState): bigint {
  const bufferProduct = state.supplied * state.liquidBufferBps;
  const buffer =
    bufferProduct / PERCENTAGE_FACTOR + (bufferProduct % PERCENTAGE_FACTOR > 0n ? 1n : 0n);
  const cap = min(
    state.exposureCapAbs,
    (state.supplied * state.exposureCapBps) / PERCENTAGE_FACTOR,
  );
  return max(saturatingSub(buffer, state.idle), saturatingSub(state.swept, cap));
}

/** Sizes the next divest, whose `amount + maxFee` returns to the Hub, capped per transfer */
export function planDivest(
  state: KeeperState,
  config: Pick<Config, 'MIN_DIVEST_AMOUNT' | 'MAX_DIVEST_AMOUNT'>,
): bigint | undefined {
  const shortfall = getShortfall(state);
  if (shortfall === 0n || shortfall < config.MIN_DIVEST_AMOUNT) return undefined;

  const withdrawable = saturatingSub(state.swept, state.maxFee);
  const amount = min(max(shortfall - state.maxFee, 1n), config.MAX_DIVEST_AMOUNT, withdrawable);
  return amount > 0n ? amount : undefined;
}

export function planInvest(
  state: KeeperState,
  config: Pick<Config, 'MIN_INVEST_AMOUNT'>,
): bigint | undefined {
  if (getShortfall(state) > 0n) return undefined;
  if (state.timestamp < state.lastInvestTimestamp + state.investMinDelay) return undefined;
  if (state.investableAmount < config.MIN_INVEST_AMOUNT) return undefined;
  return state.investableAmount;
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

/** Runs one keeper step: settles a pending divest, starts a new one, or invests */
export async function tick(ctx: KeeperContext): Promise<TickResult> {
  const state = await readState(ctx);
  if (state.paused) return 'paused';

  if (!ctx.pending) {
    const amount = planDivest(state, ctx.config);
    if (amount !== undefined) ctx.pending = await createPendingDivest(ctx, state, amount);
  }
  if (ctx.pending) return settlePendingDivest(ctx, ctx.pending, state.blockNumber);

  const amount = planInvest(state, ctx.config);
  if (amount === undefined) return 'idle';

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

async function settlePendingDivest(
  ctx: KeeperContext,
  pending: PendingDivest,
  blockNumber: bigint,
): Promise<TickResult> {
  pending.attestation ??= await requestAttestation(
    ctx.config.CIRCLE_GATEWAY_API_URL,
    pending.burnIntent,
    pending.signature,
  );

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
