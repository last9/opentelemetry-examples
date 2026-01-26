-- Verify Oracle Monitoring User Setup
-- Purpose: Validate that last9_monitor user has correct permissions
-- Usage:
--   sqlplus / as sysdba @verify-setup.sql
--
-- Version: Oracle 19c
-- Last Updated: 2025-11-29

SET ECHO ON
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 1000

PROMPT =========================================
PROMPT Verifying Oracle Monitoring Setup
PROMPT =========================================
PROMPT

-- Check 1: User exists
PROMPT [CHECK 1] Verifying user exists...
DECLARE
    v_count NUMBER;
    v_status VARCHAR2(32);
BEGIN
    SELECT COUNT(*), MAX(account_status)
    INTO v_count, v_status
    FROM dba_users
    WHERE username = 'LAST9_MONITOR';

    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('✗ FAIL: User LAST9_MONITOR does not exist');
        DBMS_OUTPUT.PUT_LINE('  Action: Run create-monitoring-user.sql');
        RAISE_APPLICATION_ERROR(-20001, 'User does not exist');
    ELSIF v_status != 'OPEN' THEN
        DBMS_OUTPUT.PUT_LINE('⚠ WARNING: User account status is: ' || v_status);
        DBMS_OUTPUT.PUT_LINE('  Expected: OPEN');
        DBMS_OUTPUT.PUT_LINE('  Action: ALTER USER last9_monitor ACCOUNT UNLOCK;');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✓ PASS: User LAST9_MONITOR exists and is unlocked');
    END IF;
END;
/

-- Check 2: Basic privileges
PROMPT
PROMPT [CHECK 2] Verifying basic privileges...
DECLARE
    v_create_session NUMBER;
    v_connect NUMBER;
    v_select_catalog NUMBER;
BEGIN
    -- Check CREATE SESSION
    SELECT COUNT(*) INTO v_create_session
    FROM dba_sys_privs
    WHERE grantee = 'LAST9_MONITOR'
    AND privilege = 'CREATE SESSION';

    -- Check CONNECT role
    SELECT COUNT(*) INTO v_connect
    FROM dba_role_privs
    WHERE grantee = 'LAST9_MONITOR'
    AND granted_role = 'CONNECT';

    -- Check SELECT_CATALOG_ROLE
    SELECT COUNT(*) INTO v_select_catalog
    FROM dba_role_privs
    WHERE grantee = 'LAST9_MONITOR'
    AND granted_role = 'SELECT_CATALOG_ROLE';

    IF v_create_session > 0 THEN
        DBMS_OUTPUT.PUT_LINE('✓ PASS: CREATE SESSION privilege granted');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✗ FAIL: CREATE SESSION privilege missing');
    END IF;

    IF v_connect > 0 THEN
        DBMS_OUTPUT.PUT_LINE('✓ PASS: CONNECT role granted');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✗ FAIL: CONNECT role missing');
    END IF;

    IF v_select_catalog > 0 THEN
        DBMS_OUTPUT.PUT_LINE('✓ PASS: SELECT_CATALOG_ROLE granted');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✗ FAIL: SELECT_CATALOG_ROLE missing');
    END IF;
END;
/

-- Check 3: Required V$ view permissions
PROMPT
PROMPT [CHECK 3] Verifying V$ view permissions...
DECLARE
    TYPE view_list IS TABLE OF VARCHAR2(50);
    v_views view_list := view_list(
        'V_$SESSION', 'V_$PROCESS', 'V_$SYSSTAT', 'V_$SYSTEM_EVENT',
        'V_$RESOURCE_LIMIT', 'V_$INSTANCE', 'V_$DATABASE', 'V_$SQL',
        'V_$SQLAREA', 'V_$SQLSTATS', 'DBA_TABLESPACES', 'DBA_DATA_FILES'
    );
    v_count NUMBER;
    v_total_missing NUMBER := 0;
BEGIN
    FOR i IN 1..v_views.COUNT LOOP
        SELECT COUNT(*) INTO v_count
        FROM dba_tab_privs
        WHERE grantee = 'LAST9_MONITOR'
        AND table_name = v_views(i)
        AND privilege = 'SELECT';

        IF v_count > 0 THEN
            DBMS_OUTPUT.PUT_LINE('  ✓ ' || RPAD(v_views(i), 30) || ' - Accessible');
        ELSE
            DBMS_OUTPUT.PUT_LINE('  ✗ ' || RPAD(v_views(i), 30) || ' - Missing SELECT permission');
            v_total_missing := v_total_missing + 1;
        END IF;
    END LOOP;

    IF v_total_missing = 0 THEN
        DBMS_OUTPUT.PUT_LINE('✓ PASS: All critical views are accessible');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✗ FAIL: ' || v_total_missing || ' views missing SELECT permission');
        DBMS_OUTPUT.PUT_LINE('  Action: Run grant-minimal-permissions.sql');
    END IF;
