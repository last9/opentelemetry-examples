#!/bin/bash
#
# Last9 OpenTelemetry Conflict Resolver
# Focused on CRD ownership and existing operator detection
# Uses high ports (40000+) to avoid port conflicts
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Last9 Configuration - High ports to avoid conflicts
readonly LAST9_NODE_EXPORTER_PORT=40001
readonly LAST9_PROMETHEUS_PORT=40002
readonly LAST9_KUBE_STATE_METRICS_PORT=40003
readonly LAST9_COLLECTOR_HTTP_PORT=40004
readonly LAST9_COLLECTOR_GRPC_PORT=40005

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

# Check if we can access Kubernetes
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check kubectl configuration."
        return 1
    fi
    log_success "Kubernetes cluster access verified"
    return 0
}

# Detect existing OpenTelemetry operator
detect_existing_opentelemetry_operator() {
    log_info "Checking for existing OpenTelemetry operator installations..."

    local operator_found=false
    local operator_namespace=""
    local operator_management=""
    local operator_version=""

    # Check for OpenTelemetry operator deployments
    local deployments
    deployments=$(kubectl get deployments --all-namespaces -l app.kubernetes.io/name=opentelemetry-operator -o json 2>/dev/null || echo '{"items":[]}')

    local deployment_count
    deployment_count=$(echo "$deployments" | jq '.items | length')

    if [[ "$deployment_count" -gt 0 ]]; then
        operator_found=true
        operator_namespace=$(echo "$deployments" | jq -r '.items[0].metadata.namespace')
        operator_management=$(echo "$deployments" | jq -r '.items[0].metadata.labels."app.kubernetes.io/managed-by" // "unknown"')
        operator_version=$(echo "$deployments" | jq -r '.items[0].spec.template.spec.containers[0].image // "unknown"' | sed 's/.*://')

        log_warn "Found existing OpenTelemetry operator:"
        log_warn "  Namespace: $operator_namespace"
        log_warn "  Managed by: $operator_management"
        log_warn "  Version: $operator_version"
    else
        log_info "No existing OpenTelemetry operator found"
    fi

    echo "$operator_found,$operator_namespace,$operator_management,$operator_version"
}

