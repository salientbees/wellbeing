import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mutationMetadata, operationWindow, errorEnvelope } from '../src/contracts.ts';

test('untrusted mutation metadata rejects tenant and server-controlled fields', () => {
  const valid = { operationCreatedAt: '2026-09-17T00:00:00Z', baseRevision: 0 };
  assert.deepEqual(mutationMetadata.parse(JSON.parse(JSON.stringify(valid))), valid);
  for (const extra of [{ uid: 'another-user' }, { role: 'admin' }, { baseRevision: -1 }, { baseRevision: Number.MAX_SAFE_INTEGER + 1 }]) {
    assert.equal(mutationMetadata.safeParse({ ...valid, ...extra }).success, false);
  }
});
test('operation expiry and clock skew have explicit inclusive boundaries', () => {
  const now = new Date('2026-09-17T00:00:00Z');
  assert.equal(operationWindow('2026-08-18T00:00:00Z', now), 'valid');
  assert.equal(operationWindow('2026-08-17T23:59:59Z', now), 'expired');
  assert.equal(operationWindow('2026-09-17T00:05:00Z', now), 'valid');
  assert.equal(operationWindow('2026-09-17T00:05:01Z', now), 'future');
});
test('error contract rejects accidental stack or provider data', () => {
  const error = { code: 'AUTH_REQUIRED', message: 'Sign in to continue.', requestId: 'f1a8b3b2-34ec-4dab-8f9f-9e7b37647c72', retryable: false };
  assert.equal(errorEnvelope.safeParse({ error }).success, true);
  assert.equal(errorEnvelope.safeParse({ error: { ...error, stack: 'private details' } }).success, false);
});
