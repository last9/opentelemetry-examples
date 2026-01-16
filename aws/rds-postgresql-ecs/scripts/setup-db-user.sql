-- =============================================================================
-- PostgreSQL Monitoring User Setup Script
-- For RDS PostgreSQL Deep Integration with Last9
-- =============================================================================

-- This script creates a dedicated monitoring user with appropriate permissions
-- for comprehensive database monitoring without requiring superuser access.

-- Run this script as the master user (usually 'postgres' on RDS)
-- Execute on EACH database you want to monitor

-- =============================================================================
-- STEP 1: Create the monitoring user (run once, on any database)
-- =============================================================================
-- Replace '<SECURE_PASSWORD>' with a strong password from Secrets Manager

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'otel_monitor') THEN
        CREATE USER otel_monitor WITH PASSWORD '<SECURE_PASSWORD>';
        RAISE NOTICE 'User otel_monitor created successfully';
    ELSE
        RAISE NOTICE 'User otel_monitor already exists';
    END IF;
END
$$;

-- =============================================================================
-- STEP 2: Grant pg_monitor role (PostgreSQL 10+)
-- =============================================================================
-- This provides read access to pg_stat_* views without superuser

GRANT pg_monitor TO otel_monitor;

-- =============================================================================
-- STEP 3: Create dedicated schema for monitoring functions
-- =============================================================================
-- We use 'otel_monitor' schema for organizing monitoring functions

CREATE SCHEMA IF NOT EXISTS otel_monitor;
GRANT USAGE ON SCHEMA otel_monitor TO otel_monitor;
GRANT USAGE ON SCHEMA public TO otel_monitor;

-- =============================================================================
-- STEP 4: Enable pg_stat_statements extension
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;

-- Verify extension is installed
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        RAISE NOTICE 'pg_stat_statements extension is installed';
    ELSE
        RAISE EXCEPTION 'pg_stat_statements extension failed to install';
    END IF;
END
$$;

-- =============================================================================
-- STEP 5: Create wrapper functions (SECURITY DEFINER pattern)
-- =============================================================================
-- These functions allow the monitoring user to access stats without direct grants

-- Wrapper for pg_stat_activity
CREATE OR REPLACE FUNCTION otel_monitor.pg_stat_activity()
RETURNS SETOF pg_stat_activity AS $$
    SELECT * FROM pg_catalog.pg_stat_activity;
$$ LANGUAGE sql SECURITY DEFINER;

-- Wrapper for pg_stat_statements
CREATE OR REPLACE FUNCTION otel_monitor.pg_stat_statements()
RETURNS SETOF pg_stat_statements AS $$
    SELECT * FROM public.pg_stat_statements;
$$ LANGUAGE sql SECURITY DEFINER;

-- Wrapper for pg_stat_statements_info (PostgreSQL 14+)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pg_stat_statements_info') THEN
        EXECUTE '
            CREATE OR REPLACE FUNCTION otel_monitor.pg_stat_statements_info()
            RETURNS pg_stat_statements_info AS $func$
                SELECT * FROM pg_stat_statements_info();
            $func$ LANGUAGE sql SECURITY DEFINER;
        ';
        RAISE NOTICE 'Created pg_stat_statements_info wrapper (PostgreSQL 14+)';
    END IF;
END
$$;

-- =============================================================================
-- STEP 6: Create explain_statement function for query plans
-- =============================================================================
-- This allows collecting EXPLAIN plans without full superuser access

CREATE OR REPLACE FUNCTION otel_monitor.explain_statement(
    l_query TEXT,
    OUT explain JSON
)
RETURNS SETOF JSON AS $$
DECLARE
    curs REFCURSOR;
    plan JSON;
BEGIN
    -- Only explain SELECT, UPDATE, INSERT, DELETE statements
    IF l_query !~* '^\s*(SELECT|UPDATE|INSERT|DELETE)' THEN
        RETURN;
    END IF;

    -- Execute EXPLAIN and return JSON plan
    BEGIN
        OPEN curs FOR EXECUTE 'EXPLAIN (FORMAT JSON, COSTS true) ' || l_query;
        FETCH curs INTO plan;
        CLOSE curs;
        explain := plan;
        RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
        -- Silently fail for queries that can't be explained
        RETURN;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- STEP 7: Create blocking queries view
-- =============================================================================

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
    blocked_locks.locktype AS lock_type,
    blocked_locks.mode AS blocked_mode,
    blocking_locks.mode AS blocking_mode,
    blocked_activity.wait_event_type,
    blocked_activity.wait_event
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
    ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

GRANT SELECT ON otel_monitor.blocking_queries TO otel_monitor;

-- =============================================================================
-- STEP 8: Create wait events aggregation view
-- =============================================================================

CREATE OR REPLACE VIEW otel_monitor.wait_events AS
SELECT
    datname AS database,
    wait_event_type,
    wait_event,
    count(*) AS count,
    array_agg(pid) AS pids
FROM pg_catalog.pg_stat_activity
WHERE wait_event IS NOT NULL
    AND state = 'active'
    AND backend_type = 'client backend'
GROUP BY datname, wait_event_type, wait_event;

GRANT SELECT ON otel_monitor.wait_events TO otel_monitor;

-- =============================================================================
-- STEP 9: Create slow queries view
-- =============================================================================

