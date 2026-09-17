import { createHmac } from 'node:crypto';
import { z } from 'zod';
import { identifier, resourceNames, type Resource } from './resources.ts';
import { sequence, timestamp } from './contracts.ts';

export const erasureRequest = z.strictObject({
  operationId: z.uuid(), scope: z.literal('records'),
  records: z.array(z.strictObject({ entityType: z.enum(resourceNames as [Resource, ...Resource[]]), entityId: identifier })).min(1).max(20),
}).refine(value => new Set(value.records.map(r => `${r.entityType}/${r.entityId}`)).size === value.records.length, 'Duplicate record selectors');

export const recoveryManifest = z.strictObject({
  schemaVersion: z.literal(1), jobId: z.uuid(), ownerHash: z.string().regex(/^[a-f0-9]{64}$/),
  keyVersion: identifier, scope: z.literal('records'),
  records: erasureRequest.shape.records, cutoffSeq: sequence,
  deletedAt: timestamp, suppressionExpiresAt: timestamp,
}).refine(v => Date.parse(v.suppressionExpiresAt) > Date.parse(v.deletedAt), 'Invalid suppression interval');
export type RecoveryManifest = z.infer<typeof recoveryManifest>;
export interface RecoveryJournal {
  /** Returns only after an immutable, matching independent copy is durable. */
  persist(manifest: RecoveryManifest): Promise<void>;
}
export function ownerRecoveryHash(uid: string, key: string): string {
  if (key.length < 32) throw new Error('Recovery HMAC key must contain at least 32 characters');
  return createHmac('sha256', key).update(uid).digest('hex');
}

/** Stable serialization makes replay mismatches detectable without health data. */
export function serializeManifest(input: RecoveryManifest): string {
  const value = recoveryManifest.parse(input);
  return JSON.stringify({ ...value, records: [...value.records].sort((a, b) => `${a.entityType}/${a.entityId}`.localeCompare(`${b.entityType}/${b.entityId}`)) });
}