# Determine CRD installation strategy
determine_crd_strategy() {
    log_info "Determining CRD installation strategy..."

    local crds_to_check=(
        "opentelemetrycollectors.opentelemetry.io"
        "instrumentations.opentelemetry.io"
        "opampbridges.opentelemetry.io"
    )

    local existing_crds=0
    local crd_versions=()

    for crd in "${crds_to_check[@]}"; do
        if kubectl get crd "$crd" &> /dev/null; then
            ((existing_crds++))

            # Check CRD version
            local version
            version=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].name}' 2>/dev/null || echo "unknown")
            crd_versions+=("$crd:$version")

            local managed_by
            managed_by=$(kubectl get crd "$crd" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || echo "unknown")

            log_info "Found $crd (version: $version, managed-by: $managed_by)"
        fi
    done

    if [[ $existing_crds -eq 0 ]]; then
        log_info "No existing OpenTelemetry CRDs found"
        echo "install-crds"
        return 0
    fi

    if [[ $existing_crds -eq ${#crds_to_check[@]} ]]; then
        log_success "All required OpenTelemetry CRDs already exist"
        log_info "Recommendation: Use --skip-crds to avoid ownership conflicts"

        # Check if CRDs are recent enough
        local old_versions=0
        for version_info in "${crd_versions[@]}"; do
            if [[ "$version_info" == *":v1alpha1" ]]; then
                ((old_versions++))
            fi
        done

        if [[ $old_versions -gt 0 ]]; then
            log_warn "Detected older CRD versions (v1alpha1). Consider compatibility testing."
        fi

        echo "skip-crds"
        return 0
    else
        log_warn "Partial OpenTelemetry CRDs found ($existing_crds/${#crds_to_check[@]})"
        log_warn "This may indicate a broken previous installation"
        echo "install-crds-force"
        return 0
    fi
}

# Generate enhanced Helm values with high ports
generate_last9_values() {
    local values_file="$1"
    local cluster_name="${2:-last9-cluster}"

    log_info "Generating Last9 Helm values with conflict-free ports..."

    cat > "$values_file" << EOF
# Last9 Enhanced Kubernetes Monitoring Values
# Uses high ports (40000+) to avoid conflicts with existing infrastructure

# Prometheus configuration
prometheus:
  enabled: true
  agentMode: true
  service:
    port: $LAST9_PROMETHEUS_PORT
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

    # Cluster identification
    externalLabels:
      cluster: $cluster_name

    # Last9 remote write configuration
    remoteWrite:
      - url: "\${MONITORING_ENDPOINT}"
        remoteTimeout: 60s
        queueConfig:
          capacity: 10000
          maxSamplesPerSend: 3000
          batchSendDeadline: 20s
          minShards: 4
          maxShards: 200
          minBackoff: 100ms
          maxBackoff: 10s
        basicAuth:
          username:
            name: last9-remote-write-secret
            key: username
          password:
            name: last9-remote-write-secret
            key: password
        writeRelabelConfigs:
          - sourceLabels: [__name__]
            regex: "up|kube_.*|container_.*|node_.*"
            action: keep

# Node exporter with high port (no conflicts)
nodeExporter:
  enabled: true
  service:
    port: $LAST9_NODE_EXPORTER_PORT
    targetPort: $LAST9_NODE_EXPORTER_PORT
  # Avoid host port binding completely
  hostNetwork: false
  hostPID: true

# Kube-state-metrics with high port
kubeStateMetrics:
  enabled: true
  service:
    port: $LAST9_KUBE_STATE_METRICS_PORT

# Kubelet monitoring
kubelet:
  enabled: true
  serviceMonitor:
    resource: true
    cAdvisor: true

# Disable potentially conflicting components
alertmanager:
  enabled: false

grafana:
  enabled: false

# Prometheus operator configuration
prometheusOperator:
  admissionWebhooks:
    enabled: false
  tls:
    enabled: false

# Disable unnecessary components that might cause conflicts
kubeApiServer:
  enabled: true

kubeControllerManager:
  enabled: false

kubeDns:
  enabled: false

kubeEtcd:
  enabled: false

kubeProxy:
  enabled: false

kubeScheduler:
  enabled: false
EOF

    log_success "Generated enhanced Helm values: $values_file"
    log_info "Port allocation:"
    log_info "  • Node Exporter: $LAST9_NODE_EXPORTER_PORT"
    log_info "  • Prometheus: $LAST9_PROMETHEUS_PORT"
    log_info "  • Kube State Metrics: $LAST9_KUBE_STATE_METRICS_PORT"
    log_info "  • OpenTelemetry Collector HTTP: $LAST9_COLLECTOR_HTTP_PORT"
    log_info "  • OpenTelemetry Collector gRPC: $LAST9_COLLECTOR_GRPC_PORT"
}

# Generate OpenTelemetry operator values with high ports
generate_otel_operator_values() {
    local values_file="$1"
    local crd_strategy="${2:-install-crds}"

    local crd_create="true"
    if [[ "$crd_strategy" == "skip-crds" ]]; then
        crd_create="false"
    fi

    cat > "$values_file" << EOF
# Last9 OpenTelemetry Operator Values
# Uses high ports to avoid conflicts
# CRD Strategy: $crd_strategy

manager:
  image:
    repository: ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-operator

  ports:
    webhookPort: $LAST9_COLLECTOR_HTTP_PORT
    metricsPort: $(($LAST9_COLLECTOR_HTTP_PORT + 1))

# Collector configuration with high ports
collector:
  ports:
    otlp-http:
      enabled: true
      containerPort: $LAST9_COLLECTOR_HTTP_PORT
      servicePort: $LAST9_COLLECTOR_HTTP_PORT
    otlp-grpc:
      enabled: true
      containerPort: $LAST9_COLLECTOR_GRPC_PORT
      servicePort: $LAST9_COLLECTOR_GRPC_PORT
    # Disable potentially conflicting ports
    jaeger-compact:
      enabled: false
    jaeger-thrift:
      enabled: false
    jaeger-grpc:
      enabled: false
    zipkin:
      enabled: false

# Webhook configuration
admissionWebhooks:
  autoGenerateCert:
    enabled: true
  certManager:
    enabled: false

# CRD management based on existing installation
crds:
  create: $crd_create
EOF

    log_success "Generated OpenTelemetry operator values: $values_file"
    log_info "CRD strategy: $crd_strategy (create: $crd_create)"
}

# Main conflict resolution function
resolve_conflicts() {
    local force_crd_takeover="${1:-false}"
    local cluster_name="${2:-last9-cluster}"
    local output_dir="${3:-/tmp}"

    log_info "Starting Last9 OpenTelemetry conflict resolution..."
    log_info "Using high-port strategy (40000+) to eliminate port conflicts"

    # Step 1: Check basic prerequisites
    check_kubectl || return 1

    # Step 2: Detect existing OpenTelemetry operator
    local operator_info
    operator_info=$(detect_existing_opentelemetry_operator)
    IFS=',' read -r operator_exists namespace management version <<< "$operator_info"

    if [[ "$operator_exists" == "true" ]]; then
        log_info "Existing operator found in $namespace (managed by $management, version: $version)"

        if [[ "$management" == "Helm" ]]; then
            log_success "Existing operator is Helm-managed - compatible with Last9 approach"
        else
            log_warn "Existing operator is $management-managed"
        fi
    else
        log_info "No existing OpenTelemetry operator found - clean installation possible"
    fi

    # Step 3: Determine CRD installation strategy
    local crd_strategy
    crd_strategy=$(determine_crd_strategy)

    case "$crd_strategy" in
        "skip-crds")
            log_success "Will skip CRD installation (existing CRDs found) - eliminates ownership conflicts"
            ;;
        "install-crds")
            log_info "Will install CRDs normally (no existing CRDs found)"
            ;;
        "install-crds-force")
            log_warn "Partial CRDs detected - will install/update all CRDs"
            ;;
    esac

    # Step 4: Generate enhanced configuration files
    local monitoring_values="$output_dir/last9-monitoring-values.yaml"
    local operator_values="$output_dir/last9-operator-values.yaml"
    local install_script="$output_dir/last9-install-commands.sh"

    generate_last9_values "$monitoring_values" "$cluster_name"
    generate_otel_operator_values "$operator_values" "$crd_strategy"

    # Generate install script with appropriate flags
    cat > "$install_script" << EOF
