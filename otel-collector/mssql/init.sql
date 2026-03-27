-- Wait for SQL Server to be ready
WAITFOR DELAY '00:00:05';

-- Create monitoring user
CREATE LOGIN otel_monitor WITH PASSWORD = 'OtelPassword123!';
GO

USE master;
CREATE USER otel_monitor FOR LOGIN otel_monitor;
GRANT VIEW SERVER STATE TO otel_monitor;
GRANT VIEW ANY DEFINITION TO otel_monitor;
GO

-- Create test database
CREATE DATABASE testdb;
GO

USE testdb;
GO

-- Enable Query Store for slow query tracking
ALTER DATABASE testdb SET QUERY_STORE = ON;
ALTER DATABASE testdb SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 60,
    INTERVAL_LENGTH_MINUTES = 1,
    QUERY_CAPTURE_MODE = ALL
);
GO

-- Create test table
CREATE TABLE users (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(255),
    email NVARCHAR(255),
    age INT,
    score FLOAT,
    status NVARCHAR(20),
    description NVARCHAR(MAX),
    created_at DATETIME DEFAULT GETDATE()
);
GO

-- Insert 100K rows (no secondary indexes = table scans)
DECLARE @i INT = 0;
WHILE @i < 100000
BEGIN
    INSERT INTO users (name, email, age, score, status, description)
    VALUES (
        CONCAT('user_', @i),
        CONCAT('user_', @i, '@example.com'),
        18 + ABS(CHECKSUM(NEWID())) % 62,
        RAND() * 100,
        CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN 'active' WHEN 1 THEN 'inactive' ELSE 'pending' END,
        CONCAT('This is a longer text field for user ', @i, ' to increase row size and slow down table scans.')
    );
    SET @i = @i + 1;
END
GO

-- Create monitoring user access to testdb
USE testdb;
CREATE USER otel_monitor FOR LOGIN otel_monitor;
GRANT SELECT ON sys.query_store_query TO otel_monitor;
GRANT SELECT ON sys.query_store_query_text TO otel_monitor;
GRANT SELECT ON sys.query_store_plan TO otel_monitor;
GRANT SELECT ON sys.query_store_runtime_stats TO otel_monitor;
GO
