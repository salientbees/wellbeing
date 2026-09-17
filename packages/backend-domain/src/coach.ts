import { z } from 'zod';

export const evidenceSchema = z.strictObject({
  id: z.string().min(1).max(120), uid: z.string().min(1), revision: z.number().int().positive(),
  dataEpoch: z.number().int().nonnegative(), generatedAt: z.iso.datetime(), expiresAt: z.iso.datetime(),
  kind: z.enum(['record', 'metric', 'userStatement']),
  value: z.union([z.string().max(2000), z.number().finite(), z.boolean()]),
});
export type Evidence = z.infer<typeof evidenceSchema>;
export const memorySchema = z.strictObject({
  id: z.string().min(1), uid: z.string().min(1),
  category: z.enum(['preference', 'goal', 'routine', 'strategy', 'challenge', 'context']),
  state: z.enum(['pending', 'active', 'disputed', 'superseded', 'forgotten']),
  provenance: z.enum(['userStated', 'userConfirmed']),
  text: z.string().min(1).max(500), confirmedAt: z.iso.datetime().nullable(),
  expiresAt: z.iso.datetime(), sourceRefs: z.array(z.strictObject({ id: z.string(), revision: z.number().int().positive() })).min(1).max(20),
});
export type Memory = z.infer<typeof memorySchema>;
export interface Suppression { category: Memory['category']; sourceIds: readonly string[] }
export interface ContextPrincipal { uid: string; dataEpoch: number; aiProcessing: boolean; memory: boolean }

export class CoachBoundaryError extends Error {
  readonly code: string;
  constructor(code: string) { super(code); this.code = code; }
}
function deny(code: string): never { throw new CoachBoundaryError(code); }

export function eligibleMemories(principal: ContextPrincipal, candidates: readonly Memory[], evidence: readonly Evidence[], suppressions: readonly Suppression[], now: Date): Memory[] {
  if (!principal.aiProcessing || !principal.memory) return [];
  const sources = new Map(evidence.filter(e => e.uid === principal.uid && e.dataEpoch === principal.dataEpoch && Date.parse(e.expiresAt) > now.getTime()).map(e => [e.id, e]));
  return candidates.filter(memory => memory.uid === principal.uid && memory.state === 'active' &&
    memory.confirmedAt !== null && Date.parse(memory.confirmedAt) <= now.getTime() && Date.parse(memory.expiresAt) > now.getTime() &&
    memory.sourceRefs.every(ref => sources.get(ref.id)?.revision === ref.revision) &&
    !suppressions.some(marker => marker.category === memory.category && memory.sourceRefs.some(ref => marker.sourceIds.includes(ref.id))))
    .slice(0, 12);
}

export interface ContextInput {
  principal: ContextPrincipal; intent: string; currentMessage: string;
  policy: string; policyVersion: string; profile: Record<string, string>;
  evidence: readonly Evidence[]; memories: readonly Memory[]; suppressions: readonly Suppression[];
  recentTurns: readonly { role: 'user' | 'assistant'; text: string }[];
}
export interface GroundedContext {
  uid: string; dataEpoch: number; generatedAt: string; policyVersion: string;
  policy: string; profile: Record<string, string>; intent: string; currentMessage: string;
  evidence: Evidence[]; memories: Memory[]; recentTurns: { role: 'user' | 'assistant'; text: string }[];
}

/// The caller supplies the evaluated model's conservative token estimator.
/// Missing estimator/model configuration must disable provider admission.
export function buildContext(input: ContextInput, estimateTokens: (text: string) => number, now: Date): GroundedContext {
  if (!input.principal.aiProcessing) deny('AI_CONSENT_REQUIRED');
  const count = (value: unknown) => {
    const tokens = estimateTokens(JSON.stringify(value));
    if (!Number.isFinite(tokens) || tokens < 0) deny('INVALID_TOKEN_ESTIMATE');
    return Math.ceil(tokens);
  };
  if (count(input.currentMessage) > 2100) deny('MESSAGE_TOO_LONG');
  if (count(input.policy) > 1200 || count(input.profile) > 600) deny('POLICY_CONFIGURATION_INVALID');
  const evidence = input.evidence.map(e => evidenceSchema.parse(e))
    .filter(e => e.uid === input.principal.uid && e.dataEpoch === input.principal.dataEpoch &&
      Date.parse(e.generatedAt) <= now.getTime() && Date.parse(e.expiresAt) > now.getTime()).slice(0, 20);
  while (evidence.length && count(evidence) > 2000) evidence.pop();
  const memories = eligibleMemories(input.principal, input.memories.map(m => memorySchema.parse(m)), evidence, input.suppressions, now);
  while (memories.length && count(memories) > 1500) memories.pop();
  const recentTurns = input.recentTurns.slice(-8).map(turn => ({ ...turn }));
  while (recentTurns.length && count(recentTurns) > 1800) recentTurns.shift();
  const result: GroundedContext = {
    uid: input.principal.uid, dataEpoch: input.principal.dataEpoch, generatedAt: now.toISOString(),
    policyVersion: input.policyVersion, policy: input.policy, profile: { ...input.profile },
    intent: input.intent, currentMessage: input.currentMessage, evidence, memories, recentTurns,
  };
  // Reserve overhead for the response schema/provider framing; never truncate policy or message.
  if (count(result) + 1000 > 10000) deny('CONTEXT_BUDGET_EXCEEDED');
  return result;
}

export const coachResponseSchema = z.strictObject({
  answer: z.string().max(6000),
  safetyOutcome: z.enum(['routine', 'clarify', 'outOfScope', 'urgentSupport']),
  personalClaims: z.array(z.strictObject({ sourceId: z.string(), revision: z.number().int().positive(),
    value: z.union([z.string().max(2000), z.number().finite(), z.boolean()]) })).max(20),
});
export type CoachResponse = z.infer<typeof coachResponseSchema>;

/// This verifies structured facts only. Free prose still needs the documented
/// independent safety/grounding evaluator before any answer can be published.
export function validateStructuredClaims(response: unknown, context: GroundedContext): CoachResponse {
  const result = coachResponseSchema.parse(response);
  const evidence = new Map(context.evidence.map(e => [e.id, e]));
  for (const claim of result.personalClaims) {
    const source = evidence.get(claim.sourceId);
    if (!source || source.uid !== context.uid || source.revision !== claim.revision || source.value !== claim.value) deny('UNSUPPORTED_PERSONAL_CLAIM');
  }
  return result;
}

export function assertPublishable(context: GroundedContext, current: ContextPrincipal, safetyPassed: boolean): void {
  if (context.uid !== current.uid || !current.aiProcessing || context.dataEpoch !== current.dataEpoch) deny('CONTEXT_CHANGED');
  if (!safetyPassed) deny('SAFETY_REVIEW_REQUIRED');
}

export interface CoachProvider {
  /** Server implementation must use store:false, no automatic billed retry,
   * evaluated model configuration, and at most 1,500 output tokens. */
  respond(context: GroundedContext, signal: AbortSignal): Promise<{ response: unknown; inputTokens: number; outputTokens: number }>;
}