-- Create slow_queries view with version compatibility
-- query_id is only available in PostgreSQL 14+, so we conditionally include it
DO $$
BEGIN
    -- Check PostgreSQL version
    IF current_setting('server_version_num')::integer >= 140000 THEN
        -- PostgreSQL 14+ with query_id
        EXECUTE '
            CREATE OR REPLACE VIEW otel_monitor.slow_queries AS
            SELECT
                pid,
                datname AS database,
                usename AS username,
                application_name,
                client_addr,
                backend_start,
                xact_start,
                query_start,
                state_change,
                wait_event_type,
                wait_event,
                state,
                backend_xid,
                backend_xmin,
                left(query, 4096) AS query,
                query_id,
                EXTRACT(EPOCH FROM (now() - query_start)) AS duration_seconds
            FROM pg_catalog.pg_stat_activity
            WHERE state = ''active''
                AND query NOT LIKE ''%pg_stat_activity%''
                AND query NOT LIKE ''%otel_monitor%''
                AND backend_type = ''client backend''
                AND query_start < now() - interval ''100 milliseconds''
            ORDER BY duration_seconds DESC;
        ';
        RAISE NOTICE 'Created slow_queries view with query_id (PostgreSQL 14+)';
    ELSE
        -- PostgreSQL 11-13 without query_id
        EXECUTE '
            CREATE OR REPLACE VIEW otel_monitor.slow_queries AS
            SELECT
                pid,
                datname AS database,
                usename AS username,
                application_name,
                client_addr,
                backend_start,
                xact_start,
                query_start,
                state_change,
                wait_event_type,
                wait_event,
                state,
                backend_xid,
                backend_xmin,
                left(query, 4096) AS query,
                EXTRACT(EPOCH FROM (now() - query_start)) AS duration_seconds
            FROM pg_catalog.pg_stat_activity
            WHERE state = ''active''
                AND query NOT LIKE ''%pg_stat_activity%''
                AND query NOT LIKE ''%otel_monitor%''
                AND backend_type = ''client backend''
                AND query_start < now() - interval ''100 milliseconds''
            ORDER BY duration_seconds DESC;
        ';
        RAISE NOTICE 'Created slow_queries view without query_id (PostgreSQL < 14)';
    END IF;
END
$$;

GRANT SELECT ON otel_monitor.slow_queries TO otel_monitor;

-- =============================================================================
-- STEP 10: Grant function execution permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION otel_monitor.pg_stat_activity() TO otel_monitor;
GRANT EXECUTE ON FUNCTION otel_monitor.pg_stat_statements() TO otel_monitor;
GRANT EXECUTE ON FUNCTION otel_monitor.explain_statement(TEXT) TO otel_monitor;

-- =============================================================================
-- STEP 11: Set search path for the monitoring user
-- =============================================================================
-- Ensures pg_stat_statements is accessible

ALTER ROLE otel_monitor SET search_path = "$user", public, otel_monitor;

-- =============================================================================
-- STEP 12: Grant CONNECT to database
-- =============================================================================

DO $$
DECLARE
    db_name TEXT;
BEGIN
    SELECT current_database() INTO db_name;
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO otel_monitor', db_name);
    RAISE NOTICE 'Granted CONNECT on database % to otel_monitor', db_name;
END
$$;

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

-- Check user and roles
SELECT
    r.rolname,
    r.rolsuper,
    ARRAY(SELECT b.rolname
          FROM pg_catalog.pg_auth_members m
          JOIN pg_catalog.pg_roles b ON (m.roleid = b.oid)
          WHERE m.member = r.oid) as memberof
FROM pg_catalog.pg_roles r
WHERE r.rolname = 'otel_monitor';

-- Check extensions
SELECT extname, extversion, nspname as schema
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE extname = 'pg_stat_statements';

-- Test wrapper functions
SELECT count(*) as activity_count FROM otel_monitor.pg_stat_activity();
SELECT count(*) as statements_count FROM otel_monitor.pg_stat_statements();

-- Test views
SELECT * FROM otel_monitor.blocking_queries LIMIT 1;
SELECT * FROM otel_monitor.wait_events LIMIT 5;
SELECT * FROM otel_monitor.slow_queries LIMIT 5;

-- =============================================================================
-- NOTES FOR RDS PARAMETER GROUP
-- =============================================================================
/*
Required RDS Parameter Group settings (requires instance reboot):

Parameter                        | Value           | Notes
---------------------------------|-----------------|----------------------------------
shared_preload_libraries         | pg_stat_statements | Required for extension
pg_stat_statements.track         | all             | Track all statements
pg_stat_statements.max           | 10000           | Max tracked statements
track_io_timing                  | on              | For I/O statistics
track_activity_query_size        | 4096            | Query text length
log_min_duration_statement       | 100             | Log slow queries (ms)
track_functions                  | all             | Track function calls

To modify: RDS Console → Parameter Groups → Create/Modify → Reboot instance
*/

-- =============================================================================
-- MULTI-DATABASE SETUP
-- =============================================================================
/*
For multiple databases, connect to EACH database and run:

\c your_database_name
CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;

Then run this full script on each database to create the schema and functions.
*/

-- =============================================================================
-- CLEANUP (if needed)
-- =============================================================================
/*
-- To remove all monitoring objects:
DROP SCHEMA IF EXISTS otel_monitor CASCADE;
REVOKE pg_monitor FROM otel_monitor;
REVOKE CONNECT ON DATABASE current_database() FROM otel_monitor;
DROP USER IF EXISTS otel_monitor;
*/

\echo 'Setup complete! Verify with: SELECT * FROM otel_monitor.pg_stat_statements() LIMIT 5;'
