-- Database tests for availability, booking, rescheduling and cancelling.
-- Runs inside a transaction that is always rolled back: it never leaves data behind.
-- Usage: psql -v ON_ERROR_STOP=1 -f booking_tests.sql   (prints "ALL TESTS PASSED" or stops at the first failure)

BEGIN;

DO $$
DECLARE
  monday   date := (date_trunc('week', now() + interval '7 days'))::date;  -- next week's Monday
  tuesday  date := monday + 1;
  sunday   date := monday + 6;
  r        jsonb;
  code     text;
  slots    jsonb;
BEGIN
  -- Closed on Sundays
  r := dental_clinic.get_available_slots(sunday, 'Routine cleaning');
  ASSERT (r->>'is_open')::boolean = false, 'Sunday should be closed';

  -- Booking a 90-minute service returns a booking code
  r := dental_clinic.book_appointment('test-1', 'Ana Test', 'Root canal', monday, '14:00');
  ASSERT (r->>'ok')::boolean, 'Booking should succeed: ' || r::text;
  code := r->>'booking_code';
  ASSERT code ~ '^MG-[A-HJ-NP-Z2-9]{5}$', 'Unexpected booking code format: ' || code;

  -- Overlapping booking is rejected by the database
  r := dental_clinic.book_appointment('test-2', 'Bob Test', 'Routine cleaning', monday, '15:00');
  ASSERT (r->>'ok')::boolean = false, 'Overlapping booking should be rejected';

  -- Availability respects the service duration: 13:00 ends exactly at 14:00, 13:30 would overlap
  slots := dental_clinic.get_available_slots(monday, 'Routine cleaning')->'available_slots';
  ASSERT slots ? '13:00' AND slots ? '15:30', 'Adjacent slots should be free';
  ASSERT NOT (slots ? '13:30' OR slots ? '14:00' OR slots ? '15:00'), 'Overlapping slots should be hidden';

  -- Validations
  r := dental_clinic.book_appointment('test-2', 'Bob Test', 'Root canal', monday, '17:00');
  ASSERT (r->>'ok')::boolean = false, 'A service ending after closing time should be rejected';
  r := dental_clinic.book_appointment('test-2', 'Bob Test', 'Consultation', monday, '10:00');
  ASSERT (r->>'ok')::boolean = false, 'Unknown service should be rejected';
  r := dental_clinic.book_appointment('test-2', 'Bob Test', 'Routine cleaning', current_date - 7, '10:00');
  ASSERT (r->>'ok')::boolean = false, 'Past dates should be rejected';
  r := dental_clinic.book_appointment('test-2', 'Bob Test', 'Routine cleaning', monday, '10:15');
  ASSERT (r->>'ok')::boolean = false, 'Times off the 30-minute grid should be rejected';

  -- The patient sees their own appointment
  r := dental_clinic.get_my_appointments('test-1');
  ASSERT jsonb_array_length(r->'appointments') = 1, 'Patient should see 1 appointment';
  r := dental_clinic.get_my_appointments('nobody');
  ASSERT jsonb_array_length(r->'appointments') = 0, 'Unknown number should see no appointments';

  -- Ownership: another number cannot touch the appointment without the patient's full name
  r := dental_clinic.cancel_appointment('test-2', code);
  ASSERT (r->>'ok')::boolean = false AND r->>'message' = 'There is no appointment with that code.',
    'Another number must not cancel (and must not learn the code exists)';

  -- Rescheduling keeps the code; the overlap rule also applies
  r := dental_clinic.reschedule_appointment('test-1', code, tuesday, '10:00');
  ASSERT (r->>'ok')::boolean AND r->>'booking_code' = code, 'Reschedule should keep the code';
  r := dental_clinic.book_appointment('test-2', 'Bob Test', 'Routine cleaning', tuesday, '11:00');
  ASSERT (r->>'ok')::boolean = false, 'Booking over the rescheduled appointment should be rejected';
  r := dental_clinic.book_appointment('test-2', 'Bob Test', 'Routine cleaning', monday, '14:00');
  ASSERT (r->>'ok')::boolean, 'The old slot should be free after rescheduling';

  -- Another number CAN cancel with the code + patient's full name; cancelling twice fails
  r := dental_clinic.cancel_appointment('test-2', lower(code), 'ana test');
  ASSERT (r->>'ok')::boolean, 'Code + full name should allow cancelling: ' || r::text;
  r := dental_clinic.cancel_appointment('test-1', code);
  ASSERT (r->>'ok')::boolean = false, 'Cancelling twice should fail';

  -- Full history is recorded
  ASSERT (SELECT string_agg(h.action, '>' ORDER BY h.id)
          FROM dental_clinic.appointment_history h
          JOIN dental_clinic.appointments a ON a.id = h.appointment_id
          WHERE a.booking_code = code) = 'created>rescheduled>cancelled', 'History should be complete';

  RAISE NOTICE 'ALL TESTS PASSED';
END $$;

ROLLBACK;
