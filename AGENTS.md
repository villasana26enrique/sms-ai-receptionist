# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, …) working in this repository.
Read `README.md` first for what the project does and how it is structured.

## Project in one paragraph

An SMS AI receptionist (Twilio) for a fictional dental clinic. n8n hosts the agent (Gemini chat model, Postgres chat
memory, six tools). Five tools are n8n sub-workflows that call PL/pgSQL functions in the `dental_clinic` schema;
the sixth, `search_clinic_documents`, calls the search API of the separate RAG knowledge assistant project.
PostgreSQL is the source of truth; Google Calendar is only a mirror kept in sync by a scheduled workflow.
It is a copy of `whatsapp-ai-receptionist` with the channel replaced: when a change touches the shared core (prompt,
tools, memory, models, SQL), say whether it should be ported to that repository too.

## Conventions

- **Everything technical is in English**: tables, columns, functions, workflow and node names, files, comments,
  commit messages, docs. Messages returned to the LLM are English too (the agent replies in the patient's language).
- **Business rules live in the database**, not in n8n Code nodes or prompts. n8n nodes stay thin:
  call a function, branch on `ok`, pass `message` back to the agent.
- Database functions return `jsonb` with `ok` and `message` instead of raising errors for business cases.
- Every function declares `SET search_path = dental_clinic` (n8n connects with the default schema; without it the
  function cannot find its tables).
- Times are `timestamptz`; the clinic time zone is in `dental_clinic.clinic.time_zone`.
- Cancelling is a soft delete (`status = 'cancelled'`); every change is logged in `appointment_history`.

## Database changes (Flyway)

- New tables, columns or data: add `database/migrations/V<next>__short_description.sql`.
  **Never modify a versioned migration that has already been applied.**
- Functions: edit or add `database/functions/R__*.sql` with `CREATE OR REPLACE`; Flyway re-applies them on change.
- Apply: `docker compose run --rm flyway` (also runs on `docker compose up`).
- Run the tests after any database change and keep them green:

  ```bash
  docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < database/tests/booking_tests.sql
  ```

  Add a test for new behavior in `database/tests/booking_tests.sql` (it runs in a rolled-back transaction).

## n8n workflow changes

- The JSON files in `n8n/workflows/` are the source of truth for the repository, but n8n runs from its own database.
  After changing a workflow in n8n, run `./scripts/export-workflows.sh` and commit the result.
- Sub-workflows are referenced **by id** from the agent's tool nodes; keep ids stable (import preserves them).
  New workflows must be added to the id map in `scripts/export-workflows.sh` and to the publish list in
  `scripts/reload-workflows.sh` (sub-workflows first).
- **Importing a workflow unpublishes it.** Load workflow changes with `./scripts/reload-workflows.sh` (imports and
  publishes them all); never import a single file by hand.
- Never hard-code personal or instance data in workflows: the calendar id is `__GOOGLE_CALENDAR_ID__` and the RAG
  search URL is `__RAG_SEARCH_URL__` in the exported files; credentials are referenced, never embedded.
- The signature check (`Verify Twilio signature`) holds `__TWILIO_AUTH_TOKEN__` and `__TWILIO_WEBHOOK_URL__` in the
  repository; `prepare-import.js` fills them in and `clean-export.js` puts them back. Before committing an export,
  check that both are still placeholders. Never remove the check or answer `200` before it.
- Twilio expects an answer within 15 seconds: the webhook replies with an empty TwiML first, and the agent's reply
  is sent with the Twilio node. Keep replies SMS-sized (the prompt asks for 1 to 3 sentences, no emojis).
- AI Agent nodes have a fallback model (`needsFallback`, a second chat model on input 1): keep both, so a 503 from
  one Gemini model does not leave the user without an answer.
- AI Agent nodes keep `options.maxTokensFromMemory` (8000). It makes n8n trim the memory so the history always
  starts on a user message. Without it, the memory window (which counts tool calls as messages) can start in the
  middle of a tool call, and Gemini 3 rejects the request with 400 "function call turn comes immediately after a user
  turn". The option is hidden in the n8n UI: keep it in the JSON.
- The clinic documents tool sends only the question to the RAG service, never the patient's phone number.
- `./scripts/setup-n8n.sh` is for a fresh instance: it re-creates credentials and overwrites workflows by id.
  Do not run it against an instance in use unless that is the intent.
- Credential ids are fixed in `n8n/scripts/build-credentials.js` and referenced by the workflows; keep them in sync.
- To test a setup without touching the running stack, use another project and env file:
  `COMPOSE_PROJECT_NAME=test docker compose --env-file .env.test up -d` and
  `COMPOSE_PROJECT_NAME=test ENV_FILE=.env.test ./scripts/setup-n8n.sh` (with different ports and volume names).

## Testing without a phone

`python scripts/simulate-sms.py "<text>" [--from +1555…] [--bad-signature] [--message-sid SM…]` posts a fake SMS
signed with the Auth Token from `.env`. Use fake numbers, and delete their rows (`patients`, `appointments`,
`appointment_history`, `chat_history`) when done.

## Secrets

- Never commit `.env`. Document every new variable in `.env.example` with a fake value.
- Before committing, check that no token, API key, phone number or email appears in the diff.

## Useful commands

| Task | Command |
|---|---|
| Start everything | `docker compose up -d` |
| Logs | `docker compose logs -f n8n` |
| Apply migrations | `docker compose run --rm flyway` |
| Database shell | `docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'` |
| Export workflows | `./scripts/export-workflows.sh` |
| Load workflow changes into n8n | `./scripts/reload-workflows.sh` |
| Set up a fresh n8n (credentials + workflows + publish) | `./scripts/setup-n8n.sh` |
| Send a signed fake SMS | `python scripts/simulate-sms.py "Hi"` |
