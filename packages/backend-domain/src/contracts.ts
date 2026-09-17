import { z } from 'zod';

export const sequence = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
export const timestamp = z.iso.datetime({ offset: true });
export const errorEnvelope = z.strictObject({
  error: z.strictObject({
    code: z.string().regex(/^[A-Z][A-Z_]{0,63}$/),
    message: z.string().max(256),
    requestId: z.uuid(),
    retryable: z.boolean(),
    fieldErrors: z.array(z.strictObject({ field: z.string().max(128), code: z.string().max(64) })).max(50).optional(),
  }),
});
export const responseMeta = z.strictObject({
  requestId: z.uuid(), serverTime: timestamp,
  nextCursor: z.string().max(2048).optional(),
  sourceThroughSeq: sequence.optional(), dataEpoch: sequence.optional(),
});
export const mutationMetadata = z.strictObject({
  operationCreatedAt: timestamp, baseRevision: sequence,
});
export type MutationMetadata = z.infer<typeof mutationMetadata>;
export type ErrorEnvelope = z.infer<typeof errorEnvelope>;

/** Inject a clock; never replace a caller's immutable operation timestamp. */
export function operationWindow(createdAt: string, now: Date): 'valid' | 'expired' | 'future' {
  const age = now.getTime() - Date.parse(timestamp.parse(createdAt));
  if (!Number.isFinite(now.getTime())) throw new TypeError('Invalid server clock');
  if (age < -5 * 60_000) return 'future';
  if (age > 30 * 24 * 60 * 60_000) return 'expired';
  return 'valid';
}
