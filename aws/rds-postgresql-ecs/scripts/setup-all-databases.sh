#!/bin/bash

# =============================================================================
# PostgreSQL Multi-Database Monitoring Setup Script
# Runs setup-db-user.sql on all databases in an RDS PostgreSQL instance
# =============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_SCRIPT="${SCRIPT_DIR}/setup-db-user.sql"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 -h HOST -U USER [-p PORT] [-d DATABASES]

Setup OpenTelemetry monitoring user across all databases in RDS PostgreSQL.

Required arguments:
  -h HOST        PostgreSQL host (e.g., your-rds.amazonaws.com)
  -U USER        PostgreSQL admin user (usually 'postgres')

Optional arguments:
  -p PORT        PostgreSQL port (default: 5432)
  -d DATABASES   Comma-separated list of databases (default: auto-detect all)
  --help         Show this help message

Examples:
  # Setup on all databases (auto-detect)
  $0 -h my-rds.amazonaws.com -U postgres

  # Setup on specific databases only
  $0 -h my-rds.amazonaws.com -U postgres -d "app_db,analytics_db,staging_db"

  # With custom port
  $0 -h my-rds.amazonaws.com -U postgres -p 5433

Environment variables:
  PGPASSWORD     Set this to avoid password prompts
                 Example: export PGPASSWORD='your_password'

EOF
}

# Parse command line arguments
HOST=""
USER=""
PORT="5432"
DATABASES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h)
            HOST="$2"
            shift 2
            ;;
        -U)
            USER="$2"
            shift 2
            ;;
        -p)
            PORT="$2"
            shift 2
            ;;
        -d)
            DATABASES="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$HOST" ]] || [[ -z "$USER" ]]; then
    print_error "Missing required arguments"
    usage
    exit 1
fi

# Check if SQL script exists
if [[ ! -f "$SQL_SCRIPT" ]]; then
    print_error "SQL script not found: $SQL_SCRIPT"
    exit 1
fi

# Check if psql is installed
if ! command -v psql &> /dev/null; then
    print_error "psql command not found. Please install PostgreSQL client."
    exit 1
fi

print_info "==================================================================="
print_info "PostgreSQL Multi-Database Monitoring Setup"
print_info "==================================================================="
print_info "Host: $HOST"
print_info "Port: $PORT"
print_info "User: $USER"
print_info "SQL Script: $SQL_SCRIPT"
print_info "==================================================================="

# If DATABASES not specified, auto-detect all databases
if [[ -z "$DATABASES" ]]; then
    print_info "Auto-detecting databases..."

    # Get list of databases, excluding templates and system databases
    DATABASES=$(PAGER=cat psql -h "$HOST" -p "$PORT" -U "$USER" -d postgres -t -P pager=off -c \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('rdsadmin') ORDER BY datname;" \
        2>/dev/null | tr -d ' ' | grep -v '^$' | paste -sd ',' -)

    if [[ -z "$DATABASES" ]]; then
        print_error "Failed to detect databases. Please specify databases with -d option."
        exit 1
    fi

    print_success "Found databases: $DATABASES"
else
    print_info "Using specified databases: $DATABASES"
fi

# Convert comma-separated string to array
IFS=',' read -ra DB_ARRAY <<< "$DATABASES"

# Counters
TOTAL=${#DB_ARRAY[@]}
SUCCESS=0
FAILED=0
SKIPPED=0

print_info ""
print_info "Starting setup on $TOTAL database(s)..."
print_info ""

# Process each database
for db in "${DB_ARRAY[@]}"; do
    # Trim whitespace
    db=$(echo "$db" | xargs)

    print_info "-------------------------------------------------------------------"
    print_info "Processing database: $db"
    print_info "-------------------------------------------------------------------"

    # Run the setup script with pager completely disabled
    # Using multiple methods to ensure no pager interference:
    # 1. PAGER=cat - override system pager
    # 2. -P pager=off - PostgreSQL pager setting
    # 3. --pset=pager=off - Alternative pager setting
    if PAGER=cat psql -h "$HOST" -p "$PORT" -U "$USER" -d "$db" -P pager=off --pset=pager=off -f "$SQL_SCRIPT" 2>&1; then
        print_success "✓ Setup completed successfully for database: $db"
        ((SUCCESS++))
    else
        print_error "✗ Setup failed for database: $db"
        ((FAILED++))
    fi

    print_info ""
done

# Summary
print_info "==================================================================="
print_info "SETUP SUMMARY"
print_info "==================================================================="
print_info "Total databases: $TOTAL"
print_success "Successful: $SUCCESS"
if [[ $FAILED -gt 0 ]]; then
    print_error "Failed: $FAILED"
fi
if [[ $SKIPPED -gt 0 ]]; then
    print_warning "Skipped: $SKIPPED"
fi
print_info "==================================================================="

# Exit with appropriate code
if [[ $FAILED -gt 0 ]]; then
    print_error "Some databases failed to setup. Please review the errors above."
    exit 1
else
    print_success "All databases setup successfully!"
    print_info ""
    print_info "Next steps:"
    print_info "1. Verify the setup by connecting with otel_monitor user"
    print_info "2. Test queries: SELECT * FROM otel_monitor.pg_stat_statements() LIMIT 5;"
    print_info "3. Configure your OpenTelemetry collector to use the otel_monitor user"
    exit 0
fi
