-- Message buffer cleanup: rows normally live a few seconds; anything older was left behind by a failed run.
-- Deletes rows older than N minutes and returns how many were deleted.

CREATE OR REPLACE FUNCTION dental_clinic.purge_stale_pending_messages(p_minutes int DEFAULT 60)
RETURNS int
LANGUAGE sql
SET search_path = dental_clinic AS $$
  WITH deleted AS (
    DELETE FROM pending_messages WHERE received_at < now() - make_interval(mins => p_minutes) RETURNING 1
  )
  SELECT count(*)::int FROM deleted;
$$;
