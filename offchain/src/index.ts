import {createPublicClient, createWalletClient, http, type Address} from 'viem';
import {controllerAbi} from './abi/controller.js';
import {chains} from './chains.js';
import {loadConfig} from './config.js';
import {readDeployment} from './deployment.js';
import {tick, type KeeperContext} from './keeper.js';
import {log} from './log.js';
import {runLoop} from './loop.js';
import {createKeeperAccount} from './signer/index.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const chain = chains[config.CHAIN];
  const transport = http(config.RPC_URL);
  const publicClient = createPublicClient({chain, transport});

  const chainId = await publicClient.getChainId();
  if (chainId !== chain.id) {
    throw new Error(`RPC_URL is on chain ${chainId}, expected ${config.CHAIN} (${chain.id})`);
  }

  const account = await createKeeperAccount(config.kms);
  const walletClient = createWalletClient({account, chain, transport});

  const deployment = await readDeployment(publicClient, config.CONTROLLER_ADDRESS as Address);
  const controller = {address: deployment.controller, abi: controllerAbi} as const;
  const keeperRole = await publicClient.readContract({...controller, functionName: 'KEEPER_ROLE'});
  const isKeeper = await publicClient.readContract({
    ...controller,
    functionName: 'hasRole',
    args: [keeperRole, account.address],
  });
  if (!isKeeper) throw new Error(`${account.address} does not hold KEEPER_ROLE`);

  const ctx: KeeperContext = {config, account, publicClient, walletClient, deployment};
  const shutdown = new AbortController();
  process.once('SIGINT', () => shutdown.abort());
  process.once('SIGTERM', () => shutdown.abort());

  log('started', {
    chain: config.CHAIN,
    gatewayApi: config.CIRCLE_GATEWAY_API_URL,
    keeper: account.address,
    ...deployment,
  });
  await runLoop({
    tick: () => tick(ctx),
    intervalMs: config.POLL_INTERVAL_SECONDS * 1_000,
    signal: shutdown.signal,
    log,
  });
  log('stopped');
}

await main();
