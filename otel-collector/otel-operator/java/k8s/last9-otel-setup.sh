#!/bin/bash

# OpenTelemetry Setup Automation Script
# Usage: 
#    Show all options
#    ./setup-otel.sh

#    Install everything
#    ./setup-otel.sh token="token" cluster="cluster" username="user" password="pass"

#    Install OpenTelemetry Operator and Collector - Used only for traces
#    ./setup-otel.sh operator-only token="token"

#    Install only Collector for logs 
#    ./setup-otel.sh logs-only token="token"

#    Install only Cluster Monitoring (Prometheus stack)
#    ./setup-otel.sh monitoring-only cluster="cluster" username="user" password="pass"

#    Remove All components
#    ./setup-otel.sh uninstall-all


set -e  # Exit on any error

# Configuration defaults
NAMESPACE="last9"
OPERATOR_VERSION="0.92.1"
COLLECTOR_VERSION="0.126.0"
MONITORING_VERSION="75.15.1"

WORK_DIR="otel-setup-$(date +%s)"
DEFAULT_REPO="https://github.com/last9/opentelemetry-examples.git#otel-k8s-monitoring"

# Initialize variables
AUTH_TOKEN=""
REPO_URL="$DEFAULT_REPO"
UNINSTALL_MODE=false
FUNCTION_TO_EXECUTE=""
VALUES_FILE=""
SETUP_MONITORING=true
CLUSTER_NAME=""
LAST9_USERNAME=""
LAST9_PASSWORD=""
OPERATOR_ONLY=false
LOGS_ONLY=false
MONITORING_ONLY=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse named arguments
parse_arguments() {
    for arg in "$@"; do
        case $arg in
            monitoring-only)
                MONITORING_ONLY=true
                shift
                ;;
            logs-only)
                LOGS_ONLY=true
                shift
                ;;
            operator-only)
                OPERATOR_ONLY=true
                shift
                ;;
            uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            uninstall-all)
                UNINSTALL_MODE=true
                FUNCTION_TO_EXECUTE="uninstall_all"
                shift
                ;;
            token=*)
                AUTH_TOKEN="${arg#*=}"
                shift
                ;;
            repo=*)
                REPO_URL="${arg#*=}"
                shift
                ;;
            function=*)
                FUNCTION_TO_EXECUTE="${arg#*=}"
                shift
                ;;
            values=*)
                VALUES_FILE="${arg#*=}"
                shift
                ;;
            monitoring=*)
                if [ "${arg#*=}" = "false" ]; then
                    SETUP_MONITORING=false
                else
                    SETUP_MONITORING=true
                    CLUSTER_NAME="${arg#*=}"
                fi
                shift
                ;;
            cluster=*)
                CLUSTER_NAME="${arg#*=}"
                shift
                ;;
            username=*)
                LAST9_USERNAME="${arg#*=}"
                shift
                ;;
            password=*)
                LAST9_PASSWORD="${arg#*=}"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_warn "Unknown argument: $arg"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show examples function (for no-args case)
show_examples() {
    echo "OpenTelemetry Setup Automation Script"
    echo ""
    echo "Quick Examples:"
    echo "  $0 token=\"your-token-here\" username=\"my-user\" password=\"my-pass\"  # For All Sources(Logs, Traces and Metrics) use this option"
    echo "  $0 operator-only token=\"your-token-here\"  # For Traces - Install OpenTelemetry Operator and Collector"
    echo "  $0 logs-only token=\"your-token-here\"  # For Logs - Install only Collector for logs (no operator)"
    echo "  $0 monitoring-only username=\"user\" password=\"pass\"  # For Metrics - Install only monitoring"
    echo "  $0 uninstall-all  # Use to Uninstall any components installed previously"
    echo ""
}

