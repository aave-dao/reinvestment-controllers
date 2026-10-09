import {z} from 'zod';
import {gatewayApiUrls, type ChainName} from './chains.js';

const kmsSchema = z.discriminatedUnion('KMS_PROVIDER', [
  z.object({
    KMS_PROVIDER: z.literal('aws'),
    AWS_KMS_KEY_ID: z.string().min(1),
    AWS_REGION: z.string().min(1),
  }),
  z.object({
    KMS_PROVIDER: z.literal('gcp'),
    GCP_KMS_KEY_NAME: z.string().min(1),
  }),
]);

const baseSchema = z
  .object({
    CHAIN: z.enum(['mainnet', 'sepolia'] as const satisfies readonly ChainName[]),
    RPC_URL: z.url(),
    CONTROLLER_ADDRESS: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
    CIRCLE_GATEWAY_API_URL: z.url().optional(),
    POLL_INTERVAL_SECONDS: z.coerce.number().int().positive().default(300),
    MIN_INVEST_AMOUNT: z.coerce.bigint().positive(),
    INVEST_HAIRCUT_BPS: z.coerce.bigint().nonnegative().max(10_000n).default(10n),
    MIN_DIVEST_AMOUNT: z.coerce.bigint().positive(),
    MAX_DIVEST_AMOUNT: z.coerce.bigint().positive().default(10_000_000_000_000n),
    BURN_INTENT_VALIDITY_BLOCKS: z.coerce.bigint().positive().default(7_200n),
  })
  .transform((config) => ({
    ...config,
    CIRCLE_GATEWAY_API_URL: config.CIRCLE_GATEWAY_API_URL ?? gatewayApiUrls[config.CHAIN],
  }));

export type KmsConfig = z.infer<typeof kmsSchema>;
export type Config = z.infer<typeof baseSchema> & {kms: KmsConfig};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  return {...baseSchema.parse(env), kms: kmsSchema.parse(env)};
}
