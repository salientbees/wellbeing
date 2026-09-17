import { z } from 'zod';
import { sequence, timestamp } from './contracts.ts';

export const identifier = z.string().regex(/^[A-Za-z0-9_-]{1,100}$/);
export const localDate = z.iso.date();
export const timeZone = z.string().max(80).refine(value => {
  try { new Intl.DateTimeFormat('en', { timeZone: value }); return true; } catch { return false; }
}, 'Use an IANA time zone');
const text = (max = 500) => z.string().trim().min(1).max(max);
const optionalText = z.string().trim().max(2000).optional();
const positive = z.number().finite().positive().max(1_000_000);
const nonnegative = z.number().finite().min(0).max(1_000_000);
const log = {
  occurredAt: timestamp, localDate, timeZone,
  utcOffsetMinutes: z.number().int().min(-840).max(840),
  source: z.literal('manual'), notes: optionalText,
};
const interval = { startAt: timestamp, endAt: timestamp };
const ordered = (v: { startAt: string; endAt: string }) => Date.parse(v.endAt) > Date.parse(v.startAt);
const status = z.enum(['active', 'paused', 'archived']);
export const foodItem = z.strictObject({
  name: text(120), quantity: positive, portionUnit: z.enum(['portion', 'g', 'ml']),
  grams: positive.optional(), energyKcal: nonnegative.optional(), proteinG: nonnegative.optional(),
  carbohydrateG: nonnegative.optional(), fatG: nonnegative.optional(), fiberG: nonnegative.optional(),
  source: z.enum(['manual', 'label', 'licensedDatabase', 'estimate']), sourceId: text(120).optional(),
  basis: z.enum(['perPortion', 'per100g']),
}).refine(v => v.basis !== 'per100g' || v.grams !== undefined, 'Mass is required for per-100g nutrition');
export const profile = z.strictObject({
  preferredName: z.string().trim().max(80), locale: text(32), timeZone,
  unitPreferences: z.strictObject({ weight: z.enum(['kg', 'lb']), length: z.enum(['cm', 'in']), volume: z.enum(['ml', 'flOz']) }),
  coachingTone: z.enum(['gentle', 'direct', 'encouraging']), ageEligible: z.literal(true),
});
export const consentChoices = z.strictObject({
  aiProcessing: z.boolean(), memory: z.boolean(), analytics: z.boolean(), crashReports: z.boolean(), healthImport: z.boolean(),
}).refine(v => !v.memory || v.aiProcessing, 'Memory requires AI processing consent');
export const bootstrap = z.strictObject({ profile, consents: consentChoices, policyVersion: text(50) });
export const settings = z.strictObject({
  theme: z.enum(['system', 'light', 'dark']), reduceMotion: z.boolean(),
  hiddenMetrics: z.array(z.enum(['weight', 'nutrition', 'measurements'])).max(3), weekStartsOn: z.number().int().min(1).max(7),
  notificationPreferences: z.strictObject({ enabled: z.boolean(), quietStart: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/), quietEnd: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/) }),
});

