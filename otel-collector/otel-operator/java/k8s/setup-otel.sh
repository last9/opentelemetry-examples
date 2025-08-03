#!/bin/bash

# OpenTelemetry Setup Automation Script
# Usage: 
#   Install: ./setup-otel.sh token="your-token-here"
#   Uninstall: ./setup-otel.sh uninstall
# Example: 
#   ./setup-otel.sh token="your-token-here"
#   ./setup-otel.sh uninstall

set -e  # Exit on any error

# Configuration defaults
NAMESPACE="last9"
OPERATOR_VERSION="0.129.1"
COLLECTOR_VERSION="0.126.0"
WORK_DIR="otel-setup-$(date +%s)"
DEFAULT_REPO="https://github.com/last9/opentelemetry-examples.git#opentelemetary-operator"

# Initialize variables
AUTH_TOKEN=""
REPO_URL="$DEFAULT_REPO"
UNINSTALL_MODE=false
FUNCTION_TO_EXECUTE=""
VALUES_FILE=""

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
            uninstall)
                UNINSTALL_MODE=true
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

# Show help function
show_help() {
    echo "OpenTelemetry Setup Automation Script"
    echo ""
    echo "Usage:"
    echo "  Install:   $0 token=\"your-token-here\" [repo=\"repository-url\"]"
    echo "  Uninstall: $0 uninstall"
    echo "  Individual: $0 function=\"function_name\" [token=\"your-token\"] [values=\"values-file\"]"
    echo ""
    echo "Install Arguments:"
    echo "  token=<value>    Required. The auth token for authentication"
    echo "  repo=<value>     Optional. Git repository URL (default: OpenTelemetry examples)"
    echo ""
    echo "Uninstall Arguments:"
    echo "  uninstall        Remove all OpenTelemetry components and resources"
    echo ""
    echo "Individual Function Arguments:"
    echo "  function=<name>  Execute specific function: setup_helm_repos, install_operator,"
    echo "                   install_collector, create_collector_service, create_instrumentation,"
    echo "                   verify_installation"
    echo "  token=<value>    Required for functions that need authentication"
    echo "  values=<file>    Custom values file for install_collector function (looks in current directory)"
    echo ""
    echo "Other:"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 token=\"bXl1c2VyOm15cGFzcw==\""
    echo "  $0 token=\"Y2xpZW50QTpwYXNz\" repo=\"https://github.com/my-repo.git\""
    echo "  $0 uninstall"
    echo "  $0 function=\"install_collector\" token=\"bXl1c2VyOm15cGFzcw==\" values=\"custom-values.yaml\""
    echo "  $0 function=\"setup_helm_repos\""
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Skip token check for uninstall mode
    if [ "$UNINSTALL_MODE" = false ] && [ -z "$AUTH_TOKEN" ]; then
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
        log_info "Using auth token: ${AUTH_TOKEN:0:10}..."  # Show only first 10 chars for security
        log_info "Using repository: $REPO_URL"
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
    
    # Replace placeholder with actual token
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
    helm repo update
    
    log_info "Helm repositories updated!"
}

# Function to install OpenTelemetry Operator
install_operator() {
    log_info "Installing OpenTelemetry Operator..."
    
    helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
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
    
    kubectl apply -f collector-svc.yaml -n "$NAMESPACE"
    
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

# Function to uninstall OpenTelemetry components
uninstall_opentelemetry() {
    log_info "🗑️  Starting OpenTelemetry uninstallation..."
    
    # Ask for confirmation
    echo ""
    log_warn "This will remove ONLY the OpenTelemetry components installed by this script"
    echo "Components to be removed:"
    echo "  - Helm chart: last9-opentelemetry-collector"
    echo "  - Helm chart: opentelemetry-operator"
    echo "  - Service: collector-svc (from collector-svc.yaml)"
    echo "  - Instrumentation: from instrumentation.yaml"
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

# Function to cleanup temporary files
cleanup() {
    if [ "$UNINSTALL_MODE" = false ]; then
        log_info "Cleaning up temporary files..."
        cd ..
        rm -rf "$WORK_DIR"
        log_info "Cleanup completed!"
    fi
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    if [ "$UNINSTALL_MODE" = true ]; then
        # Run uninstall process
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
                    
                    # Create a temporary copy of the values file for token replacement
                    local temp_values_file="${VALUES_FILE}.tmp"
                    cp "$VALUES_FILE" "$temp_values_file"
                    
                    # Replace token placeholder in the temporary file
                    log_info "Replacing auth token placeholder in values file..."
                    if grep -q '{{AUTH_TOKEN}}' "$temp_values_file"; then
                        sed -i.tmp "s/{{AUTH_TOKEN}}/$AUTH_TOKEN/g" "$temp_values_file"
                    elif grep -q '\${AUTH_TOKEN}' "$temp_values_file"; then
                        sed -i.tmp "s/\${AUTH_TOKEN}/$AUTH_TOKEN/g" "$temp_values_file"
                    elif grep -q '{{ \.Values\.authToken }}' "$temp_values_file"; then
                        sed -i.tmp "s/{{ \.Values\.authToken }}/$AUTH_TOKEN/g" "$temp_values_file"
                    else
                        log_warn "No supported placeholder found in the values file. Using as-is."
                    fi
                    
                    # Remove the temporary file created by sed -i
                    rm -f "${temp_values_file}.tmp"
                    
                    helm upgrade --install last9-opentelemetry-collector open-telemetry/opentelemetry-collector \
                        --version "$COLLECTOR_VERSION" \
                        -n "$NAMESPACE" \
                        --create-namespace \
                        -f "$temp_values_file"
                    
                    # Clean up temporary file
                    rm -f "$temp_values_file"
                else
                    # Use default behavior - clone repo and use default values file
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
            *)
                log_error "Unknown function: $FUNCTION_TO_EXECUTE"
                echo "Available functions: setup_helm_repos, install_operator, install_collector, create_collector_service, create_instrumentation, verify_installation"
                exit 1
                ;;
        esac
        
        log_info "✅ Function '$FUNCTION_TO_EXECUTE' completed successfully!"
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

