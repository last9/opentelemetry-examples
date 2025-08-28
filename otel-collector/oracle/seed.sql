-- Connect as last9
ALTER SESSION SET CURRENT_SCHEMA=last9;

-- Create a sample table
CREATE TABLE customers (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(100),
    email VARCHAR2(100) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO customers (name, email) VALUES ('Alice Johnson', 'alice@example.com');
INSERT INTO customers (name, email) VALUES ('Bob Smith', 'bob@example.com');
INSERT INTO customers (name, email) VALUES ('Charlie Davis', 'charlie@example.com');
COMMIT; 