// Copies the versioned workflows to a temp folder, filling in values from the environment, for `n8n import:workflow`.
// Runs inside the n8n container: node /repo/scripts/prepare-import.js
const fs = require('fs');
const path = require('path');

const SOURCE = '/repo/workflows';
const TARGET = '/tmp/workflows-to-import';
const calendarId = process.env.GOOGLE_CALENDAR_ID;
// Optional: without it the clinic documents tool answers that it cannot check them
const ragSearchUrl = process.env.RAG_SEARCH_URL || 'http://rag-search-url-not-configured.invalid/webhook/search';
// The signature check needs the exact public URL Twilio calls; without the token every SMS is rejected (403)
const twilioWebhookUrl = (process.env.N8N_WEBHOOK_URL || '').replace(/\/?$/, '/') + 'webhook/twilio/sms';
const twilioAuthToken = process.env.TWILIO_AUTH_TOKEN;
if (!twilioAuthToken) console.warn('TWILIO_AUTH_TOKEN is not set in .env: incoming SMS will be rejected');

if (!calendarId) {
  console.error('GOOGLE_CALENDAR_ID is not set in .env');
  process.exit(1);
}

fs.rmSync(TARGET, { recursive: true, force: true });
fs.mkdirSync(TARGET, { recursive: true });

for (const file of fs.readdirSync(SOURCE).filter(f => f.endsWith('.json'))) {
  const content = fs.readFileSync(path.join(SOURCE, file), 'utf8')
    .replaceAll('__GOOGLE_CALENDAR_ID__', calendarId)
    .replaceAll('__RAG_SEARCH_URL__', ragSearchUrl)
    .replaceAll('__TWILIO_WEBHOOK_URL__', twilioWebhookUrl)
    .replaceAll('__TWILIO_AUTH_TOKEN__', twilioAuthToken || '__TWILIO_AUTH_TOKEN__');
  fs.writeFileSync(path.join(TARGET, file), content, { mode: 0o600 });
  console.log(`prepared ${file}`);
}
