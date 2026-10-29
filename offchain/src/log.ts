export type Log = (event: string, fields?: Record<string, unknown>) => void;

/** Writes one JSON line per event, which CloudWatch and Cloud Logging parse as structured logs */
export const log: Log = (event, fields = {}) => {
  console.log(
    JSON.stringify({time: new Date().toISOString(), event, ...fields}, (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value,
    ),
  );
};

export function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