export const resourceSchemas = {
  'weight-logs': z.strictObject({ ...log, weightKg: positive.max(1000), originalValue: positive.optional(), originalUnit: z.enum(['kg', 'lb']).optional() }),
  'body-measurements': z.strictObject({ ...log, site: z.enum(['waist', 'hip', 'chest', 'arm', 'thigh', 'other']), side: z.enum(['left', 'right', 'none']).optional(), circumferenceCm: positive.max(1000), customSite: text(80).optional() }).refine(v => v.site !== 'other' || !!v.customSite, 'Name the custom measurement site'),
  'hydration-logs': z.strictObject({ ...log, volumeMl: positive.max(100_000), beverageType: z.enum(['water', 'tea', 'coffee', 'milk', 'other']) }),
  'food-logs': z.strictObject({ ...log, meal: z.enum(['breakfast', 'lunch', 'dinner', 'snack']), items: z.array(foodItem).min(1).max(30), nutritionStatus: z.enum(['complete', 'partial', 'unknown']) }),
  'saved-foods': foodItem,
  'activity-logs': z.strictObject({ ...log, ...interval, steps: nonnegative.int().optional(), distanceM: nonnegative.optional(), activeSeconds: nonnegative.int().optional(), sourceGroup: z.literal('manual') }).refine(ordered, 'End must follow start').refine(v => v.steps !== undefined || v.distanceM !== undefined || v.activeSeconds !== undefined, 'Record at least one activity measurement'),
  'exercise-logs': z.strictObject({ ...log, ...interval, type: z.enum(['walk', 'run', 'cycle', 'swim', 'strength', 'yoga', 'other']), durationSeconds: positive.int(), effort: z.number().int().min(1).max(10).optional(), energyKcal: nonnegative.optional() }).refine(ordered, 'End must follow start').refine(v => v.durationSeconds <= (Date.parse(v.endAt) - Date.parse(v.startAt)) / 1000, 'Duration exceeds the interval'),
  'sleep-logs': z.strictObject({ ...log, ...interval, awakeSeconds: nonnegative.int().optional(), kind: z.enum(['main', 'nap']), quality: z.number().int().min(1).max(5).optional() }).refine(ordered, 'End must follow start').refine(v => (v.awakeSeconds ?? 0) < (Date.parse(v.endAt) - Date.parse(v.startAt)) / 1000, 'Awake time exceeds sleep interval'),
  'mood-logs': z.strictObject({ ...log, rating: z.number().int().min(1).max(5), scaleVersion: z.literal('mood-1-5-v1'), tags: z.array(text(40)).max(10) }),
  goals: z.strictObject({ metric: z.enum(['weight', 'hydration', 'steps', 'exercise', 'sleep', 'habit']), direction: z.enum(['increase', 'decrease', 'maintain', 'complete']), baseline: nonnegative.optional(), target: nonnegative.optional(), lowerBound: nonnegative.optional(), upperBound: nonnegative.optional(), unit: z.enum(['kg', 'ml', 'steps', 'seconds', 'count']), startDate: localDate, targetDate: localDate.optional(), status, milestones: z.array(nonnegative).max(20) }).refine(v => !v.targetDate || v.targetDate >= v.startDate, 'Target date precedes start').refine(v => v.direction === 'maintain' ? v.lowerBound !== undefined && v.upperBound !== undefined && v.lowerBound <= v.upperBound : v.target !== undefined && v.baseline !== undefined && v.target !== v.baseline, 'Set a valid target or maintenance range'),
  schedules: z.strictObject({ kind: z.enum(['oneOff', 'daily', 'weekly']), localTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/), weekdays: z.array(z.number().int().min(1).max(7)).max(7), startDate: localDate, endDate: localDate.optional(), timeZone, zoneMode: z.enum(['fixed', 'followProfile']), status, skipDates: z.array(localDate).max(100) }).refine(v => !v.endDate || v.endDate >= v.startDate, 'End date precedes start').refine(v => v.kind !== 'weekly' || v.weekdays.length > 0, 'Choose weekdays'),
  habits: z.strictObject({ name: text(100), targetQuantity: positive, unit: z.enum(['count', 'minutes', 'ml']), scheduleId: identifier, status, effectiveFrom: localDate }),
  'habit-logs': z.strictObject({ ...log, habitId: identifier, occurrenceId: text(100), status: z.enum(['done', 'partial', 'skipped']), quantity: nonnegative.optional() }),
  'daily-check-ins': z.strictObject({ localDate, timeZone, answers: z.strictObject({ reflection: z.string().max(2000), energy: z.number().int().min(1).max(5).optional(), intention: z.string().max(500).optional() }), linkedLogIds: z.array(z.strictObject({ entityType: z.enum(['mood-logs', 'sleep-logs']), entityId: identifier })).max(10) }),
  reminders: z.strictObject({ scheduleId: identifier, subjectType: z.enum(['habit', 'goal', 'checkIn', 'general']), subjectId: identifier.optional(), deliveryMode: z.enum(['local', 'push']), primaryDeviceId: identifier.optional(), enabled: z.boolean() }),
} as const;
export type Resource = keyof typeof resourceSchemas;
export const collections: Record<Resource, string> = {
  'weight-logs': 'weightLogs', 'body-measurements': 'bodyMeasurements', 'hydration-logs': 'hydrationLogs', 'food-logs': 'foodLogs', 'saved-foods': 'savedFoods', 'activity-logs': 'activityLogs', 'exercise-logs': 'exerciseLogs', 'sleep-logs': 'sleepLogs', 'mood-logs': 'moodLogs', goals: 'goals', schedules: 'schedules', habits: 'habits', 'habit-logs': 'habitLogs', 'daily-check-ins': 'dailyCheckIns', reminders: 'reminders',
};
export const resourceNames = Object.keys(collections) as Resource[];
export const mutation = z.strictObject({
  operationId: z.uuid(), entityType: z.enum(resourceNames as [Resource, ...Resource[]]), entityId: identifier,
  action: z.enum(['create', 'update', 'delete']), baseRevision: sequence, operationCreatedAt: timestamp, payload: z.record(z.string(), z.unknown()),
});
export type Mutation = z.infer<typeof mutation>;
export interface Entity { id: string; entityType: Resource; revision: number; schemaVersion: number; createdAt: string; updatedAt: string; deletedAt: string | null; payload: Record<string, unknown> }
export function validateMutation(input: unknown): Mutation {
  const op = mutation.parse(input);
  if (op.action === 'delete') z.strictObject({}).parse(op.payload);
  else op.payload = resourceSchemas[op.entityType].parse(op.payload);
  if (op.action === 'create' && op.baseRevision !== 0) throw new z.ZodError([{ code: 'custom', path: ['baseRevision'], message: 'Create requires revision zero' }]);
  if (op.entityType === 'daily-check-ins' && op.action !== 'delete' && op.entityId !== op.payload.localDate) throw new z.ZodError([{ code: 'custom', path: ['entityId'], message: 'Check-in identifier must match its local date' }]);
  return op;
}