# Show help function
show_help() {
    echo "OpenTelemetry Setup Automation Script"
    echo ""
    echo "Usage:"
    echo "  $0 token=\"your-token-here\" username=\"my-user\" password=\"my-pass\"  # For All Sources(Logs, Traces and Metrics) use this option"
    echo "  $0 operator-only token=\"your-token-here\"  # For Traces - Install OpenTelemetry Operator and Collector"
    echo "  $0 logs-only token=\"your-token-here\"  # For Logs - Install only Collector for logs (no operator)"
    echo "  $0 monitoring-only username=\"user\" password=\"pass\"  # For Metrics - Install only monitoring"
    echo "  $0 uninstall-all  # Use to Uninstall any components installed previously"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Skip token check for uninstall mode, logs-only mode, and monitoring-only mode
    # Note: operator-only mode will check for token later in its specific section
    if [ "$UNINSTALL_MODE" = false ] && [ "$LOGS_ONLY" = false ] && [ "$MONITORING_ONLY" = false ] && [ "$OPERATOR_ONLY" = false ] && [ -z "$AUTH_TOKEN" ]; then
        log_error "Auth token is required for installation."
        echo ""
        show_help
        exit 1
    fi
    
    command -v helm >/dev/null 2>&1 || { log_error "helm is required but not installed. Aborting."; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed. Aborting."; exit 1; }
    
    if [ "$UNINSTALL_MODE" = false ]; then
        command -v git >/dev/null 2>&1 || { log_error "git is required but not installed. Aborting."; exit 1; }
    fi
    
    # Check kubectl connectivity
    kubectl cluster-info >/dev/null 2>&1 || { log_error "kubectl cannot connect to cluster. Aborting."; exit 1; }
    
    log_info "Prerequisites check passed!"
    
    if [ "$UNINSTALL_MODE" = false ]; then
        if [ "$OPERATOR_ONLY" = true ]; then
            log_info "Running in operator-only mode"
        elif [ "$LOGS_ONLY" = true ]; then
            log_info "Running in logs-only mode"
            log_info "Using auth token: ${AUTH_TOKEN:0:10}..."  # Show only first 10 chars for security
            log_info "Using repository: $REPO_URL"
        elif [ "$MONITORING_ONLY" = true ]; then
            log_info "Running in monitoring-only mode"
        else
            log_info "Using auth token: ${AUTH_TOKEN:0:10}..."  # Show only first 10 chars for security
            log_info "Using repository: $REPO_URL"
        fi
    else
        log_info "Running in uninstall mode"
    fi
}

# Function to setup repository and files
setup_repository() {
    log_info "Setting up repository and configuration files..."
    
    # Create temporary work directory
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Clone repository
    log_info "Cloning repository: $REPO_URL"
    #git clone "$REPO_URL" .

     
    # Check if URL contains branch specification (format: url#branch)
    if [[ "$REPO_URL" == *"#"* ]]; then
       # Split URL and branch
       ACTUAL_URL="${REPO_URL%#*}"
       BRANCH="${REPO_URL#*#}"
       log_info "Cloning branch '$BRANCH' from: $ACTUAL_URL"
       git clone -b "$BRANCH" "$ACTUAL_URL" .
    else
      # Clone default branch
      git clone "$REPO_URL" .
    fi

    
    # Navigate to the correct directory
    if [ -d "otel-collector/otel-operator/java/k8s" ]; then
        cd otel-collector/otel-operator/java/k8s
    else
        log_error "Expected directory structure not found. Please check the repository."
        exit 1
    fi
    
    # Verify required files exist
    required_files=("last9-otel-collector-values.yaml" "collector-svc.yaml" "instrumentation.yaml")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file '$file' not found in repository."
            exit 1
        fi
    done
    
    log_info "Repository setup completed!"
    
    # Update auth token in the values file
    update_auth_token
}

# Function to update auth token in values file
update_auth_token() {
    log_info "Updating auth token placeholder in last9-otel-collector-values.yaml..."
    
    # Check if the values file exists
    if [ ! -f "last9-otel-collector-values.yaml" ]; then
        log_error "last9-otel-collector-values.yaml not found!"
        exit 1
    fi
    
    # Create backup of original file
    cp last9-otel-collector-values.yaml last9-otel-collector-values.yaml.backup
    log_info "Created backup: last9-otel-collector-values.yaml.backup"
    
    # Replace placeholder with actual token (expects complete authorization header)
    log_info "Using auth token: ${AUTH_TOKEN:0:20}..."
    
    # Handle multiple placeholder formats
    if grep -q '{{AUTH_TOKEN}}' last9-otel-collector-values.yaml; then
        log_info "Found {{AUTH_TOKEN}} placeholder"
        sed -i.tmp "s/{{AUTH_TOKEN}}/$AUTH_TOKEN/g" last9-otel-collector-values.yaml
    elif grep -q '${AUTH_TOKEN}' last9-otel-collector-values.yaml; then
        log_info "Found \${AUTH_TOKEN} placeholder"
        sed -i.tmp "s/\${AUTH_TOKEN}/$AUTH_TOKEN/g" last9-otel-collector-values.yaml
    elif grep -q '{{ \.Values\.authToken }}' last9-otel-collector-values.yaml; then
        log_info "Found Helm template placeholder"
        sed -i.tmp "s/{{ \.Values\.authToken }}/$AUTH_TOKEN/g" last9-otel-collector-values.yaml
    else
        log_error "No supported placeholder found in the file."
        log_info "Please use one of these placeholders in your YAML file:"
        echo "  - {{AUTH_TOKEN}}"
        echo "  - \${AUTH_TOKEN}"
        echo "  - {{ .Values.authToken }}"
        exit 1
    fi
    
    # Remove the temporary file created by sed -i
    rm -f last9-otel-collector-values.yaml.tmp
    
    # Verify the change was made
    if grep -q "$AUTH_TOKEN" last9-otel-collector-values.yaml && ! grep -q -E '(\{\{|\$\{).*AUTH_TOKEN.*(\}\}|\})' last9-otel-collector-values.yaml; then
        log_info "✓ Auth token placeholder replaced successfully!"
    else
        log_warn "⚠ Could not verify token replacement. Please check the file manually."
    fi
}

# Function to setup Helm repositories
setup_helm_repos() {
    log_info "Setting up Helm repositories..."
    
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    log_info "Helm repositories updated!"
}

# Function to install OpenTelemetry Operator
install_operator() {
    log_info "Installing OpenTelemetry Operator..."
    
    helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
        --version "$OPERATOR_VERSION" \
        -n "$NAMESPACE" \
        --create-namespace \
        --set "manager.collectorImage.repository=ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s" \
        --set admissionWebhooks.certManager.enabled=false \
        --set admissionWebhooks.autoGenerateCert.enabled=true
    
    log_info "OpenTelemetry Operator installed!"
    
    # Additional wait for webhook service to be available
    log_info "Waiting for webhook service to be available..."
    sleep 30
}

# Function to update deployment mode in values file
update_deployment_mode() {
    log_info "Updating deployment mode from daemonset to deployment..."
    
    # Check if the values file exists
    if [ ! -f "last9-otel-collector-values.yaml" ]; then
        log_error "last9-otel-collector-values.yaml not found!"
        exit 1
    fi
    
    # Create backup of original file
    cp last9-otel-collector-values.yaml last9-otel-collector-values.yaml.backup
    log_info "Created backup: last9-otel-collector-values.yaml.backup"
    
    # Replace daemonset with deployment
    sed -i.tmp 's/mode: "daemonset"/mode: "deployment"/' last9-otel-collector-values.yaml
    
    # Disable logsCollection preset for operator-only case (this disables filelog receiver)
    log_info "Disabling logsCollection preset to remove filelog receiver..."
    # Find the logsCollection section and change enabled: true to enabled: false
    awk '/^  logsCollection:/ {in_section=1; print; next} 
         in_section && /^    enabled: true/ {print "    enabled: false"; in_section=0; next}
         in_section && /^  [^ ]/ {in_section=0}
         {print}' last9-otel-collector-values.yaml > last9-otel-collector-values.yaml.tmp2
    mv last9-otel-collector-values.yaml.tmp2 last9-otel-collector-values.yaml
    
    # Comment out filelog receiver in logs pipeline for operator-only case (backup approach)
    log_info "Commenting out filelog receiver in logs pipeline..."
    sed -i.tmp 's/          - filelog/          # - filelog/' last9-otel-collector-values.yaml
    
    # Remove the temporary file created by sed -i
    rm -f last9-otel-collector-values.yaml.tmp
    
    # Verify the changes were made
    if grep -q 'mode: "deployment"' last9-otel-collector-values.yaml; then
        log_info "✓ Deployment mode updated successfully!"
    else
        log_warn "⚠ Could not verify deployment mode update. Please check the file manually."
    fi
    
    if grep -A 1 'logsCollection:' last9-otel-collector-values.yaml | grep -q 'enabled: false'; then
        log_info "✓ LogsCollection preset disabled successfully!"
    else
        log_warn "⚠ Could not verify logsCollection preset disable. Please check the file manually."
    fi
    
    if grep -q '          # - filelog' last9-otel-collector-values.yaml; then
        log_info "✓ Filelog receiver commented out successfully!"
    else
        log_warn "⚠ Could not verify filelog receiver comment. Please check the file manually."
    fi
}

# Function to install OpenTelemetry Collector
install_collector() {
    log_info "Installing OpenTelemetry Collector..."
    
    local values_file="last9-otel-collector-values.yaml"
    if [ -n "$VALUES_FILE" ]; then
        values_file="$VALUES_FILE"
        log_info "Using custom values file: $values_file"
    fi
    
    helm upgrade --install last9-opentelemetry-collector open-telemetry/opentelemetry-collector \
        --version "$COLLECTOR_VERSION" \
        -n "$NAMESPACE" \
        --create-namespace \
        -f "$values_file"
    
    log_info "OpenTelemetry Collector installed!"
}

# Function to create collector service
create_collector_service() {
    log_info "Creating Collector service..."
    
    # For operator-only mode, update the component selector to standalone-collector
    if [ "$OPERATOR_ONLY" = true ]; then
        log_info "Updating service selector for operator-only mode (component: standalone-collector)..."
        
        # Create a temporary copy of the service file
        cp collector-svc.yaml collector-svc-temp.yaml
        
        # Update the component selector
        sed -i.tmp 's/component: agent-collector/component: standalone-collector/' collector-svc-temp.yaml
        
        # Remove the temporary file created by sed -i
        rm -f collector-svc-temp.yaml.tmp
        
        # Apply the modified service file
        kubectl apply -f collector-svc-temp.yaml -n "$NAMESPACE"
        
        # Clean up temporary file
        rm -f collector-svc-temp.yaml
        
        log_info "✓ Service created with component: standalone-collector"
    else
        # Use the original service file for other modes
        kubectl apply -f collector-svc.yaml -n "$NAMESPACE"
        log_info "✓ Service created with component: agent-collector"
    fi
    
    log_info "Collector service created!"
}

# Function to create instrumentation
create_instrumentation() {
    log_info "Creating Common instrumentation..."
    
    # Retry logic for webhook issues
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt of $max_attempts to create instrumentation..."
        
        if kubectl apply -f instrumentation.yaml -n "$NAMESPACE" 2>/dev/null; then
            log_info "✓ Common instrumentation created successfully!"
            return 0
        else
            log_warn "Attempt $attempt failed. Waiting before retry..."
            sleep 30
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "Failed to create instrumentation after $max_attempts attempts."
    log_info "You can try manually: kubectl apply -f instrumentation.yaml -n $NAMESPACE"
    return 1
}

# Function to verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Check if operator pod is running
    if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=opentelemetry-operator --no-headers | grep -q "Running"; then
        log_info "✓ OpenTelemetry Operator is running"
    else
        log_warn "⚠ OpenTelemetry Operator may not be ready yet"
    fi
    
    # Check if collector pod is running
    if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=opentelemetry-collector --no-headers | grep -q "Running"; then
        log_info "✓ OpenTelemetry Collector is running"
    else
        log_warn "⚠ OpenTelemetry Collector may not be ready yet"
    fi
    
    # Show services
    log_info "Services in $NAMESPACE namespace:"
    kubectl get svc -n "$NAMESPACE"
}

