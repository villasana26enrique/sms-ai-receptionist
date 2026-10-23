-- Agent chat memory, written by n8n's "Postgres Chat Memory" node.
-- The node expects id, session_id and message; created_at is ours, for retention.

CREATE TABLE dental_clinic.chat_history (
  id         serial       PRIMARY KEY,
  session_id varchar(255) NOT NULL,            -- patient's mobile number
  message    jsonb        NOT NULL,            -- {type: human | ai, content, ...}
  created_at timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX chat_history_session ON dental_clinic.chat_history (session_id, id);
CREATE INDEX chat_history_created ON dental_clinic.chat_history (created_at);
