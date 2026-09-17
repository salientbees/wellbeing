import { test } from 'node:test';
import assert from 'node:assert/strict';
import { erasureRequest, ownerRecoveryHash, recoveryManifest } from '../src/privacy.ts';
test('privacy selectors reject arbitrary collections, duplicated IDs and owner injection', () => {
  const record = { entityType: 'weight-logs', entityId: 'one' };
  const request = { operationId: 'b9103272-32e9-440c-8b7b-4cfad829f905', scope: 'records', records: [record] };
  assert.equal(erasureRequest.safeParse(request).success, true);
  assert.equal(erasureRequest.safeParse({ ...request, records: [record, record] }).success, false);
  assert.equal(erasureRequest.safeParse({ ...request, ownerUid: 'other' }).success, false);
  assert.equal(erasureRequest.safeParse({ ...request, records: [{ entityType: 'users', entityId: 'other' }] }).success, false);
});
test('recovery identity is keyed and manifests reject health payloads', () => {
  const key = 'test-key-with-at-least-32-characters';
  assert.notEqual(ownerRecoveryHash('one', key), ownerRecoveryHash('two', key));
  assert.notEqual(ownerRecoveryHash('one', key), ownerRecoveryHash('one', `${key}-rotated`));
  assert.throws(() => ownerRecoveryHash('one', 'short'));
  assert.equal(recoveryManifest.safeParse({ weightKg: 70 }).success, false);
});
