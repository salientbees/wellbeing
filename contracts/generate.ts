import { readFile, writeFile } from 'node:fs/promises';
import { z } from 'zod';
import { profilePatch, settingsPatch, consentChange } from '../packages/backend-domain/src/account_preferences.ts';
import { errorEnvelope, mutationMetadata, responseMeta } from '../packages/backend-domain/src/contracts.ts';

const document = {
  openapi: '3.1.0',
  info: {
    title: 'Wellbeing API', version: '0.1.0',
    description: 'Runtime common and account-preference schemas. Other business routes remain specified in docs/API_SPECIFICATION.md. No production API is deployed.',
  },
  servers: [{ url: '/v1' }],
  paths: Object.fromEntries([
    ['/me/profile', 'patch', 'ProfilePatch'], ['/me/settings', 'patch', 'SettingsPatch'], ['/me/consents', 'post', 'ConsentChange'],
  ].map(([path, method, schema]) => [path, { [method!]: {
    requestBody: { required: true, content: { 'application/json': { schema: { $ref: `#/components/schemas/${schema}` } } } },
    responses: { '200': { description: 'Confirmed revision, committedSeq and current account' },
      '409': { description: 'Revision or idempotency conflict; refresh and review before resubmission' },
      '422': { description: 'Invalid fields or memory grant without AI consent' } },
  } }])),
  components: {
    securitySchemes: {
      firebaseIdToken: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
      appCheck: { type: 'apiKey', in: 'header', name: 'X-Firebase-AppCheck' },
    },
    schemas: {
      ProfilePatch: z.toJSONSchema(profilePatch),
      SettingsPatch: z.toJSONSchema(settingsPatch),
      ConsentChange: z.toJSONSchema(consentChange),
      ErrorEnvelope: z.toJSONSchema(errorEnvelope),
      ResponseMeta: z.toJSONSchema(responseMeta),
      MutationMetadata: z.toJSONSchema(mutationMetadata),
    },
  },
  security: [{ firebaseIdToken: [], appCheck: [] }],
};
const path = new URL('./openapi.json', import.meta.url);
const output = JSON.stringify(document, null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (await readFile(path, 'utf8') !== output) throw new Error('OpenAPI schemas differ from runtime schemas. Run npm run contracts:generate.');
} else {
  await writeFile(path, output);
}