# Function to create logs-only configuration
create_logs_only_config() {
    log_info "Creating logs-only configuration..."
    
    local base_values="last9-otel-collector-values.yaml"
    local logs_values="last9-otel-collector-logs-only.yaml"
    
    # Create a copy of the base values file
    cp "$base_values" "$logs_values"
    
    # Disable metrics collection
    log_info "Disabling metrics collection for logs-only setup..."
    sed -i.tmp 's/hostMetrics:/hostMetrics:\n    enabled: false/' "$logs_values"
    sed -i.tmp 's/kubeletMetrics:/kubeletMetrics:\n    enabled: false/' "$logs_values"
    sed -i.tmp 's/clusterMetrics:/clusterMetrics:\n    enabled: false/' "$logs_values"
    
    # Keep logs collection enabled (already enabled by default)
    log_info "Keeping logs collection enabled..."
    
    # Remove temporary files
    rm -f "$logs_values.tmp"
    
    VALUES_FILE="$logs_values"
    log_info "Logs-only values file created: $VALUES_FILE"
}

# Function to setup Last9 monitoring stack
setup_last9_monitoring() {
    log_info "Setting up Last9 monitoring stack..."
    
    local cluster_name=""
    
    # Parse cluster name from arguments
    for arg in "$@"; do
        case $arg in
            cluster=*)
                cluster_name="${arg#*=}"
                shift
                ;;
        esac
    done
    
    # If cluster name not provided, try to get it from kubectl
    if [ -z "$cluster_name" ]; then
        log_info "Cluster name not provided, attempting to detect from kubectl..."
        cluster_name=$(kubectl config current-context 2>/dev/null || echo "unknown-cluster")
        log_info "Detected cluster name: $cluster_name"
    fi
    
    if [ -z "$cluster_name" ]; then
        log_error "Cluster name is required. Please provide cluster=<cluster-name>"
        exit 1
    fi
    
    log_info "Using cluster name: $cluster_name"
    
    # Use provided credentials
    if [ -z "$LAST9_USERNAME" ] || [ -z "$LAST9_PASSWORD" ]; then
        log_error "Last9 credentials are required for monitoring setup."
        log_error "Please provide username=<value> and password=<value> parameters."
        exit 1
    fi
    
    local username="$LAST9_USERNAME"
    local password="$LAST9_PASSWORD"
    
    log_info "Using Last9 credentials: username=${username:0:8}... password=${password:0:8}..."
    
    # Create the namespace first
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    log_info "✓ Namespace $NAMESPACE created/verified"
    
    # Create the secret for Last9 remote write
    log_info "Creating Last9 remote write secret..."
    kubectl create secret generic last9-remote-write-secret \
        -n "$NAMESPACE" \
        --from-literal=username="$username" \
        --from-literal=password="$password" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "✓ Last9 remote write secret created"
    
    # Check if k8s-monitoring-values.yaml exists
    if [ ! -f "k8s-monitoring-values.yaml" ]; then
        log_error "k8s-monitoring-values.yaml not found in current directory"
        exit 1
    fi
    
    # Create backup of original file
    cp k8s-monitoring-values.yaml k8s-monitoring-values.yaml.backup
    log_info "Created backup: k8s-monitoring-values.yaml.backup"
    
    # Replace cluster name placeholder in the values file
    log_info "Updating cluster name in k8s-monitoring-values.yaml..."
    sed -i.tmp "s/my-cluster-name/$cluster_name/g" k8s-monitoring-values.yaml
    
    # Remove the temporary file created by sed -i
    rm -f k8s-monitoring-values.yaml.tmp
    
    # Verify the change was made
    if grep -q "cluster: $cluster_name" k8s-monitoring-values.yaml; then
        log_info "✓ Cluster name placeholder replaced successfully!"
    else
        log_warn "⚠ Could not verify cluster name replacement. Please check the file manually."
    fi
    
    # Add prometheus-community repo if not already added
    log_info "Adding prometheus-community Helm repository..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install/upgrade the monitoring stack
    log_info "Installing/upgrading Last9 K8s monitoring stack..."
    helm upgrade --install last9-k8s-monitoring prometheus-community/kube-prometheus-stack \
        --version "$MONITORING_VERSION" \
        -n "$NAMESPACE" \
        -f k8s-monitoring-values.yaml \
        --create-namespace
    
    log_info "✓ Last9 K8s monitoring stack deployed successfully!"
    
    # Show the deployed resources
    log_info "Monitoring stack resources in last9 namespace:"
    kubectl get pods -n last9 -l "app.kubernetes.io/name=prometheus" 2>/dev/null || true
    kubectl get pods -n last9 -l "app.kubernetes.io/name=kube-state-metrics" 2>/dev/null || true
    kubectl get pods -n last9 -l "app.kubernetes.io/name=node-exporter" 2>/dev/null || true
    
    log_info "🎉 Last9 monitoring stack setup completed!"
    echo ""
    echo "Summary:"
    echo "  ✓ Created secret: last9-remote-write-secret"
    echo "  ✓ Updated cluster name in k8s-monitoring-values.yaml"
    echo "  ✓ Deployed kube-prometheus-stack with Last9 configuration"
    echo ""
    echo "To verify the deployment:"
    echo "  kubectl get pods -n last9"
    echo "  kubectl get secrets -n last9 last9-remote-write-secret"
    echo "  kubectl get prometheus -n last9"
}

