import { z } from 'zod';
import { mutationMetadata } from './contracts.ts';
import { profile, settings } from './resources.ts';

const metadata = { ...mutationMetadata.shape, operationId: z.uuid() };
export const profilePatch = z.strictObject({ ...metadata,
  changes: profile.omit({ ageEligible: true }).partial().refine(v => Object.keys(v).length > 0, 'Provide a change'),
});
export const settingsPatch = z.strictObject({ ...metadata,
  changes: settings.partial().refine(v => Object.keys(v).length > 0, 'Provide a change'),
});
export const consentChange = z.strictObject({ ...metadata,
  category: z.enum(['aiProcessing', 'memory', 'analytics', 'crashReports', 'healthImport']),
  granted: z.boolean(), policyVersion: z.string().min(1).max(50),
});
