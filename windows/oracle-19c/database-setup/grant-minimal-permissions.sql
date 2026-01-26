-- Grant Minimal Permissions for Oracle Monitoring
-- Purpose: Grant SELECT on V$ views required for OpenTelemetry monitoring
-- Security: Read-only access to performance views, no access to application data
--
-- Usage:
--   sqlplus / as sysdba @grant-minimal-permissions.sql
--
-- Prerequisites:
--   - User last9_monitor must exist (run create-monitoring-user.sql first)
--
-- Version: Oracle 19c
-- Last Updated: 2025-11-29

SET ECHO ON
SET SERVEROUTPUT ON

PROMPT =========================================
PROMPT Granting Minimal Permissions
PROMPT =========================================
PROMPT

-- Verify user exists
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM dba_users
    WHERE username = 'LAST9_MONITOR';

    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error: User LAST9_MONITOR does not exist!');
        DBMS_OUTPUT.PUT_LINE('  Run create-monitoring-user.sql first');
        RAISE_APPLICATION_ERROR(-20002, 'User does not exist');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✓ User LAST9_MONITOR found');
    END IF;
END;
/

-- Grant SELECT on required V$ views
-- These views contain performance statistics and metadata only (no application data)

PROMPT
PROMPT Granting SELECT on V$ performance views...
PROMPT

-- Session and Process Information
GRANT SELECT ON V_$SESSION TO last9_monitor;
GRANT SELECT ON V_$PROCESS TO last9_monitor;
GRANT SELECT ON V_$SESSTAT TO last9_monitor;
GRANT SELECT ON V_$SESSION_WAIT TO last9_monitor;
GRANT SELECT ON V_$SESSION_WAIT_CLASS TO last9_monitor;
GRANT SELECT ON V_$SESSION_WAIT_HISTORY TO last9_monitor;

-- System Statistics
GRANT SELECT ON V_$SYSSTAT TO last9_monitor;
GRANT SELECT ON V_$SYSMETRIC TO last9_monitor;
GRANT SELECT ON V_$SYSMETRIC_HISTORY TO last9_monitor;
GRANT SELECT ON V_$SYSTEM_EVENT TO last9_monitor;
GRANT SELECT ON V_$SYSTEM_WAIT_CLASS TO last9_monitor;

-- Database and Instance Information
GRANT SELECT ON V_$DATABASE TO last9_monitor;
GRANT SELECT ON V_$INSTANCE TO last9_monitor;
GRANT SELECT ON V_$PARAMETER TO last9_monitor;
GRANT SELECT ON V_$SYSTEM_PARAMETER TO last9_monitor;

-- Resource Limits and Usage
GRANT SELECT ON V_$RESOURCE_LIMIT TO last9_monitor;
GRANT SELECT ON V_$RESOURCE TO last9_monitor;
GRANT SELECT ON V_$RESOURCE_CURRENT_LIMIT TO last9_monitor;

-- SQL and Execution Statistics
GRANT SELECT ON V_$SQL TO last9_monitor;
GRANT SELECT ON V_$SQLAREA TO last9_monitor;
GRANT SELECT ON V_$SQLSTATS TO last9_monitor;
GRANT SELECT ON V_$SQL_PLAN TO last9_monitor;
GRANT SELECT ON V_$SQL_PLAN_STATISTICS TO last9_monitor;
GRANT SELECT ON V_$SQL_PLAN_STATISTICS_ALL TO last9_monitor;

-- Tablespace and Storage
GRANT SELECT ON DBA_TABLESPACES TO last9_monitor;
GRANT SELECT ON DBA_DATA_FILES TO last9_monitor;
GRANT SELECT ON DBA_TEMP_FILES TO last9_monitor;
GRANT SELECT ON DBA_FREE_SPACE TO last9_monitor;
GRANT SELECT ON DBA_TABLESPACE_USAGE_METRICS TO last9_monitor;

-- Wait Events
GRANT SELECT ON V_$EVENT_NAME TO last9_monitor;
GRANT SELECT ON V_$WAITSTAT TO last9_monitor;

-- I/O Statistics
GRANT SELECT ON V_$FILESTAT TO last9_monitor;
GRANT SELECT ON V_$TEMPSTAT TO last9_monitor;
GRANT SELECT ON V_$IOSTAT_FILE TO last9_monitor;
GRANT SELECT ON V_$IOSTAT_FUNCTION TO last9_monitor;

