import { test } from 'node:test';
import assert from 'node:assert/strict';
import { responseRequest } from '../src/ai/openai_provider.ts';
import type { GroundedContext } from '../../../packages/backend-domain/src/coach.ts';
test('provider request is bounded, stateless and omits internal account identifiers', () => {
  const context: GroundedContext = { uid: 'sensitive-internal-owner', dataEpoch: 1, generatedAt: '2026-09-17T12:00:00Z', policyVersion: 'test', policy: 'Server policy', profile: {}, intent: 'greeting', currentMessage: 'Hello', evidence: [], memories: [], recentTurns: [] };
  const request = responseRequest(context, 'evaluated-model-from-config');
  assert.equal(request.store, false);
  assert.equal(request.stream, false);
  assert.equal(request.max_output_tokens, 1500);
  assert.deepEqual(request.tools, []);
  assert.equal(request.instructions, context.policy);
  assert.equal(JSON.stringify(request.input).includes(context.uid), false);
  assert.equal(request.text?.format?.type, 'json_schema');
  assert.throws(() => responseRequest(context, ''), { code: 'MODEL_CONFIGURATION_REQUIRED' });
});