# Function to uninstall Last9 monitoring stack
uninstall_last9_monitoring() {
    log_info "🗑️  Starting Last9 monitoring stack uninstallation..."
    
    # Ask for confirmation
    echo ""
    log_warn "This will remove the Last9 monitoring stack components"
    echo "Components to be removed:"
    echo "  - Helm chart: last9-k8s-monitoring (kube-prometheus-stack)"
    echo "  - Secret: last9-remote-write-secret"
    echo "  - Namespace 'last9' (only if empty after cleanup)"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall cancelled."
        exit 0
    fi
    
    log_info "Proceeding with uninstallation..."
    
    # Remove the Helm chart
    if helm list -n last9 2>/dev/null | grep -q "last9-k8s-monitoring"; then
        log_info "Uninstalling Last9 K8s monitoring stack..."
        helm uninstall last9-k8s-monitoring -n last9 || log_warn "Failed to uninstall monitoring chart"
    else
        log_info "Last9 K8s monitoring stack chart not found"
    fi
    
    # Remove the secret
    log_info "Removing Last9 remote write secret..."
    kubectl delete secret last9-remote-write-secret -n last9 --ignore-not-found=true 2>/dev/null || true
    
    # Wait for Helm resources to be cleaned up
    log_info "Waiting for Helm resources to be cleaned up..."
    sleep 10
    
    # Check if namespace is empty and offer to delete it
    log_info "Checking if namespace 'last9' is empty..."
    remaining_resources=$(kubectl get all -n last9 --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$remaining_resources" -eq 0 ]; then
        log_info "Namespace 'last9' appears to be empty."
        read -p "Do you want to delete the empty namespace 'last9'? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete namespace last9 --ignore-not-found=true
            log_info "✓ Namespace 'last9' deleted"
        else
            log_info "Keeping namespace 'last9'"
        fi
    else
        log_info "Namespace 'last9' contains other resources. Keeping namespace."
        echo "Remaining resources in namespace:"
        kubectl get all -n last9 2>/dev/null || true
    fi
    
    log_info "🎉 Last9 monitoring stack uninstallation completed!"
    echo ""
    echo "Summary of actions taken:"
    echo "  ✓ Removed Helm chart: last9-k8s-monitoring"
    echo "  ✓ Removed secret: last9-remote-write-secret"
    echo "  ✓ Preserved other resources in namespace (if any)"
    echo ""
    echo "To verify cleanup, run:"
    echo "  helm list -n last9 | grep last9-k8s-monitoring  # Should return nothing"
    echo "  kubectl get secrets -n last9 last9-remote-write-secret  # Should return nothing"
}

# Function to uninstall OpenTelemetry components
uninstall_opentelemetry() {
    log_info "🗑️  Starting OpenTelemetry uninstallation..."
    
    # Ask for confirmation
    echo ""
    log_warn "This will remove ONLY the OpenTelemetry components installed by this script"
    echo "Components to be removed:"
    echo "  - Helm chart: last9-opentelemetry-collector"
    echo "  - Helm chart: opentelemetry-operator"
    echo "  - Helm chart: last9-k8s-monitoring (if exists)"
    echo "  - Service: collector-svc (from collector-svc.yaml)"
    echo "  - Instrumentation: from instrumentation.yaml"
    echo "  - Secret: last9-remote-write-secret (if exists)"
    echo "  - Namespace '$NAMESPACE' (only if empty after cleanup)"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall cancelled."
        exit 0
    fi
    
    log_info "Proceeding with uninstallation..."
    
    # Step 1: Remove specific Helm charts installed by this script
    log_info "Removing Helm charts installed by this script..."
    
    # Remove OpenTelemetry Collector (specific release name from our script)
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "last9-opentelemetry-collector"; then
        log_info "Uninstalling OpenTelemetry Collector (last9-opentelemetry-collector)..."
        helm uninstall last9-opentelemetry-collector -n "$NAMESPACE" || log_warn "Failed to uninstall collector chart"
    else
        log_info "OpenTelemetry Collector chart (last9-opentelemetry-collector) not found"
    fi
    
    # Remove OpenTelemetry Operator (specific release name from our script)
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "opentelemetry-operator"; then
        log_info "Uninstalling OpenTelemetry Operator (opentelemetry-operator)..."
        helm uninstall opentelemetry-operator -n "$NAMESPACE" || log_warn "Failed to uninstall operator chart"
    else
        log_info "OpenTelemetry Operator chart (opentelemetry-operator) not found"
    fi
    
    # Remove Last9 K8s monitoring stack (if exists)
    if helm list -n "last9" 2>/dev/null | grep -q "last9-k8s-monitoring"; then
        log_info "Uninstalling Last9 K8s monitoring stack (last9-k8s-monitoring)..."
        helm uninstall last9-k8s-monitoring -n "last9" || log_warn "Failed to uninstall monitoring chart"
    else
        log_info "Last9 K8s monitoring stack chart (last9-k8s-monitoring) not found"
    fi
    
    # Wait for Helm resources to be cleaned up
    log_info "Waiting for Helm resources to be cleaned up..."
    sleep 10
    
    # Step 2: Remove specific Kubernetes resources created by our YAML files
    log_info "Removing specific Kubernetes resources created by this script..."
    
    # Remove instrumentation from instrumentation.yaml
    # Try to identify the instrumentation by common names or labels
    log_info "Removing instrumentation resources..."
    kubectl delete instrumentations --all -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || log_info "No instrumentation resources found"
    
    # Remove service from collector-svc.yaml
    # Common service names that might be in collector-svc.yaml
    log_info "Removing collector service..."
    potential_services=("collector-service" "otel-collector-service" "opentelemetry-collector" "last9-collector" "collector")
    for svc in "${potential_services[@]}"; do
        if kubectl get service "$svc" -n "$NAMESPACE" >/dev/null 2>&1; then
            kubectl delete service "$svc" -n "$NAMESPACE" --ignore-not-found=true
            log_info "Removed service: $svc"
        fi
    done
    
    # Step 3: Clean up any remaining resources with OpenTelemetry labels
    log_info "Cleaning up resources with OpenTelemetry labels..."
    
    # Remove resources with app.kubernetes.io/name=opentelemetry-*
    kubectl delete all -l "app.kubernetes.io/name=opentelemetry-operator" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete all -l "app.kubernetes.io/name=opentelemetry-collector" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    
    # Remove configmaps and secrets created by our installation
    kubectl delete configmaps -l "app.kubernetes.io/name=opentelemetry-operator" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete configmaps -l "app.kubernetes.io/name=opentelemetry-collector" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete secrets -l "app.kubernetes.io/name=opentelemetry-operator" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete secrets -l "app.kubernetes.io/name=opentelemetry-collector" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    
    # Remove RBAC resources created by our installation
    kubectl delete serviceaccounts -l "app.kubernetes.io/name=opentelemetry-operator" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete roles -l "app.kubernetes.io/name=opentelemetry-operator" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete rolebindings -l "app.kubernetes.io/name=opentelemetry-operator" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    
    # Remove Last9 monitoring secret (if exists)
    log_info "Removing Last9 monitoring secret..."
    kubectl delete secret last9-remote-write-secret -n "last9" --ignore-not-found=true 2>/dev/null || true
    
    # Step 4: Check if namespace is empty and offer to delete it
    log_info "Checking if namespace '$NAMESPACE' is empty..."
    remaining_resources=$(kubectl get all -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$remaining_resources" -eq 0 ]; then
        log_info "Namespace '$NAMESPACE' appears to be empty."
        read -p "Do you want to delete the empty namespace '$NAMESPACE'? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
            log_info "✓ Namespace '$NAMESPACE' deleted"
        else
            log_info "Keeping namespace '$NAMESPACE'"
        fi
    else
        log_info "Namespace '$NAMESPACE' contains other resources. Keeping namespace."
        echo "Remaining resources in namespace:"
        kubectl get all -n "$NAMESPACE" 2>/dev/null || true
    fi
    
    # Step 5: Only remove CRDs if no OpenTelemetry resources exist anywhere
    log_info "Checking OpenTelemetry CRDs..."
    if kubectl get crd instrumentations.opentelemetry.io >/dev/null 2>&1; then
        # Check if any instrumentation resources exist across all namespaces
        total_instrumentations=$(kubectl get instrumentations --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
        total_collectors=$(kubectl get opentelemetrycollectors --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$total_instrumentations" -eq 0 ] && [ "$total_collectors" -eq 0 ]; then
            read -p "No OpenTelemetry resources found cluster-wide. Remove OpenTelemetry CRDs? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Removing OpenTelemetry CRDs..."
                kubectl delete crd instrumentations.opentelemetry.io --ignore-not-found=true || true
                kubectl delete crd opentelemetrycollectors.opentelemetry.io --ignore-not-found=true || true
                log_info "✓ OpenTelemetry CRDs removed"
            fi
        else
            log_info "Other OpenTelemetry resources found cluster-wide. Keeping CRDs."
        fi
    fi
    
    # Step 6: Optional Helm repository cleanup
    read -p "Do you want to remove the OpenTelemetry Helm repository? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        helm repo remove open-telemetry 2>/dev/null || log_warn "OpenTelemetry Helm repository not found"
        log_info "✓ OpenTelemetry Helm repository removed"
    fi
    
    log_info "🎉 OpenTelemetry uninstallation completed!"
    echo ""
    echo "Summary of actions taken:"
    echo "  ✓ Removed Helm chart: last9-opentelemetry-collector"
    echo "  ✓ Removed Helm chart: opentelemetry-operator"  
    echo "  ✓ Removed specific Kubernetes resources created by this script"
    echo "  ✓ Cleaned up OpenTelemetry labeled resources"
    echo "  ✓ Preserved other resources in namespace (if any)"
    echo ""
    echo "To verify cleanup, run:"
    echo "  helm list -n $NAMESPACE | grep opentelemetry  # Should return nothing"
    echo "  kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-operator"
    echo "  kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector"
}

# Function to uninstall everything (OpenTelemetry + Monitoring)
uninstall_all() {
    log_info "🗑️  Starting complete uninstallation (OpenTelemetry + Monitoring)..."
    
    # Ask for confirmation
    echo ""
    log_warn "This will remove ALL components installed by this script"
    echo "Components to be removed:"
    echo "  - OpenTelemetry components (operator, collector, instrumentation)"
    echo "  - Last9 monitoring stack (kube-prometheus-stack)"
    echo "  - Last9 remote write secret"
    echo "  - Namespaces (if empty after cleanup)"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall cancelled."
        exit 0
    fi
    
    log_info "Proceeding with complete uninstallation..."
    
    # First uninstall monitoring stack
    log_info "Step 1: Uninstalling Last9 monitoring stack..."
    uninstall_last9_monitoring
    
    # Then uninstall OpenTelemetry components
    log_info "Step 2: Uninstalling OpenTelemetry components..."
    uninstall_opentelemetry
    
    log_info "🎉 Complete uninstallation finished!"
    echo ""
    echo "All components have been removed successfully!"
}

# Function to cleanup temporary files
cleanup() {
    # Always cleanup temporary files unless it's an uninstall operation
    if [ "$UNINSTALL_MODE" = false ] && [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        log_info "Cleaning up temporary files..."
        # Go back to the original directory and remove the work directory
        cd "$(dirname "$0")" 2>/dev/null || cd /tmp
        rm -rf "$WORK_DIR"
        log_info "✓ Temporary directory '$WORK_DIR' removed"
    fi
}

# Main execution function
main() {
    # Check if no arguments provided
    if [ $# -eq 0 ]; then
        echo ""
        log_info "No arguments provided. Showing available examples:"
        echo ""
        show_examples
        exit 0
    fi
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    if [ "$UNINSTALL_MODE" = true ] && [ -n "$FUNCTION_TO_EXECUTE" ]; then
        # Handle special uninstall functions
        case "$FUNCTION_TO_EXECUTE" in
            uninstall_last9_monitoring)
                log_info "Running monitoring-specific uninstall..."
                uninstall_last9_monitoring
                ;;
            uninstall_all)
                log_info "Running complete uninstall..."
                uninstall_all
                ;;
            *)
                log_warn "Unknown uninstall function: $FUNCTION_TO_EXECUTE"
                log_info "Running standard OpenTelemetry uninstall..."
                uninstall_opentelemetry
                ;;
        esac
    elif [ "$UNINSTALL_MODE" = true ]; then
        # Run standard uninstall process
        uninstall_opentelemetry
    elif [ -n "$FUNCTION_TO_EXECUTE" ]; then
        # Execute individual function
        log_info "Executing individual function: $FUNCTION_TO_EXECUTE"
        
        case "$FUNCTION_TO_EXECUTE" in
            setup_helm_repos)
                setup_helm_repos
                ;;
            install_operator)
                setup_helm_repos
                install_operator
                ;;
            install_collector)
                if [ -z "$AUTH_TOKEN" ]; then
                    log_error "Token is required for install_collector function"
                    exit 1
                fi
                setup_helm_repos
                if [ -n "$VALUES_FILE" ]; then
                    log_info "Using custom values file from current directory: $VALUES_FILE"
                    # Check if values file exists in current directory
                    if [ ! -f "$VALUES_FILE" ]; then
                        log_error "Values file '$VALUES_FILE' not found in current directory"
                        exit 1
                    fi
                    
                    # For individual function calls with custom values, use as-is (no token replacement)
                    log_info "Using values file as-is for individual function call"
                    helm upgrade --install last9-opentelemetry-collector open-telemetry/opentelemetry-collector \
                        --version "$COLLECTOR_VERSION" \
                        -n "$NAMESPACE" \
                        --create-namespace \
                        -f "$VALUES_FILE"
                else
                    # Use default behavior - clone repo and use default values file with token replacement
                    setup_repository
                    install_collector
                fi
                ;;
            create_collector_service)
                setup_repository
                create_collector_service
                ;;
            create_instrumentation)
                setup_repository
                create_instrumentation
                ;;
            verify_installation)
                verify_installation
                ;;
            setup_last9_monitoring)
                setup_last9_monitoring "$@"
                ;;
            uninstall_last9_monitoring)
                uninstall_last9_monitoring
                ;;
            uninstall_all)
                uninstall_all
                ;;
            *)
                log_error "Unknown function: $FUNCTION_TO_EXECUTE"
                echo "Available functions: setup_helm_repos, install_operator, install_collector, create_collector_service, create_instrumentation, verify_installation, setup_last9_monitoring, uninstall_last9_monitoring, uninstall_all"
                exit 1
                ;;
        esac
        
        # Cleanup for individual functions
        cleanup
        
        log_info "✅ Function '$FUNCTION_TO_EXECUTE' completed successfully!"
    elif [ "$MONITORING_ONLY" = true ]; then
        # Install only Cluster Monitoring (Prometheus stack)
        log_info "Starting Cluster Monitoring installation..."
        
        # Check if credentials are provided
        if [ -z "$LAST9_USERNAME" ] || [ -z "$LAST9_PASSWORD" ]; then
            log_error "Last9 credentials are required for monitoring setup."
            log_error "Please provide username=<value> and password=<value> parameters."
            exit 1
        fi
        
        # Check if cluster name is provided
        if [ -z "$CLUSTER_NAME" ]; then
            log_info "Cluster name not provided, attempting to detect from kubectl..."
            CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown-cluster")
            log_info "Detected cluster name: $CLUSTER_NAME"
        fi
        
        setup_repository
        setup_helm_repos
        setup_last9_monitoring cluster="$CLUSTER_NAME"
        
        cleanup
        
        log_info "🎉 Cluster Monitoring installation completed successfully!"
        log_info "Next steps:"
        echo "  1. Wait for monitoring pods to be in Running state: kubectl get pods -n $NAMESPACE"
        echo "  2. Check Prometheus logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=prometheus"
        echo "  3. Verify monitoring services: kubectl get svc -n $NAMESPACE"
        echo ""
        echo "📝 Note: Monitoring stack deployed with cluster name: $CLUSTER_NAME"
        echo ""
        echo "To add OpenTelemetry later, run: $0 token=\"your-token\""
        echo "To uninstall later, run: $0 uninstall function=\"uninstall_last9_monitoring\""
    elif [ "$LOGS_ONLY" = true ]; then
        # Install only Collector for logs
        log_info "Starting OpenTelemetry Collector for logs installation..."
        
        setup_repository
        setup_helm_repos
        create_logs_only_config
        install_collector
        create_collector_service
        verify_installation
        
        cleanup
        
        log_info "🎉 OpenTelemetry Collector for logs installation completed successfully!"
        log_info "Next steps:"
        echo "  1. Wait for collector pod to be in Running state: kubectl get pods -n $NAMESPACE"
        echo "  2. Check collector logs if needed: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector"
        echo "  3. Verify collector service: kubectl get svc -n $NAMESPACE"
        echo ""
        echo "📝 Note: Logs-only configuration file created: last9-otel-collector-logs-only.yaml"
        echo ""
        echo "To add operator later, run: $0 operator-only"
        echo "To add monitoring later, run: $0 token=\"your-token\" cluster=\"cluster-name\" username=\"user\" password=\"pass\""
        echo "To uninstall later, run: $0 uninstall"
    elif [ "$OPERATOR_ONLY" = true ]; then
        # Install OpenTelemetry Operator and Collector
        log_info "Starting OpenTelemetry Operator and Collector installation..."
        
        # Check if token is provided for collector installation
        if [ -z "$AUTH_TOKEN" ]; then
            log_error "Auth token is required for collector installation."
            log_error "Please provide token=<value> parameter for operator-only installation."
            exit 1
        fi
        
        setup_repository
        setup_helm_repos
        update_deployment_mode
        install_operator
        install_collector
        create_collector_service
        create_instrumentation
        verify_installation
        
        cleanup
        
        log_info "🎉 OpenTelemetry Operator and Collector installation completed successfully!"
        log_info "Next steps:"
        echo "  1. Wait for operator pod to be in Running state: kubectl get pods -n $NAMESPACE"
        echo "  2. Wait for collector pod to be in Running state: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector"
        echo "  3. Check operator logs if needed: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-operator"
        echo "  4. Check collector logs if needed: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector"
        echo "  5. Verify services: kubectl get svc -n $NAMESPACE"
        echo "  6. Check instrumentation: kubectl get instrumentation -n $NAMESPACE"
        echo ""
        echo "📝 Note: Deployment mode changed from daemonset to deployment"
        echo "📝 Note: LogsCollection preset disabled (removes filelog receiver)"
        echo "📝 Note: Filelog receiver commented out in logs pipeline (backup approach)"
        echo "📝 Note: Service selector updated to component: standalone-collector"
        echo "📝 Note: Original values file backed up as last9-otel-collector-values.yaml.backup"
        echo ""
        echo "To add monitoring later, run: $0 token=\"your-token\" cluster=\"cluster-name\" username=\"user\" password=\"pass\""
        echo "To uninstall later, run: $0 uninstall"
    else
        # Run installation process
        log_info "Starting OpenTelemetry setup automation..."
        
        setup_repository
        setup_helm_repos
        install_operator
        install_collector
        create_collector_service
        create_instrumentation
        verify_installation
        
        # Install monitoring stack if requested
        if [ "$SETUP_MONITORING" = true ]; then
            log_info "Installing Last9 monitoring stack..."
            setup_last9_monitoring cluster="$CLUSTER_NAME"
        fi
        
        cleanup
        
        log_info "🎉 OpenTelemetry setup completed successfully!"
        log_info "Next steps:"
        echo "  1. Wait for all pods to be in Running state: kubectl get pods -n $NAMESPACE"
        echo "  2. Check logs if needed: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector"
        echo "  3. Verify services: kubectl get svc -n $NAMESPACE"
        echo ""
        echo "📝 Note: Original values file backed up as last9-otel-collector-values.yaml.backup"
        echo ""
        echo "To uninstall later, run: $0 uninstall"
    fi
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"