-- Memory and SGA
GRANT SELECT ON V_$SGA TO last9_monitor;
GRANT SELECT ON V_$SGASTAT TO last9_monitor;
GRANT SELECT ON V_$SGAINFO TO last9_monitor;
GRANT SELECT ON V_$PGA_TARGET_ADVICE TO last9_monitor;

-- Parallel Execution
GRANT SELECT ON V_$PX_PROCESS TO last9_monitor;
GRANT SELECT ON V_$PX_SESSION TO last9_monitor;
GRANT SELECT ON V_$PQ_SESSTAT TO last9_monitor;

-- Redo and Archive Logs
GRANT SELECT ON V_$LOG TO last9_monitor;
GRANT SELECT ON V_$LOGFILE TO last9_monitor;
GRANT SELECT ON V_$LOG_HISTORY TO last9_monitor;
GRANT SELECT ON V_$ARCHIVED_LOG TO last9_monitor;

-- Library Cache and Shared Pool
GRANT SELECT ON V_$LIBRARYCACHE TO last9_monitor;
GRANT SELECT ON V_$ROWCACHE TO last9_monitor;

-- Locks and Latches
GRANT SELECT ON V_$LOCK TO last9_monitor;
GRANT SELECT ON V_$LATCH TO last9_monitor;
GRANT SELECT ON V_$LATCH_CHILDREN TO last9_monitor;

-- Additional DBA views for comprehensive monitoring
GRANT SELECT ON DBA_OBJECTS TO last9_monitor;
GRANT SELECT ON DBA_SEGMENTS TO last9_monitor;

PROMPT
PROMPT ✓ All permissions granted successfully!
PROMPT

-- Summary of granted permissions
PROMPT
PROMPT =========================================
PROMPT Permission Summary
PROMPT =========================================
SELECT
    GRANTEE,
    COUNT(*) AS TOTAL_PRIVILEGES
FROM (
    SELECT GRANTEE FROM DBA_TAB_PRIVS WHERE GRANTEE = 'LAST9_MONITOR'
    UNION ALL
    SELECT GRANTEE FROM DBA_SYS_PRIVS WHERE GRANTEE = 'LAST9_MONITOR'
    UNION ALL
    SELECT GRANTEE FROM DBA_ROLE_PRIVS WHERE GRANTEE = 'LAST9_MONITOR'
)
WHERE GRANTEE = 'LAST9_MONITOR'
GROUP BY GRANTEE;

PROMPT
PROMPT Roles Granted:
SELECT * FROM DBA_ROLE_PRIVS WHERE GRANTEE = 'LAST9_MONITOR';

PROMPT
PROMPT System Privileges:
SELECT * FROM DBA_SYS_PRIVS WHERE GRANTEE = 'LAST9_MONITOR';

PROMPT
PROMPT Object Privileges (showing first 10):
SELECT * FROM (
    SELECT TABLE_NAME, PRIVILEGE
    FROM DBA_TAB_PRIVS
    WHERE GRANTEE = 'LAST9_MONITOR'
    ORDER BY TABLE_NAME
) WHERE ROWNUM <= 10;

PROMPT
PROMPT =========================================
PROMPT Next Steps:
PROMPT =========================================
PROMPT 1. Verify permissions:
PROMPT    @verify-setup.sql
PROMPT
PROMPT 2. Test connection:
PROMPT    sqlplus last9_monitor/password@localhost:1521/ORCL
PROMPT
PROMPT 3. Configure OpenTelemetry Collector:
PROMPT    - Set username: last9_monitor
PROMPT    - Set password in environment variable
PROMPT    - Deploy config-oracle-agent.yaml
PROMPT
PROMPT 4. Start monitoring and verify metrics in Last9
PROMPT =========================================

PROMPT
PROMPT ⚠ SECURITY NOTES:
PROMPT   ✓ Read-only access granted (SELECT only)
PROMPT   ✓ No DML/DDL privileges (cannot modify data or objects)
PROMPT   ✓ No access to application tables
PROMPT   ✓ Only performance and metadata views accessible
PROMPT   ✗ Do NOT grant additional privileges without security review
PROMPT

EXIT;
