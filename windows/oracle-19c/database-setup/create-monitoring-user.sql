-- Create Oracle Monitoring User for OpenTelemetry
-- Purpose: Create a dedicated user with minimal privileges for database monitoring
-- Security: Read-only access to performance views only, no access to application data
--
-- Usage:
--   sqlplus / as sysdba @create-monitoring-user.sql
--
-- Version: Oracle 19c
-- Last Updated: 2025-11-29

SET ECHO ON
SET SERVEROUTPUT ON

PROMPT =========================================
PROMPT Creating OpenTelemetry Monitoring User
PROMPT =========================================
PROMPT

-- Check if user already exists
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM dba_users
    WHERE username = 'LAST9_MONITOR';

    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('⚠ User LAST9_MONITOR already exists!');
        DBMS_OUTPUT.PUT_LINE('  To recreate, run: DROP USER last9_monitor CASCADE;');
        RAISE_APPLICATION_ERROR(-20001, 'User already exists');
    END IF;
END;
/

-- Create monitoring user
-- IMPORTANT: Change this password before deploying to production!
PROMPT Creating user LAST9_MONITOR...
CREATE USER last9_monitor IDENTIFIED BY "CHANGE_THIS_PASSWORD_IN_PRODUCTION"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    QUOTA 0 ON USERS  -- No quota needed (read-only)
    ACCOUNT UNLOCK
    PASSWORD EXPIRE;  -- Force password change on first login

-- Add comment for documentation
COMMENT ON USER last9_monitor IS 'OpenTelemetry monitoring user - read-only access to V$ views for Last9 integration';

-- Grant basic connection privileges
PROMPT Granting basic connection privileges...
GRANT CREATE SESSION TO last9_monitor;
GRANT CONNECT TO last9_monitor;

-- Grant catalog role for read-only access to data dictionary
PROMPT Granting SELECT_CATALOG_ROLE...
GRANT SELECT_CATALOG_ROLE TO last9_monitor;

-- Verify user creation
PROMPT
PROMPT ✓ User LAST9_MONITOR created successfully!
PROMPT
PROMPT User Details:
SELECT
    username,
    account_status,
    default_tablespace,
    temporary_tablespace,
    created
FROM dba_users
WHERE username = 'LAST9_MONITOR';

PROMPT
PROMPT =========================================
PROMPT Next Steps:
PROMPT =========================================
PROMPT 1. Change the password:
PROMPT    ALTER USER last9_monitor IDENTIFIED BY "YourSecurePassword";
PROMPT
PROMPT 2. Grant specific permissions:
PROMPT    @grant-minimal-permissions.sql
PROMPT
PROMPT 3. Verify setup:
PROMPT    @verify-setup.sql
PROMPT
PROMPT 4. Store password securely (do NOT hardcode in configs):
PROMPT    - Windows: Use environment variables or Windows Credential Manager
PROMPT    - Linux: Use environment variables or secrets management
PROMPT    - Never commit passwords to version control!
PROMPT =========================================

-- Security reminder
PROMPT
PROMPT ⚠ SECURITY REMINDER:
PROMPT   - This user has read-only access to performance views
PROMPT   - No access to application data or tables
PROMPT   - Cannot modify database objects
PROMPT   - Use a strong password (min 12 characters, mixed case, numbers, symbols)
PROMPT   - Rotate password every 90 days
PROMPT   - Monitor failed login attempts
PROMPT

EXIT;
