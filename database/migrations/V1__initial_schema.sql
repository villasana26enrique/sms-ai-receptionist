-- Dental clinic demo (Maple Grove Dental Studio): tables and constraints.
-- Versioned migration: runs once. Functions live in database/functions (repeatable migrations).

CREATE SCHEMA IF NOT EXISTS dental_clinic;
SET search_path TO dental_clinic;

-- General clinic settings (single row)
CREATE TABLE clinic (
  id           smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  name         text     NOT NULL,
  time_zone    text     NOT NULL,
  slot_minutes smallint NOT NULL DEFAULT 30 CHECK (slot_minutes > 0)
);

-- Opening hours; ISO weekday: 1 = Monday ... 7 = Sunday (no row = closed)
CREATE TABLE business_hours (
  weekday   smallint PRIMARY KEY CHECK (weekday BETWEEN 1 AND 7),
  opens_at  time NOT NULL,
  closes_at time NOT NULL,
  CHECK (opens_at < closes_at)
);

CREATE TABLE services (
  id               serial PRIMARY KEY,
  name             text     NOT NULL UNIQUE,
  duration_minutes smallint NOT NULL CHECK (duration_minutes > 0 AND duration_minutes % 30 = 0),
  price_from       numeric(10, 2),
  is_active        boolean  NOT NULL DEFAULT true
);

-- The mobile number (digits only, with country code) identifies the patient
CREATE TABLE patients (
  id             serial PRIMARY KEY,
  phone          text        NOT NULL UNIQUE,
  full_name      text        NOT NULL,
  birth_date     date,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- Booking code: MG- + 5 characters, excluding easily confused ones (0/O, 1/I).
-- Defined here (not in functions/) because the appointments table uses it as a column default.
CREATE FUNCTION generate_booking_code() RETURNS text
LANGUAGE plpgsql
SET search_path = dental_clinic AS $$
DECLARE
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
BEGIN
  LOOP
    code := 'MG-';
    FOR i IN 1..5 LOOP
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM appointments WHERE booking_code = code);
  END LOOP;
  RETURN code;
END $$;

CREATE TABLE appointments (
  id              serial PRIMARY KEY,
  booking_code    text        NOT NULL UNIQUE DEFAULT generate_booking_code(),
  patient_id      int         NOT NULL REFERENCES patients (id),
  service_id      int         NOT NULL REFERENCES services (id),
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  status          text        NOT NULL DEFAULT 'confirmed'
                    CHECK (status IN ('confirmed', 'cancelled', 'completed', 'no_show')),
  google_event_id text,
  -- false = the Google Calendar mirror event does not reflect the latest change yet
  calendar_synced boolean     NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (starts_at < ends_at),
  -- Double booking is impossible: two confirmed appointments cannot overlap (single chair)
  CONSTRAINT appointments_no_overlap
    EXCLUDE USING gist (tstzrange(starts_at, ends_at) WITH &&) WHERE (status = 'confirmed')
);
CREATE INDEX appointments_patient_starts ON appointments (patient_id, starts_at);

-- What happened to each appointment and when
CREATE TABLE appointment_history (
  id             bigserial PRIMARY KEY,
  appointment_id int         NOT NULL REFERENCES appointments (id),
  action         text        NOT NULL CHECK (action IN ('created', 'rescheduled', 'cancelled')),
  details        jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX appointment_history_appointment ON appointment_history (appointment_id);
