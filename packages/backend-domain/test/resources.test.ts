import { test } from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { validateMutation, resourceSchemas, consentChoices } from '../src/resources.ts';

const operation = { operationId: 'b9103272-32e9-440c-8b7b-4cfad829f905', entityType: 'weight-logs', entityId: 'record-1', action: 'create', baseRevision: 0, operationCreatedAt: '2026-09-17T08:00:00Z', payload: { occurredAt: '2026-09-17T08:00:00Z', localDate: '2026-09-17', timeZone: 'Asia/Kolkata', utcOffsetMinutes: 330, source: 'manual', weightKg: 70 } };
test('strict mutation boundary rejects injected ownership and invalid create revisions', () => {
  assert.equal(validateMutation(operation).payload.weightKg, 70);
  assert.throws(() => validateMutation({ ...operation, uid: 'another-user' }), z.ZodError);
  assert.throws(() => validateMutation({ ...operation, baseRevision: 4 }), z.ZodError);
  assert.throws(() => validateMutation({ ...operation, payload: { ...operation.payload, uid: 'another-user' } }), z.ZodError);
});
test('delete requests cannot retain health payloads', () => {
  assert.throws(() => validateMutation({ ...operation, action: 'delete' }), z.ZodError);
  assert.deepEqual(validateMutation({ ...operation, action: 'delete', payload: {} }).payload, {});
});
test('daily check-in identity is its local date', () => {
  assert.throws(() => validateMutation({ ...operation, entityType: 'daily-check-ins', payload: { localDate: '2026-09-17', timeZone: 'Asia/Kolkata', answers: { reflection: '' }, linkedLogIds: [] } }), z.ZodError);
});
test('unknown nutrients are permitted but per-100g foods require mass', () => {
  const food = { name: 'Food', quantity: 1, portionUnit: 'portion', source: 'manual', basis: 'perPortion' };
  assert.equal(resourceSchemas['saved-foods'].safeParse(food).success, true);
  assert.equal(resourceSchemas['saved-foods'].safeParse({ ...food, basis: 'per100g' }).success, false);
});
test('memory cannot be enabled without AI processing consent', () => {
  assert.equal(consentChoices.safeParse({ aiProcessing: false, memory: true, analytics: false, crashReports: false, healthImport: false }).success, false);
});