END;
/

-- Check 4: Test queries
PROMPT
PROMPT [CHECK 4] Testing actual queries...
PROMPT Testing as LAST9_MONITOR user...

-- Create test connection
CONNECT last9_monitor/CHANGE_THIS_PASSWORD_IN_PRODUCTION@&1
WHENEVER SQLERROR CONTINUE

-- Test V$SYSSTAT
PROMPT
PROMPT Testing V$SYSSTAT query...
SELECT COUNT(*) AS metric_count FROM V$SYSSTAT WHERE ROWNUM <= 10;

-- Test V$SESSION
PROMPT
PROMPT Testing V$SESSION query...
SELECT COUNT(*) AS session_count FROM V$SESSION;

-- Test DBA_TABLESPACES
PROMPT
PROMPT Testing DBA_TABLESPACES query...
SELECT
    tablespace_name,
    status,
    contents
FROM dba_tablespaces
WHERE ROWNUM <= 5;

-- Test V$INSTANCE
PROMPT
PROMPT Testing V$INSTANCE query...
SELECT
    instance_name,
    host_name,
    version,
    status
FROM v$instance;

-- Reconnect as SYSDBA for final summary
CONNECT / AS SYSDBA

PROMPT
PROMPT =========================================
PROMPT Verification Summary
PROMPT =========================================

-- Total permissions
SELECT
    'Total Privileges' AS metric,
    COUNT(*) AS value
FROM (
    SELECT GRANTEE FROM DBA_TAB_PRIVS WHERE GRANTEE = 'LAST9_MONITOR'
    UNION ALL
    SELECT GRANTEE FROM DBA_SYS_PRIVS WHERE GRANTEE = 'LAST9_MONITOR'
    UNION ALL
    SELECT GRANTEE FROM DBA_ROLE_PRIVS WHERE GRANTEE = 'LAST9_MONITOR'
)
WHERE GRANTEE = 'LAST9_MONITOR';

-- Count by type
PROMPT
PROMPT Privileges by Type:
SELECT 'System Privileges' AS privilege_type, COUNT(*) AS count
FROM dba_sys_privs WHERE grantee = 'LAST9_MONITOR'
UNION ALL
SELECT 'Roles', COUNT(*)
FROM dba_role_privs WHERE grantee = 'LAST9_MONITOR'
UNION ALL
SELECT 'Object Privileges', COUNT(*)
FROM dba_tab_privs WHERE grantee = 'LAST9_MONITOR';

-- Critical V$ views
PROMPT
PROMPT Critical V$ View Access:
SELECT
    table_name,
    privilege
FROM dba_tab_privs
WHERE grantee = 'LAST9_MONITOR'
AND table_name LIKE 'V_%'
AND table_name IN ('V_$SESSION', 'V_$SYSSTAT', 'V_$SYSTEM_EVENT', 'V_$SQL')
ORDER BY table_name;

PROMPT
PROMPT =========================================
PROMPT Final Status
PROMPT =========================================
PROMPT
PROMPT If all checks passed (✓ PASS):
PROMPT   1. Test connection from application server:
PROMPT      sqlplus last9_monitor/password@oracle-host:1521/ORCL
PROMPT
PROMPT   2. Configure OpenTelemetry Collector:
PROMPT      receivers:
PROMPT        oracledb:
PROMPT          endpoint: oracle-host:1521
PROMPT          service: ORCL
PROMPT          username: last9_monitor
PROMPT          password: ${ORACLE_MONITOR_PASSWORD}
PROMPT
PROMPT   3. Start collector and verify metrics:
PROMPT      curl http://localhost:8888/metrics | grep oracledb
PROMPT
PROMPT   4. Check Last9 for incoming metrics (2-3 min delay)
PROMPT
PROMPT If any checks failed (✗ FAIL):
PROMPT   - Review error messages above
PROMPT   - Re-run grant-minimal-permissions.sql
PROMPT   - Ensure Oracle version is 19c or later
PROMPT =========================================

EXIT;
