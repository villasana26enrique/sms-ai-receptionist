-- Look up, cancel and reschedule appointments.

SET search_path TO dental_clinic;

-- Upcoming confirmed appointments of the number that is writing
CREATE OR REPLACE FUNCTION get_my_appointments(p_phone text)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = dental_clinic AS $$
  SELECT jsonb_build_object(
    'ok', true,
    'appointments', coalesce(jsonb_agg(jsonb_build_object(
               'booking_code', a.booking_code,
               'service', s.name,
               'date', to_char(a.starts_at AT TIME ZONE c.time_zone, 'YYYY-MM-DD'),
               'weekday', to_char(a.starts_at AT TIME ZONE c.time_zone, 'FMDay'),
               'time', to_char(a.starts_at AT TIME ZONE c.time_zone, 'HH24:MI'))
             ORDER BY a.starts_at) FILTER (WHERE a.id IS NOT NULL), '[]'::jsonb),
    'message', CASE WHEN count(a.id) = 0 THEN 'No upcoming appointments for this number.' ELSE '' END)
  FROM clinic c
  LEFT JOIN patients p ON p.phone = p_phone
  LEFT JOIN appointments a ON a.patient_id = p.id AND a.status = 'confirmed' AND a.starts_at > now()
  LEFT JOIN services s ON s.id = a.service_id;
$$;


-- Finds an appointment by code and checks the sender may change it:
-- same mobile number, or the patient's full name when writing from another number
CREATE OR REPLACE FUNCTION authorize_appointment(p_code text, p_phone text, p_full_name text,
                                                 OUT appointment_id int, OUT reason text)
LANGUAGE plpgsql STABLE
SET search_path = dental_clinic AS $$
DECLARE
  v_phone     text;
  v_full_name text;
  v_status    text;
  v_starts_at timestamptz;
BEGIN
  SELECT a.id, p.phone, p.full_name, a.status, a.starts_at
  INTO appointment_id, v_phone, v_full_name, v_status, v_starts_at
  FROM appointments a JOIN patients p ON p.id = a.patient_id
  WHERE a.booking_code = upper(trim(p_code));

  IF appointment_id IS NULL THEN
    reason := 'There is no appointment with that code.';
  ELSIF v_phone <> p_phone
        AND lower(trim(coalesce(p_full_name, ''))) <> lower(trim(v_full_name)) THEN
    -- Same message as "not found", so other people's codes are never confirmed
    appointment_id := NULL;
    reason := 'There is no appointment with that code.';
  ELSIF v_status <> 'confirmed' THEN
    reason := 'That appointment is no longer active (status: ' || v_status || ').';
  ELSIF v_starts_at <= now() THEN
    reason := 'That appointment is in the past.';
  END IF;
END $$;


CREATE OR REPLACE FUNCTION cancel_appointment(p_phone text, p_code text, p_full_name text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = dental_clinic AS $$
DECLARE
  v_auth        record;
  v_appointment appointments%ROWTYPE;
BEGIN
  SELECT * INTO v_auth FROM authorize_appointment(p_code, p_phone, p_full_name);
  IF v_auth.reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'message', v_auth.reason);
  END IF;

  UPDATE appointments
  SET status = 'cancelled',
      calendar_synced = (google_event_id IS NULL),
      updated_at = now()
  WHERE id = v_auth.appointment_id
  RETURNING * INTO v_appointment;

  INSERT INTO appointment_history (appointment_id, action, details)
  VALUES (v_appointment.id, 'cancelled', jsonb_build_object('channel', 'sms'));

  RETURN jsonb_build_object(
    'ok', true,
    'appointment_id', v_appointment.id,
    'booking_code', v_appointment.booking_code,
    'google_event_id', v_appointment.google_event_id,
    'less_than_24h', v_appointment.starts_at < now() + interval '24 hours',
    'message', 'Appointment ' || v_appointment.booking_code || ' cancelled.');
END $$;


-- Moves the appointment to another day/time; keeps the booking code and the service
CREATE OR REPLACE FUNCTION reschedule_appointment(p_phone text, p_code text, p_date date, p_time time,
                                                  p_full_name text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = dental_clinic AS $$
DECLARE
  v_auth        record;
  v_appointment appointments%ROWTYPE;
  v_range       record;
  v_previous    timestamptz;
BEGIN
  SELECT * INTO v_auth FROM authorize_appointment(p_code, p_phone, p_full_name);
  IF v_auth.reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'message', v_auth.reason);
  END IF;

  SELECT * INTO v_appointment FROM appointments WHERE id = v_auth.appointment_id;
  v_previous := v_appointment.starts_at;

  SELECT * INTO v_range FROM appointment_range(v_appointment.service_id, p_date, p_time);
  IF v_range.reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'message', v_range.reason);
  END IF;

  BEGIN
    UPDATE appointments
    SET starts_at = v_range.starts_at, ends_at = v_range.ends_at,
        calendar_synced = false, updated_at = now()
    WHERE id = v_appointment.id
    RETURNING * INTO v_appointment;
  EXCEPTION WHEN exclusion_violation THEN
    RETURN jsonb_build_object('ok', false, 'message',
      'That time is already taken. Check availability again and offer another time.');
  END;

  INSERT INTO appointment_history (appointment_id, action, details)
  VALUES (v_appointment.id, 'rescheduled', jsonb_build_object('channel', 'sms', 'previous_starts_at', v_previous));

  RETURN jsonb_build_object(
    'ok', true,
    'appointment_id', v_appointment.id,
    'booking_code', v_appointment.booking_code,
    'service', (SELECT name FROM services WHERE id = v_appointment.service_id),
    'patient', (SELECT full_name FROM patients WHERE id = v_appointment.patient_id),
    'date', p_date,
    'time', to_char(p_time, 'HH24:MI'),
    'starts_at', v_appointment.starts_at,
    'ends_at', v_appointment.ends_at,
    'google_event_id', v_appointment.google_event_id,
    'message', 'Appointment ' || v_appointment.booking_code || ' rescheduled.');
END $$;


-- The Google Calendar event of a cancelled appointment was deleted
CREATE OR REPLACE FUNCTION mark_google_event_deleted(p_appointment_id int)
RETURNS void
LANGUAGE sql
SET search_path = dental_clinic AS $$
  UPDATE appointments
  SET google_event_id = NULL, calendar_synced = true, updated_at = now()
  WHERE id = p_appointment_id;
$$;
