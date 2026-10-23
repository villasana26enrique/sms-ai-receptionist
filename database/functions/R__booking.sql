-- Availability and booking. Called by the agent tools (n8n sub-workflows).
-- Every function pins search_path: n8n connects with the default schema (public).

SET search_path TO dental_clinic;

-- Shared validation for booking and rescheduling: returns the time range or the rejection reason
CREATE OR REPLACE FUNCTION appointment_range(p_service_id int, p_date date, p_time time,
                                             OUT starts_at timestamptz, OUT ends_at timestamptz, OUT reason text)
LANGUAGE plpgsql STABLE
SET search_path = dental_clinic AS $$
DECLARE
  v_time_zone    text;
  v_slot_minutes int;
  v_duration     int;
  v_hours        business_hours%ROWTYPE;
  v_local_start  timestamp;
  v_local_end    timestamp;
BEGIN
  SELECT time_zone, slot_minutes INTO v_time_zone, v_slot_minutes FROM clinic;
  SELECT duration_minutes INTO v_duration FROM services WHERE id = p_service_id;

  v_local_start := p_date + p_time;
  v_local_end   := v_local_start + make_interval(mins => v_duration);
  starts_at := v_local_start AT TIME ZONE v_time_zone;
  ends_at   := v_local_end AT TIME ZONE v_time_zone;

  SELECT * INTO v_hours FROM business_hours WHERE weekday = extract(isodow FROM p_date);
  IF NOT FOUND THEN
    reason := 'The clinic is closed that day.';
  ELSIF starts_at <= now() THEN
    reason := 'That time is in the past.';
  ELSIF v_local_start < p_date + v_hours.opens_at OR v_local_end > p_date + v_hours.closes_at THEN
    reason := 'Outside opening hours (' || to_char(v_hours.opens_at, 'HH24:MI') || '-'
              || to_char(v_hours.closes_at, 'HH24:MI') || ') for a ' || v_duration || '-minute service.';
  ELSIF (extract(hour FROM p_time) * 60 + extract(minute FROM p_time))::int % v_slot_minutes <> 0 THEN
    reason := 'Appointments start on ' || v_slot_minutes || '-minute slots (e.g. 09:00, 09:30).';
  END IF;
END $$;


-- Free start times on a day for a service, based on its duration
CREATE OR REPLACE FUNCTION get_available_slots(p_date date, p_service text)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = dental_clinic AS $$
DECLARE
  v_time_zone    text;
  v_slot_minutes int;
  v_service      services%ROWTYPE;
  v_hours        business_hours%ROWTYPE;
  v_duration     interval;
  v_slots        text[];
BEGIN
  SELECT time_zone, slot_minutes INTO v_time_zone, v_slot_minutes FROM clinic;

  SELECT * INTO v_service FROM services WHERE lower(name) = lower(trim(p_service)) AND is_active;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Unknown service. Use the exact name of one of the listed services.',
      'services', (SELECT jsonb_agg(name ORDER BY id) FROM services WHERE is_active));
  END IF;
  v_duration := make_interval(mins => v_service.duration_minutes);

  SELECT * INTO v_hours FROM business_hours WHERE weekday = extract(isodow FROM p_date);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'date', p_date, 'weekday', to_char(p_date, 'FMDay'),
      'is_open', false, 'available_slots', '[]'::jsonb, 'message', 'The clinic is closed that day.');
  END IF;

  -- Every possible start (clinic local time) where the whole service fits before closing
  SELECT coalesce(array_agg(to_char(local_start, 'HH24:MI') ORDER BY local_start), '{}')
  INTO v_slots
  FROM generate_series(p_date + v_hours.opens_at,
                       p_date + v_hours.closes_at - v_duration,
                       make_interval(mins => v_slot_minutes)) AS local_start
  WHERE (local_start AT TIME ZONE v_time_zone) > now()
    AND NOT EXISTS (
      SELECT 1 FROM appointments a
      WHERE a.status = 'confirmed'
        AND tstzrange(a.starts_at, a.ends_at) && tstzrange(local_start AT TIME ZONE v_time_zone,
                                                           (local_start + v_duration) AT TIME ZONE v_time_zone));

  RETURN jsonb_build_object(
    'ok', true,
    'date', p_date,
    'weekday', to_char(p_date, 'FMDay'),
    'is_open', true,
    'opening_hours', to_char(v_hours.opens_at, 'HH24:MI') || '-' || to_char(v_hours.closes_at, 'HH24:MI'),
    'service', v_service.name,
    'duration_minutes', v_service.duration_minutes,
    'available_slots', to_jsonb(v_slots),
    'message', CASE WHEN cardinality(v_slots) = 0
                    THEN 'No free times left that day for this service.' ELSE '' END);
END $$;


-- Books an appointment; returns ok=false with the reason instead of raising errors
CREATE OR REPLACE FUNCTION book_appointment(p_phone text, p_full_name text, p_service text,
                                            p_date date, p_time time)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = dental_clinic AS $$
DECLARE
  v_service        services%ROWTYPE;
  v_range          record;
  v_patient_id     int;
  v_appointment_id int;
  v_code           text;
BEGIN
  SELECT * INTO v_service FROM services WHERE lower(name) = lower(trim(p_service)) AND is_active;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Unknown service. Use the exact name of one of the listed services.');
  END IF;

  SELECT * INTO v_range FROM appointment_range(v_service.id, p_date, p_time);
  IF v_range.reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'message', v_range.reason);
  END IF;

  -- The mobile number identifies the patient; an existing name is kept
  INSERT INTO patients (phone, full_name)
  VALUES (p_phone, p_full_name)
  ON CONFLICT (phone) DO UPDATE SET phone = EXCLUDED.phone
  RETURNING id INTO v_patient_id;

  BEGIN
    INSERT INTO appointments (patient_id, service_id, starts_at, ends_at)
    VALUES (v_patient_id, v_service.id, v_range.starts_at, v_range.ends_at)
    RETURNING id, booking_code INTO v_appointment_id, v_code;
  EXCEPTION WHEN exclusion_violation THEN
    RETURN jsonb_build_object('ok', false, 'message',
      'That time is already taken. Check availability again and offer another time.');
  END;

  INSERT INTO appointment_history (appointment_id, action, details)
  VALUES (v_appointment_id, 'created', jsonb_build_object('channel', 'sms', 'given_name', p_full_name));

  RETURN jsonb_build_object(
    'ok', true,
    'appointment_id', v_appointment_id,
    'booking_code', v_code,
    'service', v_service.name,
    'patient', (SELECT full_name FROM patients WHERE id = v_patient_id),
    'date', p_date,
    'time', to_char(p_time, 'HH24:MI'),
    'duration_minutes', v_service.duration_minutes,
    'starts_at', v_range.starts_at,
    'ends_at', v_range.ends_at,
    'message', 'Appointment booked. Booking code: ' || v_code);
END $$;


-- Google Calendar now reflects the appointment (event created or updated); without an id it does nothing
CREATE OR REPLACE FUNCTION set_google_event(p_appointment_id int, p_event_id text)
RETURNS void
LANGUAGE sql
SET search_path = dental_clinic AS $$
  UPDATE appointments
  SET google_event_id = p_event_id, calendar_synced = true, updated_at = now()
  WHERE id = p_appointment_id AND p_event_id IS NOT NULL;
$$;
