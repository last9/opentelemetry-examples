# Use the official Oracle XE image
FROM gvenzl/oracle-xe:21.3.0

# Set environment variables for Oracle
ENV ORACLE_PASSWORD=oracle

# Copy seed SQL script
COPY seed.sql /docker-entrypoint-initdb.d/
COPY grant_metrics_privs.sql /docker-entrypoint-initdb.d/

# Expose Oracle ports
EXPOSE 1521 5500

# The base image will automatically run scripts in /docker-entrypoint-initdb.d/
# No additional CMD or ENTRYPOINT needed 