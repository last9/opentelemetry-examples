#!/bin/bash
# Generate slow queries for MSSQL to populate Query Store.
# Uses WAITFOR DELAY to guarantee they exceed detection thresholds.

set -e

SQLCMD="/opt/mssql-tools18/bin/sqlcmd -S mssql -U sa -P MSSQLPassword123! -C -d testdb"

echo "Generating slow queries..."

echo "1. Table scan with WHERE on unindexed column..."
$SQLCMD -Q "WAITFOR DELAY '00:00:00.200'; SELECT COUNT(*) FROM users WHERE score > 50 AND score < 51 ORDER BY age DESC;"

echo "2. LIKE query on unindexed column..."
$SQLCMD -Q "WAITFOR DELAY '00:00:00.200'; SELECT COUNT(*) FROM users WHERE name LIKE '%user_999%' ORDER BY created_at;"

echo "3. GROUP BY on unindexed column..."
$SQLCMD -Q "WAITFOR DELAY '00:00:00.150'; SELECT status, AVG(score) as avg_score, COUNT(*) as cnt FROM users WHERE description LIKE '%slow%' GROUP BY status ORDER BY avg_score DESC;"

echo "4. Subquery with IN on unindexed column..."
$SQLCMD -Q "WAITFOR DELAY '00:00:00.200'; SELECT COUNT(*) FROM users WHERE age IN (SELECT DISTINCT age FROM users WHERE status = 'pending') AND score > 90;"

echo "Slow query generation complete."
