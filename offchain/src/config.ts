import {z} from 'zod';

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

const baseSchema = z.object({
  RPC_MAINNET: z.url(),
  CONTROLLER_ADDRESS: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
  CIRCLE_GATEWAY_API_URL: z.url(),
  POLL_INTERVAL_SECONDS: z.coerce.number().int().positive().default(300),
  MIN_INVEST_AMOUNT: z.coerce.bigint().positive(),
  MIN_DIVEST_AMOUNT: z.coerce.bigint().positive(),
  MAX_DIVEST_AMOUNT: z.coerce.bigint().positive().default(10_000_000_000_000n),
  BURN_INTENT_VALIDITY_BLOCKS: z.coerce.bigint().positive().default(7_200n),
});

export type KmsConfig = z.infer<typeof kmsSchema>;
export type Config = z.infer<typeof baseSchema> & {kms: KmsConfig};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  return {...baseSchema.parse(env), kms: kmsSchema.parse(env)};
}
