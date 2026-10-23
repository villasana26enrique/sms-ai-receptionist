-- Chat history retention: deletes messages older than N days and returns how many were deleted.

CREATE OR REPLACE FUNCTION dental_clinic.purge_chat_history(p_days int DEFAULT 90)
RETURNS int
LANGUAGE sql
SET search_path = dental_clinic AS $$
  WITH deleted AS (
    DELETE FROM chat_history WHERE created_at < now() - make_interval(days => p_days) RETURNING 1
  )
  SELECT count(*)::int FROM deleted;
$$;