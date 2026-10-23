// Builds the n8n credentials file from environment variables, for `n8n import:credentials`.
// The ids match the ones referenced by the workflows, so nodes are linked without manual selection.
// Runs inside the n8n container: node /repo/scripts/build-credentials.js
const fs = require('fs');

const env = process.env;
const OUTPUT = '/tmp/credentials-to-import.json';

const credentials = [
  {
    id: 'QugGwVrTwVGwNGBq',
    name: 'Postgres account',
    type: 'postgres',
    required: ['POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD'],
    data: () => ({ host: 'postgres', port: 5432, database: env.POSTGRES_DB, user: env.POSTGRES_USER, password: env.POSTGRES_PASSWORD }),
  },
  {
    id: 'tW5sM2nQ8rK4xP7v',
    name: 'Twilio account',
    type: 'twilioApi',
    required: ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN'],
    data: () => ({ authType: 'authToken', accountSid: env.TWILIO_ACCOUNT_SID, authToken: env.TWILIO_AUTH_TOKEN }),
  },
  {
    id: 'PagpXlhagAXnBBZ8',
    name: 'Google Gemini(PaLM) Api account',
    type: 'googlePalmApi',
    required: ['GEMINI_API_KEY'],
    data: () => ({ host: 'https://generativelanguage.googleapis.com', apiKey: env.GEMINI_API_KEY }),
  },
  {
    id: 'rG3sK8pW2nQ6vL4x',
    name: 'RAG search API key',
    type: 'httpHeaderAuth',
    required: ['RAG_SEARCH_API_KEY'],
    data: () => ({ name: 'X-API-Key', value: env.RAG_SEARCH_API_KEY }),
  },
  {
    id: 'YuVyTsCz6Jv4vpYH',
    name: 'Google Calendar account',
    type: 'googleCalendarOAuth2Api',
    required: ['GOOGLE_OAUTH_CLIENT_ID', 'GOOGLE_OAUTH_CLIENT_SECRET'],
    data: () => ({ clientId: env.GOOGLE_OAUTH_CLIENT_ID, clientSecret: env.GOOGLE_OAUTH_CLIENT_SECRET }),
  },
];

const ready = [];
for (const credential of credentials) {
  const missing = credential.required.filter(name => !env[name]);
  if (missing.length) {
    console.warn(`skipped "${credential.name}": missing ${missing.join(', ')} in .env`);
    continue;
  }
  ready.push({ id: credential.id, name: credential.name, type: credential.type, data: credential.data() });
  console.log(`prepared "${credential.name}"`);
}

fs.writeFileSync(OUTPUT, JSON.stringify(ready), { mode: 0o600 });
