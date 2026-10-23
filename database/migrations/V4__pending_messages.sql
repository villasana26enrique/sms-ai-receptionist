-- Short-lived buffer for messages sent in a row: the agent waits a few seconds and answers once.
-- Rows live only seconds; the workflow deletes them after building the combined message.

CREATE TABLE dental_clinic.pending_messages (
  id          bigserial   PRIMARY KEY,
  phone       text        NOT NULL,
  message_id  text        NOT NULL UNIQUE,   -- Twilio MessageSid; UNIQUE drops repeated deliveries
  text        text        NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX pending_messages_phone ON dental_clinic.pending_messages (phone, id);
