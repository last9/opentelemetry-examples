-- Create monitoring schema
CREATE SCHEMA IF NOT EXISTS otel_monitor;

-- Create wrapper function for pg_stat_activity
CREATE OR REPLACE FUNCTION otel_monitor.pg_stat_activity()
RETURNS SETOF pg_stat_activity AS $$
    SELECT * FROM pg_catalog.pg_stat_activity;
$$ LANGUAGE sql SECURITY DEFINER;

-- Create wrapper function for pg_stat_statements
CREATE OR REPLACE FUNCTION otel_monitor.pg_stat_statements()
RETURNS SETOF pg_stat_statements AS $$
    SELECT * FROM public.pg_stat_statements;
$$ LANGUAGE sql SECURITY DEFINER;

-- Create explain_statement function
CREATE OR REPLACE FUNCTION otel_monitor.explain_statement(
    l_query TEXT,
    OUT explain JSON
)
RETURNS SETOF JSON AS $$
DECLARE
    curs REFCURSOR;
    plan JSON;
BEGIN
    IF l_query !~* '^\s*(SELECT|UPDATE|INSERT|DELETE)' THEN
        RETURN;
    END IF;
    BEGIN
        OPEN curs FOR EXECUTE 'EXPLAIN (FORMAT JSON, COSTS true) ' || l_query;
        FETCH curs INTO plan;
        CLOSE curs;
        explain := plan;
        RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create blocking queries view
CREATE OR REPLACE VIEW otel_monitor.blocking_queries AS
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocked_activity.datname AS database,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_query,
    blocking_activity.query AS blocking_query,
    blocked_activity.query_start AS blocked_query_start,
    blocked_locks.locktype AS lock_type
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- Create wait events view
CREATE OR REPLACE VIEW otel_monitor.wait_events AS
SELECT
    datname AS database,
    wait_event_type,
    wait_event,
    count(*) AS count
FROM pg_catalog.pg_stat_activity
WHERE wait_event IS NOT NULL
    AND state = 'active'
    AND backend_type = 'client backend'
GROUP BY datname, wait_event_type, wait_event;

SELECT 'Monitoring schema created successfully!' AS status;