#!/bin/bash
# Last9 Installation Commands
# Generated by Last9 conflict resolver

set -euo pipefail

echo "Installing Last9 monitoring stack..."
helm upgrade --install last9-k8s-monitoring prometheus-community/kube-prometheus-stack \\
  -n last9 -f "$monitoring_values" --create-namespace

echo "Installing OpenTelemetry operator..."
EOF

    if [[ "$crd_strategy" == "skip-crds" ]]; then
        cat >> "$install_script" << EOF
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \\
  -n last9 -f "$operator_values" --create-namespace --skip-crds
EOF
    else
        cat >> "$install_script" << EOF
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \\
  -n last9 -f "$operator_values" --create-namespace
EOF
    fi

    cat >> "$install_script" << EOF

echo "✅ Last9 installation completed!"
echo "Verify with: kubectl get pods -n last9"
EOF

    chmod +x "$install_script"

    log_success "Conflict resolution completed successfully!"
    log_info ""
    log_info "Generated files:"
    log_info "• Monitoring values: $monitoring_values"
    log_info "• Operator values: $operator_values"
    log_info "• Install script: $install_script"
    log_info ""
    log_info "CRD Strategy: $crd_strategy"
    if [[ "$crd_strategy" == "skip-crds" ]]; then
        log_info "• Will use --skip-crds flag (safe with existing operators)"
    fi
    log_info ""
    log_info "To install, run: $install_script"

    return 0
}

# Print usage information
usage() {
    cat << EOF
Last9 OpenTelemetry Conflict Resolver

Automatically resolves common conflicts during Last9 OpenTelemetry setup by:
• Using high ports (40000+) to avoid port conflicts
• Detecting existing OpenTelemetry operators
• Smart CRD strategy (--skip-crds when operators exist)

Usage: $0 [OPTIONS]

OPTIONS:
    --cluster-name NAME       Set cluster name (default: last9-cluster)
    --output-dir DIR          Output directory for generated values (default: /tmp)
    --help                    Show this help message

CRD STRATEGY (Automatic):
    • If existing OpenTelemetry CRDs found: Uses --skip-crds (safe, no conflicts)
    • If no existing CRDs found: Installs CRDs normally
    • If partial CRDs found: Forces CRD installation/update

EXAMPLES:
    $0                                    # Detect conflicts and generate config
    $0 --cluster-name production         # Set cluster name
    $0 --output-dir ./configs            # Custom output directory

EOF
}

# Main execution
main() {
    local cluster_name="last9-cluster"
    local output_dir="/tmp"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
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
            --output-dir)
                if [[ -n "${2:-}" ]]; then
                    output_dir="$2"
                    shift 2
                else
                    log_error "Output directory cannot be empty"
                    exit 1
                fi
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Ensure output directory exists
    mkdir -p "$output_dir"

    # Run conflict resolution (force_crd_takeover is no longer needed)
    if resolve_conflicts "false" "$cluster_name" "$output_dir"; then
        log_success "Last9 conflict resolution completed successfully!"
        exit 0
    else
        log_error "Conflict resolution failed. Please review the issues above."
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi