import OpenAI from 'openai';
import type { ResponseCreateParamsNonStreaming } from 'openai/resources/responses/responses';
import { z } from 'zod';
import { coachResponseSchema, CoachBoundaryError, type CoachProvider, type GroundedContext } from '../../../../packages/backend-domain/src/coach.ts';

export function responseRequest(context: GroundedContext, model: string): ResponseCreateParamsNonStreaming {
  if (!model.trim()) throw new CoachBoundaryError('MODEL_CONFIGURATION_REQUIRED');
  // Internal tenant identifiers are authorization metadata, not model context.
  const { uid: _uid, policy, ...data } = context;
  const payload = { ...data,
    evidence: context.evidence.map(({ uid: _owner, ...e }) => e),
    memories: context.memories.map(({ uid: _owner, ...m }) => m),
  };
  return {
    model, store: false, stream: false, max_output_tokens: 1500,
    instructions: policy,
    input: [{ role: 'user', content: JSON.stringify(payload) }],
    tools: [],
    text: { format: { type: 'json_schema', name: 'wellbeing_coach_response_v1', strict: true,
      schema: z.toJSONSchema(coachResponseSchema) } },
  };
}

/** Not exposed by HTTP until durable admission, safety evaluation and final
 * consent/epoch publication checks are connected. Never instantiate in Flutter. */
export class OpenAiCoachProvider implements CoachProvider {
  private readonly client: OpenAI;
  private readonly model: string;
  constructor(config: { apiKey: string; model: string }) {
    if (!config.apiKey || !config.model) throw new CoachBoundaryError('PROVIDER_CONFIGURATION_REQUIRED');
    this.model = config.model;
    this.client = new OpenAI({ apiKey: config.apiKey, maxRetries: 0, timeout: 30_000 });
  }
  async respond(context: GroundedContext, signal: AbortSignal) {
    let result;
    try {
      result = await this.client.responses.create(responseRequest(context, this.model), { signal });
    } catch {
      // A timeout/cancellation may already have incurred usage. The admission
      // service must reconcile the existing request, never auto-regenerate it.
      throw new CoachBoundaryError('PROVIDER_OUTCOME_UNKNOWN');
    }
    if (result.status !== 'completed' || !result.output_text || !result.usage) {
      throw new CoachBoundaryError('PROVIDER_RESULT_UNAVAILABLE');
    }
    let response;
    try { response = coachResponseSchema.parse(JSON.parse(result.output_text)); }
    catch { throw new CoachBoundaryError('PROVIDER_RESULT_INVALID'); }
    return { response, inputTokens: result.usage.input_tokens, outputTokens: result.usage.output_tokens };
  }
}
