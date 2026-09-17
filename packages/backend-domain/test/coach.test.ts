import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildContext, eligibleMemories, validateStructuredClaims, assertPublishable, type ContextInput, type Memory, type Evidence } from '../src/coach.ts';
const now = new Date('2026-09-17T12:00:00Z');
const principal = { uid: 'owner', dataEpoch: 4, aiProcessing: true, memory: true };
const evidence: Evidence = { id: 'source', uid: 'owner', revision: 2, dataEpoch: 4, generatedAt: '2026-09-17T10:00:00Z', expiresAt: '2026-09-18T10:00:00Z', kind: 'metric', value: 250 };
const memory: Memory = { id: 'memory', uid: 'owner', category: 'preference', state: 'active', provenance: 'userConfirmed', text: 'Brief check-ins', confirmedAt: '2026-09-17T10:00:00Z', expiresAt: '2026-10-17T10:00:00Z', sourceRefs: [{ id: 'source', revision: 2 }] };
const input: ContextInput = { principal, intent: 'hydration', currentMessage: 'What did I record?', policy: 'Server policy', policyVersion: 'test', profile: {}, evidence: [evidence], memories: [memory], suppressions: [], recentTurns: [] };
// UTF-8 bytes provide deliberately conservative fixture accounting, not a model tokenizer claim.
const estimate = (value: string) => Buffer.byteLength(value);
test('context excludes cross-user, stale and future evidence and honors consent', () => {
  const context = buildContext({ ...input, evidence: [evidence, { ...evidence, uid: 'other' }, { ...evidence, dataEpoch: 3 }, { ...evidence, generatedAt: '2027-01-01T00:00:00Z' }] }, estimate, now);
  assert.equal(context.evidence.length, 1);
  assert.throws(() => buildContext({ ...input, principal: { ...principal, aiProcessing: false } }, estimate, now), { code: 'AI_CONSENT_REQUIRED' });
});
test('memory revision changes, disputes, expiry and forgetting suppression remove eligibility', () => {
  assert.equal(eligibleMemories(principal, [memory], [evidence], [], now).length, 1);
  for (const candidate of [{ ...memory, state: 'disputed' as const }, { ...memory, confirmedAt: null }, { ...memory, expiresAt: '2026-09-16T00:00:00Z' }]) {
    assert.equal(eligibleMemories(principal, [candidate], [evidence], [], now).length, 0);
  }
  assert.equal(eligibleMemories(principal, [memory], [{ ...evidence, revision: 3 }], [], now).length, 0);
  assert.equal(eligibleMemories(principal, [memory], [evidence], [{ category: 'preference', sourceIds: ['source'] }], now).length, 0);
});
test('context bounds history and never silently truncates an oversized user request', () => {
  assert.throws(() => buildContext({ ...input, currentMessage: 'x'.repeat(2200) }, estimate, now), { code: 'MESSAGE_TOO_LONG' });
  const context = buildContext({ ...input, recentTurns: Array.from({ length: 100 }, () => ({ role: 'user' as const, text: 'hello' })) }, estimate, now);
  assert.equal(context.recentTurns.length, 8);
});
test('numeric claims require exact evidence and publication rechecks epoch and safety', () => {
  const context = buildContext(input, estimate, now);
  const response = { answer: 'Recorded amount', safetyOutcome: 'routine', personalClaims: [{ sourceId: 'source', revision: 2, value: 250 }] };
  assert.equal(validateStructuredClaims(response, context).personalClaims.length, 1);
  assert.throws(() => validateStructuredClaims({ ...response, personalClaims: [{ sourceId: 'source', revision: 2, value: 500 }] }, context), { code: 'UNSUPPORTED_PERSONAL_CLAIM' });
  assert.throws(() => assertPublishable(context, { ...principal, dataEpoch: 5 }, true), { code: 'CONTEXT_CHANGED' });
  assert.throws(() => assertPublishable(context, principal, false), { code: 'SAFETY_REVIEW_REQUIRED' });
});
