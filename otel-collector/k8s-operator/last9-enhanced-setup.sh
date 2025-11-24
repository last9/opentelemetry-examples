#!/bin/bash
#
# Last9 Enhanced OpenTelemetry Setup
# Simple wrapper that resolves conflicts before running the main setup
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFLICT_RESOLVER="$SCRIPT_DIR/last9-conflict-resolver.sh"
SETUP_SCRIPT_URL="https://raw.githubusercontent.com/last9/opentelemetry-examples/main/otel-collector/otel-operator/last9-otel-setup.sh"
TEMP_DIR=""

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Cleanup function
cleanup() {
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up temporary files"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Download the main setup script
download_setup_script() {
    local script_path="$1"

    log_info "Downloading Last9 setup script..."

    if ! curl -fsSL "$SETUP_SCRIPT_URL" -o "$script_path"; then
        log_error "Failed to download setup script"
        return 1
    fi

    chmod +x "$script_path"
    log_success "Setup script downloaded"
    return 0
}

# Run conflict resolution
run_conflict_resolution() {
    local cluster_name="$1"
    local output_dir="$2"

    log_info "🔍 Running conflict detection and resolution..."

    if [[ ! -f "$CONFLICT_RESOLVER" ]]; then
        log_error "Conflict resolver not found: $CONFLICT_RESOLVER"
        return 1
    fi

    local resolver_args=""

    if [[ -n "$cluster_name" ]]; then
        resolver_args="$resolver_args --cluster-name $cluster_name"
    fi

    resolver_args="$resolver_args --output-dir $output_dir"

    if "$CONFLICT_RESOLVER" $resolver_args; then
        log_success "✅ All conflicts resolved successfully"
        log_info "✅ Smart CRD strategy: Will use --skip-crds if existing operators detected"
        return 0
    else
        log_error "❌ Conflict resolution failed"
        return 1
    fi
}

# Enhance the main setup script arguments
enhance_setup_args() {
    local original_args=("$@")
    local enhanced_args=()
    local values_dir="$TEMP_DIR"

    # Add our enhanced values files if they were generated
    local monitoring_values="$values_dir/last9-monitoring-values.yaml"
    local operator_values="$values_dir/last9-operator-values.yaml"

    # Copy original arguments
    enhanced_args=("${original_args[@]}")

    # Set environment variable to indicate enhanced mode
    export ENHANCED_MODE="true"
    export LAST9_MONITORING_VALUES="$monitoring_values"
    export LAST9_OPERATOR_VALUES="$operator_values"

    echo "${enhanced_args[@]}"
}

# Run the main setup script with enhancements
run_enhanced_setup() {
    local setup_script="$1"
    shift
    local setup_args=("$@")

    log_info "🚀 Running Last9 setup with conflict-free configuration..."

    # Enhance the arguments
    local enhanced_args
    enhanced_args=($(enhance_setup_args "${setup_args[@]}"))

    # Run the setup script
    if timeout 600 bash "$setup_script" "${enhanced_args[@]}"; then
        log_success "✅ Last9 setup completed successfully"
        return 0
    else
        log_error "❌ Setup failed"
        return 1
    fi
}

# Print setup summary
print_summary() {
    local cluster_name="$1"

    echo
    log_success "🎉 Last9 Enhanced Setup Completed!"
    echo
    echo "Summary:"
    echo "--------"
    echo "• Conflict resolution: ✅ Automatic (high ports 40000+)"
    echo "• CRD strategy: ✅ Smart detection (--skip-crds when needed)"
    echo "• Port conflicts: ✅ Eliminated"
    echo "• Cluster: $cluster_name"
    echo
    echo "Port Allocation:"
    echo "• Node Exporter: 40001"
    echo "• Prometheus: 40002"
    echo "• Kube State Metrics: 40003"
    echo "• OTEL Collector HTTP: 40004"
    echo "• OTEL Collector gRPC: 40005"
    echo
    echo "Next steps:"
    echo "-----------"
    echo "1. Verify pods are running:"
    echo "   kubectl get pods -n last9"
    echo
    echo "2. Add instrumentation to your apps:"
    echo "   metadata:"
    echo "     annotations:"
    echo "       instrumentation.opentelemetry.io/inject-java: \"last9/l9-instrumentation\""
    echo
    echo "3. Check Last9 dashboard for incoming data"
    echo
}

# Print usage information
usage() {
    cat << EOF
Last9 Enhanced OpenTelemetry Setup

Automatically resolves installation conflicts and runs the Last9 setup using:
• High ports (40000+) to avoid port conflicts
• Smart CRD strategy (--skip-crds when existing operators detected)

Usage: $0 [OPTIONS] -- [SETUP_ARGS]

OPTIONS:
    --cluster-name NAME       Set cluster name (default: auto-detected)
    --help                    Show this help message

SETUP_ARGS:
    All arguments after '--' are passed to the Last9 setup script

EXAMPLES:
    # Basic setup with automatic conflict resolution
    $0 -- endpoint="https://..." token="..."

    # Full observability with monitoring
    $0 --cluster-name production -- \\
      endpoint="https://..." token="..." \\
      monitoring-endpoint="https://..." username="..." password="..."

    # Monitoring only (no traces)
    $0 -- monitoring-only \\
      monitoring-endpoint="https://..." username="..." password="..."

CONFLICT RESOLUTION (Automatic):
    • Detects existing OpenTelemetry operators
    • Uses --skip-crds if existing CRDs found (safe, no ownership conflicts)
    • Uses high ports (40000+) to eliminate port conflicts
    • Compatible with Dynatrace, New Relic, and other existing operators

EOF
}

# Main execution
main() {
    local cluster_name=""
    local setup_args=()
    local parsing_setup_args=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        if [[ "$parsing_setup_args" == "true" ]]; then
            setup_args+=("$1")
            shift
            continue
        fi

        case $1 in
            --cluster-name)
                if [[ -n "${2:-}" ]]; then
                    cluster_name="$2"
                    shift 2
                else
                    log_error "Cluster name cannot be empty"
                    exit 1
                fi
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --)
                parsing_setup_args=true
                shift
                ;;
            *)
                log_error "Unknown option: $1. Use '--' to separate options from setup arguments."
                usage
                exit 1
                ;;
        esac
    done

    # Validate setup arguments
    if [[ ${#setup_args[@]} -eq 0 ]]; then
        log_error "No setup arguments provided"
        log_error "Use: $0 [OPTIONS] -- endpoint=\"...\" token=\"...\""
        usage
        exit 1
    fi

    # Auto-detect cluster name if not provided
    if [[ -z "$cluster_name" ]]; then
        cluster_name=$(kubectl config current-context 2>/dev/null | sed 's/.*\///g' || echo "last9-cluster")
        log_info "Auto-detected cluster name: $cluster_name"
    fi

    # Create temp directory
    TEMP_DIR=$(mktemp -d -t "last9-enhanced-setup-XXXXXX")
    log_info "Using temporary directory: $TEMP_DIR"

    # Main execution flow
    log_info "🎯 Starting Last9 Enhanced OpenTelemetry Setup..."
    echo

    # Step 1: Run conflict resolution
    if ! run_conflict_resolution "$cluster_name" "$TEMP_DIR"; then
        log_error "Cannot proceed due to unresolved conflicts"
        exit 1
    fi

    # Step 2: Download setup script
    local setup_script="$TEMP_DIR/last9-otel-setup.sh"
    if ! download_setup_script "$setup_script"; then
        log_error "Failed to download setup script"
        exit 1
    fi

    # Step 3: Run enhanced setup
    if ! run_enhanced_setup "$setup_script" "${setup_args[@]}"; then
        log_error "Setup failed"
        exit 1
    fi

    # Step 4: Print summary
    print_summary "$cluster_name"

    log_success "🎉 Enhanced setup completed successfully!"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi