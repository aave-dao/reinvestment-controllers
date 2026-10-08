import type {Address, LocalAccount, PublicClient, WalletClient} from 'viem';
import type {Config} from './config.js';

export type KeeperContext = {
  config: Config;
  account: LocalAccount;
  publicClient: PublicClient;
  walletClient: WalletClient;
  controller: Address;
};

export async function tick(ctx: KeeperContext): Promise<void> {
  throw new Error('not implemented');
}
