#!/bin/bash

# OpenTelemetry Setup Automation Script
# Usage:
#    Show all options
#    ./last9-otel-setup.sh

#    Option 1: Install Everything (Recommended - Logs, Traces, Cluster Monitoring and Events)
#    ./last9-otel-setup.sh token="your-token-here" endpoint="your-endpoint-here" monitoring-endpoint="your-metrics-endpoint" username="your-username" password="your-password"

#    Option 2: For Traces alone --> Install OpenTelemetry Operator and collector
#    ./last9-otel-setup.sh operator-only endpoint="your-endpoint-here" token="your-token-here"

#    Option 3: For Logs use case --> Install Only Collector for Logs (No Operator)
#    ./last9-otel-setup.sh logs-only endpoint="your-endpoint-here" token="your-token-here"

#    Option 4: Install Only Cluster Monitoring (Using Metrics)
#    ./last9-otel-setup.sh monitoring-only monitoring-endpoint="your-metrics-endpoint" username="your-username" password="your-password"

#    Option 5: Install Only Kubernetes Events Agent
#    ./last9-otel-setup.sh events-only

#    Uninstall All components
#    ./last9-otel-setup.sh uninstall-all


set -e  # Exit on any error

# Configuration defaults
NAMESPACE="last9"
OPERATOR_VERSION="0.92.1"
COLLECTOR_VERSION="0.126.0"
MONITORING_VERSION="75.15.1"

WORK_DIR="otel-setup-$(date +%s)"
DEFAULT_REPO="https://github.com/last9/opentelemetry-examples.git#main"
ORIGINAL_DIR="$(pwd)"

# Initialize variables
AUTH_TOKEN=""
OTEL_ENDPOINT=""
MONITORING_ENDPOINT=""
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
EVENTS_ONLY=false
TOLERATIONS_FILE=""
USE_YQ=false
DEPLOYMENT_ENV=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Helper function to escape special characters for sed
escape_for_sed() {
    printf '%s\n' "$1" | sed 's:[[\.*^$()+?{|/]:\\&:g'
}

# Check if yq is available
check_yq_available() {
    if command -v yq >/dev/null 2>&1; then
        USE_YQ=true
        log_info "✓ yq found: $(yq --version 2>&1 | head -n1)"
    else
        USE_YQ=false
        log_warn "⚠ yq not found - using awk/sed fallback for YAML parsing"
        log_warn "  For better reliability, install yq:"
        log_warn "  - macOS: brew install yq"
        log_warn "  - Linux: wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq"
    fi
}

# Load and parse tolerations from YAML file
load_tolerations_from_file() {
    local file_path="$1"

    log_info "Loading tolerations from file: $file_path"

    # Validate file exists and is readable
    if [ ! -f "$file_path" ]; then
        log_error "Tolerations file not found: $file_path"
        exit 1
    fi

    if [ ! -r "$file_path" ]; then
        log_error "Tolerations file is not readable: $file_path"
        exit 1
    fi

    # Check for yq
    check_yq_available

    log_info "✓ Tolerations file loaded successfully"

    # Store the file path for later use
    export TOLERATIONS_FILE_PATH="$file_path"
}

# Convert tolerations from YAML to Helm --set format
convert_tolerations_to_helm_set() {
    local file_path="$1"
    local prefix="$2"  # e.g., "" for operator, "manager" for other charts
    local helm_args=""
    local path_prefix=""

    # Add dot separator only if prefix is not empty
    [ -n "$prefix" ] && path_prefix="${prefix}."

    if [ "$USE_YQ" = true ]; then
        # Use yq to parse YAML and convert to --set format
        local count=0
        local tolerations_count=$(yq eval '.tolerations | length' "$file_path" 2>/dev/null || echo "0")

        if [ "$tolerations_count" != "0" ] && [ "$tolerations_count" != "null" ]; then
            while [ $count -lt $tolerations_count ]; do
                local key=$(yq eval ".tolerations[$count].key" "$file_path" 2>/dev/null)
                local operator=$(yq eval ".tolerations[$count].operator" "$file_path" 2>/dev/null)
                local value=$(yq eval ".tolerations[$count].value" "$file_path" 2>/dev/null)
                local effect=$(yq eval ".tolerations[$count].effect" "$file_path" 2>/dev/null)

                if [ "$key" != "null" ]; then
                    helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].key=$key"
                    helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].operator=$operator"
                    [ "$value" != "null" ] && helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].value=$value"
                    [ "$effect" != "null" ] && helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].effect=$effect"
                fi

                count=$((count + 1))
            done
        fi
    else
        # Awk fallback for parsing YAML
        log_warn "Using awk fallback for tolerations parsing"

        local in_tolerations=false
        local count=0
        local current_key=""
        local current_operator=""
        local current_value=""
        local current_effect=""

        while IFS= read -r line; do
            # Check if we're in the tolerations section
            if echo "$line" | grep -q "^tolerations:"; then
                in_tolerations=true
                continue
            fi

            # Exit tolerations section if we hit another top-level key
            if echo "$line" | grep -q "^[a-zA-Z]" && [ "$in_tolerations" = true ]; then
                in_tolerations=false
            fi

            if [ "$in_tolerations" = true ]; then
                # Parse toleration entry
                if echo "$line" | grep -q "^  - key:"; then
                    # Save previous entry if exists
                    if [ -n "$current_key" ]; then
                        helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].key=$current_key"
                        helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].operator=$current_operator"
                        [ -n "$current_value" ] && helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].value=$current_value"
                        [ -n "$current_effect" ] && helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].effect=$current_effect"
                        count=$((count + 1))
                    fi

                    # Start new entry
                    current_key=$(echo "$line" | sed -E 's/.*key: *"?([^"]*)"?.*/\1/')
                    current_operator=""
                    current_value=""
                    current_effect=""
                elif echo "$line" | grep -q "operator:"; then
                    current_operator=$(echo "$line" | sed -E 's/.*operator: *"?([^"]*)"?.*/\1/')
                elif echo "$line" | grep -q "value:"; then
                    current_value=$(echo "$line" | sed -E 's/.*value: *"?([^"]*)"?.*/\1/')
                elif echo "$line" | grep -q "effect:"; then
                    current_effect=$(echo "$line" | sed -E 's/.*effect: *"?([^"]*)"?.*/\1/')
                fi
            fi
        done < "$file_path"

        # Save last entry
        if [ -n "$current_key" ]; then
            helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].key=$current_key"
            helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].operator=$current_operator"
            [ -n "$current_value" ] && helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].value=$current_value"
            [ -n "$current_effect" ] && helm_args="$helm_args --set-string ${path_prefix}tolerations[$count].effect=$current_effect"
        fi
    fi

    echo "$helm_args"
}

# Convert nodeSelector from YAML to Helm --set format
convert_node_selector_to_helm_set() {
    local file_path="$1"
    local prefix="$2"  # e.g., "" for operator, "manager" for other charts
    local helm_args=""
    local path_prefix=""

    # Add dot separator only if prefix is not empty
    [ -n "$prefix" ] && path_prefix="${prefix}."

    if [ "$USE_YQ" = true ]; then
        # Check if nodeSelector exists and is not empty
        local has_selector=$(yq eval '.nodeSelector | length' "$file_path" 2>/dev/null || echo "0")

        if [ "$has_selector" != "0" ] && [ "$has_selector" != "null" ]; then
            # Get all keys
            local keys=$(yq eval '.nodeSelector | keys | .[]' "$file_path" 2>/dev/null)

            while IFS= read -r key; do
                if [ -n "$key" ]; then
                    local value=$(yq eval ".nodeSelector.\"$key\"" "$file_path" 2>/dev/null)
                    # Escape special characters in key for Helm --set
                    local escaped_key=$(echo "$key" | sed 's/\./\\./g')
                    # Use --set-string to force string interpretation (prevents boolean conversion)
                    helm_args="$helm_args --set-string ${path_prefix}nodeSelector.${escaped_key}=$value"
                fi
            done <<< "$keys"
        fi
    else
        # Awk fallback for nodeSelector parsing
        local in_selector=false

        while IFS= read -r line; do
            if echo "$line" | grep -q "^nodeSelector:"; then
                in_selector=true
                # Check if it's empty object
                if echo "$line" | grep -q "nodeSelector: {}"; then
                    break
                fi
                continue
            fi

            # Exit nodeSelector section
            if echo "$line" | grep -q "^[a-zA-Z]" && [ "$in_selector" = true ]; then
                break
            fi

            if [ "$in_selector" = true ]; then
                # Parse key: value
                if echo "$line" | grep -q ":"; then
                    local key=$(echo "$line" | sed -E 's/^ *([^:]+):.*/\1/' | tr -d '"')
                    local value=$(echo "$line" | sed -E 's/.*: *"?([^"]*)"?.*/\1/')

                    if [ -n "$key" ]; then
                        local escaped_key=$(echo "$key" | sed 's/\./\\./g')
                        # Use --set-string to force string interpretation (prevents boolean conversion)
                        helm_args="$helm_args --set-string ${path_prefix}nodeSelector.${escaped_key}=$value"
                    fi
                fi
            fi
        done < "$file_path"
    fi

    echo "$helm_args"
}

# Apply tolerations to collector values file
apply_tolerations_to_collector_values() {
    local values_file="$1"
    local tolerations_file="$TOLERATIONS_FILE_PATH"

    log_info "Applying tolerations to collector values file: $values_file"

    # Create backup
    cp "$values_file" "${values_file}.backup-tolerations"
    log_info "Created backup: ${values_file}.backup-tolerations"

    if [ "$USE_YQ" = true ]; then
        # Use yq for precise YAML manipulation

        # Apply tolerations
        local has_tolerations=$(yq eval '.tolerations | length' "$tolerations_file" 2>/dev/null || echo "0")
        if [ "$has_tolerations" != "0" ] && [ "$has_tolerations" != "null" ]; then
            log_info "Applying tolerations array to collector values..."
            yq eval-all 'select(fileIndex == 0).tolerations = select(fileIndex == 1).tolerations | select(fileIndex == 0)' \
                "$values_file" "$tolerations_file" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
        fi

        # Apply nodeSelector
        local has_selector=$(yq eval '.nodeSelector | length' "$tolerations_file" 2>/dev/null || echo "0")
        if [ "$has_selector" != "0" ] && [ "$has_selector" != "null" ]; then
            log_info "Applying nodeSelector to collector values..."
            yq eval-all 'select(fileIndex == 0).nodeSelector = select(fileIndex == 1).nodeSelector | select(fileIndex == 0)' \
                "$values_file" "$tolerations_file" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
        fi
    else
        # Awk fallback - replace tolerations: [] and nodeSelector: {}
        log_warn "Using awk fallback for collector values injection"

        # Extract tolerations from file and format as YAML
        local tolerations_yaml=""
        local in_tolerations=false
        while IFS= read -r line; do
            if echo "$line" | grep -q "^tolerations:"; then
                in_tolerations=true
                continue
            fi
            if echo "$line" | grep -q "^[a-zA-Z]" && [ "$in_tolerations" = true ]; then
                break
            fi
            if [ "$in_tolerations" = true ]; then
                tolerations_yaml="${tolerations_yaml}${line}\n"
            fi
        done < "$tolerations_file"

        # Replace in values file
        if [ -n "$tolerations_yaml" ]; then
            awk -v tol="$tolerations_yaml" '
            /^tolerations: \[\]/ {
                print "tolerations:"
                printf "%s", tol
                next
            }
            {print}
            ' "$values_file" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
        fi

        # Extract and apply nodeSelector
        local selector_yaml=""
        local in_selector=false
        while IFS= read -r line; do
            if echo "$line" | grep -q "^nodeSelector:"; then
                in_selector=true
                if echo "$line" | grep -q "nodeSelector: {}"; then
                    break
                fi
                continue
            fi
            if echo "$line" | grep -q "^[a-zA-Z]" && [ "$in_selector" = true ]; then
                break
            fi
            if [ "$in_selector" = true ]; then
                selector_yaml="${selector_yaml}${line}\n"
            fi
        done < "$tolerations_file"

        if [ -n "$selector_yaml" ]; then
            awk -v sel="$selector_yaml" '
            /^nodeSelector: \{\}/ {
                print "nodeSelector:"
                printf "%s", sel
                next
            }
            {print}
            ' "$values_file" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
        fi
    fi

    log_info "✓ Tolerations applied to collector values file"
}

# Apply tolerations to monitoring values file
apply_tolerations_to_monitoring_values() {
    local values_file="$1"
    local tolerations_file="$TOLERATIONS_FILE_PATH"

    log_info "Applying tolerations to monitoring values file: $values_file"

    # Create backup
    cp "$values_file" "${values_file}.backup-tolerations"
    log_info "Created backup: ${values_file}.backup-tolerations"

    if [ "$USE_YQ" = true ]; then
        # Apply to Prometheus
        local has_tolerations=$(yq eval '.tolerations | length' "$tolerations_file" 2>/dev/null || echo "0")
        if [ "$has_tolerations" != "0" ] && [ "$has_tolerations" != "null" ]; then
            log_info "Applying tolerations to prometheus.prometheusSpec..."
            yq eval ".prometheus.prometheusSpec.tolerations = $(yq eval '.tolerations' "$tolerations_file")" -i "$values_file"

            log_info "Applying tolerations to kubeStateMetrics..."
            yq eval ".kubeStateMetrics.tolerations = $(yq eval '.tolerations' "$tolerations_file")" -i "$values_file"

            log_info "Applying tolerations to prometheusOperator..."
            yq eval ".prometheusOperator.tolerations = $(yq eval '.tolerations' "$tolerations_file")" -i "$values_file"
        fi

        # Apply nodeSelector
        local has_selector=$(yq eval '.nodeSelector | length' "$tolerations_file" 2>/dev/null || echo "0")
        if [ "$has_selector" != "0" ] && [ "$has_selector" != "null" ]; then
            log_info "Applying nodeSelector to prometheus.prometheusSpec..."
            yq eval ".prometheus.prometheusSpec.nodeSelector = $(yq eval '.nodeSelector' "$tolerations_file")" -i "$values_file"

            log_info "Applying nodeSelector to kubeStateMetrics..."
            yq eval ".kubeStateMetrics.nodeSelector = $(yq eval '.nodeSelector' "$tolerations_file")" -i "$values_file"

            log_info "Applying nodeSelector to prometheusOperator..."
            yq eval ".prometheusOperator.nodeSelector = $(yq eval '.nodeSelector' "$tolerations_file")" -i "$values_file"
        fi

        # Special handling for node-exporter - check for nodeExporterTolerations
        local has_node_exporter_tol=$(yq eval '.nodeExporterTolerations | length' "$tolerations_file" 2>/dev/null || echo "0")
        if [ "$has_node_exporter_tol" != "0" ] && [ "$has_node_exporter_tol" != "null" ]; then
            log_info "Applying special nodeExporterTolerations..."
            yq eval ".nodeExporter.tolerations = $(yq eval '.nodeExporterTolerations' "$tolerations_file")" -i "$values_file"
        else
            # Default: operator Exists (run on all nodes)
            log_info "Applying default permissive tolerations to node-exporter (operator: Exists)..."
            yq eval '.nodeExporter.tolerations = [{"operator": "Exists"}]' -i "$values_file"
        fi
    else
        # Awk fallback - using sed for simpler and more reliable injection
        log_warn "Using awk/sed fallback for monitoring values injection"

        # Create temp file for extracted sections
        local temp_dir=$(mktemp -d)
        local tol_file="$temp_dir/tolerations.txt"
        local ns_file="$temp_dir/nodeselector.txt"
        local ne_tol_file="$temp_dir/ne_tolerations.txt"

        # Extract sections from tolerations file
        awk '/^tolerations:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && NF' "$tolerations_file" > "$tol_file"
        awk '/^nodeSelector:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && NF && !/^#/' "$tolerations_file" > "$ns_file"
        awk '/^nodeExporterTolerations:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && NF' "$tolerations_file" > "$ne_tol_file"

        # Apply to prometheusOperator using sed
        if [ -s "$tol_file" ]; then
            log_info "Injecting tolerations to prometheusOperator..."
            # Find prometheusOperator: and insert tolerations after it
            sed '/^prometheusOperator:/a\
  tolerations:
' "$values_file" > "${values_file}.tmp1"
            # Now insert the actual toleration content
            awk -v tol_file="$tol_file" '
                /^prometheusOperator:/ {print; getline; print
                    while ((getline line < tol_file) > 0) {
                        print "  " line
                    }
                    close(tol_file)
                    next
                }
                {print}
            ' "${values_file}.tmp1" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
            rm -f "${values_file}.tmp1"
        fi

        # Apply to kubeStateMetrics
        if [ -s "$tol_file" ]; then
            log_info "Injecting tolerations to kubeStateMetrics..."
            sed '/^kubeStateMetrics:/a\
  tolerations:
' "$values_file" > "${values_file}.tmp1"
            awk -v tol_file="$tol_file" '
                /^kubeStateMetrics:/ {print; getline; print
                    while ((getline line < tol_file) > 0) {
                        print "  " line
                    }
                    close(tol_file)
                    next
                }
                {print}
            ' "${values_file}.tmp1" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
            rm -f "${values_file}.tmp1"
        fi

        # Apply nodeSelector to prometheusOperator
        if [ -s "$ns_file" ]; then
            log_info "Injecting nodeSelector to prometheusOperator..."
            sed '/^prometheusOperator:/a\
  nodeSelector:
' "$values_file" > "${values_file}.tmp1"
            awk -v ns_file="$ns_file" '
                /^prometheusOperator:/ {print; getline; print
                    while ((getline line < ns_file) > 0) {
                        print "  " line
                    }
                    close(ns_file)
                    next
                }
                {print}
            ' "${values_file}.tmp1" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
            rm -f "${values_file}.tmp1"
        fi

        # Apply nodeSelector to kubeStateMetrics
        if [ -s "$ns_file" ]; then
            log_info "Injecting nodeSelector to kubeStateMetrics..."
            sed '/^kubeStateMetrics:/a\
  nodeSelector:
' "$values_file" > "${values_file}.tmp1"
            awk -v ns_file="$ns_file" '
                /^kubeStateMetrics:/ {print; getline; print
                    while ((getline line < ns_file) > 0) {
                        print "  " line
                    }
                    close(ns_file)
                    next
                }
                {print}
            ' "${values_file}.tmp1" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
            rm -f "${values_file}.tmp1"
        fi

        # Apply node-exporter tolerations
        if [ -s "$ne_tol_file" ]; then
            log_info "Injecting nodeExporterTolerations..."
            sed '/^nodeExporter:/a\
  tolerations:
' "$values_file" > "${values_file}.tmp1"
            awk -v ne_file="$ne_tol_file" '
                /^nodeExporter:/ {print; getline; print
                    while ((getline line < ne_file) > 0) {
                        print "  " line
                    }
                    close(ne_file)
                    next
                }
                {print}
            ' "${values_file}.tmp1" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
            rm -f "${values_file}.tmp1"
        else
            log_info "Applying default permissive tolerations to node-exporter (operator: Exists)..."
            sed '/^nodeExporter:/a\
  tolerations:\
    - operator: Exists
' "$values_file" > "${values_file}.tmp"
            mv "${values_file}.tmp" "$values_file"
        fi

        # Cleanup temp files
        rm -rf "$temp_dir"

        log_info "✓ Awk/sed fallback completed"
    fi

    log_info "✓ Tolerations applied to monitoring values file"
}

# Function to patch monitoring components with tolerations and nodeSelector directly via kubectl
# This handles components that don't properly inherit tolerations from Helm values
# This is the primary method for applying tolerations/nodeSelector (more reliable than Helm values)
patch_monitoring_components_tolerations() {
    local tolerations_file="$TOLERATIONS_FILE_PATH"

    if [ -z "$tolerations_file" ]; then
        log_info "No tolerations file provided, skipping component patching"
        return 0
    fi

    log_info "Patching monitoring components with tolerations and nodeSelector from Kubernetes API..."

    # Extract tolerations in JSON format for kubectl patch
    local tolerations_json=""
    local node_exporter_tolerations_json=""
    local node_selector_json=""

    if [ "$USE_YQ" = true ]; then
        # Use yq to convert YAML to JSON
        tolerations_json=$(yq eval '.tolerations' "$tolerations_file" -o=json 2>/dev/null)
        if [ "$tolerations_json" = "null" ] || [ -z "$tolerations_json" ]; then
            log_warn "No tolerations found in file"
            tolerations_json=""
        fi

        # Check for special nodeExporterTolerations
        node_exporter_tolerations_json=$(yq eval '.nodeExporterTolerations' "$tolerations_file" -o=json 2>/dev/null)
        if [ "$node_exporter_tolerations_json" = "null" ] || [ -z "$node_exporter_tolerations_json" ]; then
            # Default: operator Exists (run on all nodes)
            node_exporter_tolerations_json='[{"operator":"Exists"}]'
        fi

        # Extract nodeSelector
        node_selector_json=$(yq eval '.nodeSelector' "$tolerations_file" -o=json 2>/dev/null)
        if [ "$node_selector_json" = "null" ] || [ -z "$node_selector_json" ]; then
            node_selector_json=""
        fi
    else
        # Awk fallback - build JSON manually
        log_warn "Using awk fallback to build JSON patch"

        local temp_file=$(mktemp)
        awk '/^tolerations:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && NF' "$tolerations_file" > "$temp_file"

        if [ -s "$temp_file" ]; then
            # Build JSON array from YAML tolerations
            tolerations_json="["
            local first=true
            local current_obj=""

            while IFS= read -r line; do
                if echo "$line" | grep -q "^  - key:"; then
                    # Start of new toleration object
                    if [ "$first" = false ]; then
                        tolerations_json="${tolerations_json},"
                    fi
                    first=false
                    local key=$(echo "$line" | sed -E 's/.*key: *"?([^"]*)"?.*/\1/')
                    current_obj="{\"key\":\"$key\""
                elif echo "$line" | grep -q "operator:"; then
                    local op=$(echo "$line" | sed -E 's/.*operator: *"?([^"]*)"?.*/\1/')
                    current_obj="${current_obj},\"operator\":\"$op\""
                elif echo "$line" | grep -q "value:"; then
                    local val=$(echo "$line" | sed -E 's/.*value: *"?([^"]*)"?.*/\1/')
                    current_obj="${current_obj},\"value\":\"$val\""
                elif echo "$line" | grep -q "effect:"; then
                    local eff=$(echo "$line" | sed -E 's/.*effect: *"?([^"]*)"?.*/\1/')
                    current_obj="${current_obj},\"effect\":\"$eff\"}"
                    tolerations_json="${tolerations_json}${current_obj}"
                fi
            done < "$temp_file"

            tolerations_json="${tolerations_json}]"
        fi
        rm -f "$temp_file"

        # Check for nodeExporterTolerations
        local ne_temp_file=$(mktemp)
        awk '/^nodeExporterTolerations:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && NF' "$tolerations_file" > "$ne_temp_file"

        if [ -s "$ne_temp_file" ]; then
            # Build JSON for node-exporter tolerations
            node_exporter_tolerations_json="["
            local first=true
            local current_obj=""

            while IFS= read -r line; do
                if echo "$line" | grep -q "^  - "; then
                    if [ "$first" = false ]; then
                        node_exporter_tolerations_json="${node_exporter_tolerations_json},"
                    fi
                    first=false

                    if echo "$line" | grep -q "operator:"; then
                        local op=$(echo "$line" | sed -E 's/.*operator: *"?([^"]*)"?.*/\1/')
                        node_exporter_tolerations_json="${node_exporter_tolerations_json}{\"operator\":\"$op\"}"
                    fi
                fi
            done < "$ne_temp_file"
            node_exporter_tolerations_json="${node_exporter_tolerations_json}]"
        else
            # Default: operator Exists
            node_exporter_tolerations_json='[{"operator":"Exists"}]'
        fi
        rm -f "$ne_temp_file"

        # Extract nodeSelector
        local ns_temp_file=$(mktemp)
        awk '/^nodeSelector:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag && NF && !/^#/' "$tolerations_file" > "$ns_temp_file"

        if [ -s "$ns_temp_file" ]; then
            node_selector_json="{"
            local first=true
            while IFS= read -r line; do
                if echo "$line" | grep -q ":"; then
                    local key=$(echo "$line" | sed -E 's/^ *([^:]+):.*/\1/' | tr -d '"')
                    local value=$(echo "$line" | sed -E 's/.*: *"?([^"]*)"?.*/\1/')

                    if [ "$first" = false ]; then
                        node_selector_json="${node_selector_json},"
                    fi
                    first=false
                    node_selector_json="${node_selector_json}\"$key\":\"$value\""
                fi
            done < "$ns_temp_file"
            node_selector_json="${node_selector_json}}"
        fi
        rm -f "$ns_temp_file"
    fi

    [ -n "$tolerations_json" ] && log_info "Tolerations JSON: $tolerations_json"
    [ -n "$node_selector_json" ] && log_info "NodeSelector JSON: $node_selector_json"
    [ -n "$node_exporter_tolerations_json" ] && log_info "NodeExporter Tolerations JSON: $node_exporter_tolerations_json"

    # Wait for resources to be created by Helm
    log_info "Waiting for monitoring resources to be created..."
    sleep 5

    # Patch kube-state-metrics Deployment
    if [ -n "$tolerations_json" ] || [ -n "$node_selector_json" ]; then
        log_info "Patching kube-state-metrics Deployment..."
        if kubectl get deployment last9-k8s-monitoring-kube-state-metrics -n "$NAMESPACE" &>/dev/null; then
            if [ -n "$tolerations_json" ]; then
                kubectl patch deployment last9-k8s-monitoring-kube-state-metrics -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/tolerations\", \"value\": $tolerations_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            if [ -n "$node_selector_json" ]; then
                kubectl patch deployment last9-k8s-monitoring-kube-state-metrics -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/nodeSelector\", \"value\": $node_selector_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            log_info "✓ kube-state-metrics Deployment patched"
        else
            log_warn "kube-state-metrics Deployment not found, skipping"
        fi
    fi

    # Patch PrometheusAgent CRD
    if [ -n "$tolerations_json" ] || [ -n "$node_selector_json" ]; then
        log_info "Patching PrometheusAgent CRD..."
        if kubectl get prometheusagent last9-k8s-monitoring-kube-prometheus -n "$NAMESPACE" &>/dev/null; then
            if [ -n "$tolerations_json" ]; then
                kubectl patch prometheusagent last9-k8s-monitoring-kube-prometheus -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/tolerations\", \"value\": $tolerations_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            if [ -n "$node_selector_json" ]; then
                kubectl patch prometheusagent last9-k8s-monitoring-kube-prometheus -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/nodeSelector\", \"value\": $node_selector_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            log_info "✓ PrometheusAgent CRD patched"
        else
            log_warn "PrometheusAgent CRD not found, skipping"
        fi
    fi

    # Patch Prometheus Operator Deployment
    if [ -n "$tolerations_json" ] || [ -n "$node_selector_json" ]; then
        log_info "Patching Prometheus Operator Deployment..."
        if kubectl get deployment last9-k8s-monitoring-kube-prom-operator -n "$NAMESPACE" &>/dev/null; then
            if [ -n "$tolerations_json" ]; then
                kubectl patch deployment last9-k8s-monitoring-kube-prom-operator -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/tolerations\", \"value\": $tolerations_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            if [ -n "$node_selector_json" ]; then
                kubectl patch deployment last9-k8s-monitoring-kube-prom-operator -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/nodeSelector\", \"value\": $node_selector_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            log_info "✓ Prometheus Operator Deployment patched"
        else
            log_warn "Prometheus Operator Deployment not found, skipping"
        fi
    fi

    # Patch kube-operator Deployment
    if [ -n "$tolerations_json" ] || [ -n "$node_selector_json" ]; then
        log_info "Patching kube-operator Deployment..."
        if kubectl get deployment last9-k8s-monitoring-kube-operator -n "$NAMESPACE" &>/dev/null; then
            if [ -n "$tolerations_json" ]; then
                kubectl patch deployment last9-k8s-monitoring-kube-operator -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/tolerations\", \"value\": $tolerations_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            if [ -n "$node_selector_json" ]; then
                kubectl patch deployment last9-k8s-monitoring-kube-operator -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/nodeSelector\", \"value\": $node_selector_json}]" 2>&1 | grep -v "Warning:" || true
            fi
            log_info "✓ kube-operator Deployment patched"
        else
            log_warn "kube-operator Deployment not found, skipping"
        fi
    fi

    # Patch node-exporter DaemonSet with special tolerations
    if [ -n "$node_exporter_tolerations_json" ]; then
        log_info "Patching node-exporter DaemonSet with permissive tolerations..."
        if kubectl get daemonset last9-k8s-monitoring-prometheus-node-exporter -n "$NAMESPACE" &>/dev/null; then
            kubectl patch daemonset last9-k8s-monitoring-prometheus-node-exporter -n "$NAMESPACE" --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/tolerations\", \"value\": $node_exporter_tolerations_json}]" 2>&1 | grep -v "Warning:" || true
            log_info "✓ node-exporter DaemonSet patched"
        else
            log_warn "node-exporter DaemonSet not found, skipping"
        fi
    fi

    # Wait for pods to be recreated and ready
    log_info "Waiting for monitoring pods to be ready..."
    sleep 10

    # Check pod status
    log_info "Monitoring pod status:"
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=kube-state-metrics" 2>/dev/null || true
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=prometheus" 2>/dev/null || true
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=prometheus-node-exporter" 2>/dev/null || true

    log_info "✓ Monitoring components patched with tolerations and nodeSelector"
}

# Parse named arguments
parse_arguments() {
    for arg in "$@"; do
        case $arg in
            monitoring-only)
                MONITORING_ONLY=true
                ;;
            events-only)
                EVENTS_ONLY=true
                ;;
            logs-only)
                LOGS_ONLY=true
                ;;
            operator-only)
                OPERATOR_ONLY=true
                ;;
            uninstall)
                UNINSTALL_MODE=true
                ;;
            uninstall-all)
                UNINSTALL_MODE=true
                FUNCTION_TO_EXECUTE="uninstall_all"
                ;;
            token=*)
                AUTH_TOKEN="${arg#*=}"
                ;;
            endpoint=*)
                OTEL_ENDPOINT="${arg#*=}"
                ;;
            monitoring-endpoint=*)
                MONITORING_ENDPOINT="${arg#*=}"
                ;;
            repo=*)
                REPO_URL="${arg#*=}"
                ;;
            function=*)
                FUNCTION_TO_EXECUTE="${arg#*=}"
                ;;
            values=*)
                VALUES_FILE="${arg#*=}"
                ;;
            monitoring=*)
                if [ "${arg#*=}" = "false" ]; then
                    SETUP_MONITORING=false
                else
                    SETUP_MONITORING=true
                    CLUSTER_NAME="${arg#*=}"
                fi
                ;;
            cluster=*)
                CLUSTER_NAME="${arg#*=}"
                ;;
            username=*)
                LAST9_USERNAME="${arg#*=}"
                ;;
            password=*)
                LAST9_PASSWORD="${arg#*=}"
                ;;
            tolerations-file=*)
                TOLERATIONS_FILE="${arg#*=}"

                # Validate tolerations file path immediately
                if [ -z "$TOLERATIONS_FILE" ]; then
                    log_error "tolerations-file argument is empty. Please provide an absolute path to the tolerations YAML file."
                    log_error "Example: tolerations-file=/absolute/path/to/tolerations.yaml"
                    exit 1
                fi

                # Check if path is absolute (starts with /)
                if [[ ! "$TOLERATIONS_FILE" =~ ^/ ]]; then
                    log_error "tolerations-file must be an absolute path (starting with /)"
                    log_error "Provided: $TOLERATIONS_FILE"
                    log_error "Example: tolerations-file=/home/user/tolerations.yaml"
                    exit 1
                fi

                # Check if file exists
                if [ ! -f "$TOLERATIONS_FILE" ]; then
                    log_error "Tolerations file not found at: $TOLERATIONS_FILE"
                    log_error "Please verify the file path and try again."
                    exit 1
                fi

                # Check if file is readable
                if [ ! -r "$TOLERATIONS_FILE" ]; then
                    log_error "Tolerations file is not readable: $TOLERATIONS_FILE"
                    log_error "Please check file permissions and try again."
                    exit 1
                fi

                log_info "✓ Tolerations file validated: $TOLERATIONS_FILE"
                ;;
            env=*)
                DEPLOYMENT_ENV="${arg#*=}"
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
    echo "  $0 token=\"your-token-here\" endpoint=\"your-otel-endpoint\" monitoring-endpoint=\"your-monitoring-endpoint\" username=\"my-user\" password=\"my-pass\"  # For All Sources(Logs, Traces, Metrics and Events) use this option"
    echo "  $0 operator-only token=\"your-token-here\" endpoint=\"your-otel-endpoint\"  # For Traces - Install OpenTelemetry Operator and Collector"
    echo "  $0 logs-only token=\"your-token-here\" endpoint=\"your-otel-endpoint\"  # For Logs - Install only Collector for logs (no operator)"
    echo "  $0 monitoring-only monitoring-endpoint=\"your-monitoring-endpoint\" username=\"user\" password=\"pass\"  # For Metrics - Install only monitoring"
    echo "  $0 events-only  # For Events - Install only Kubernetes Events Agent"
    echo "  $0 uninstall-all  # Use to Uninstall any components installed previously"
    echo ""
    echo "With Environment and Cluster Override:"
    echo "  $0 token=\"xxx\" endpoint=\"xxx\" env=production cluster=prod-us-east-1  # Set environment and cluster name"
    echo "  $0 token=\"xxx\" endpoint=\"xxx\" env=staging cluster=staging-cluster    # Set environment and cluster name"
    echo ""
    echo "With Tolerations and NodeSelector:"
    echo "  $0 tolerations-file=examples/tolerations-monitoring-nodes.yaml token=\"xxx\" endpoint=\"xxx\" ...  # Run on monitoring nodes"
    echo "  $0 tolerations-file=examples/tolerations-all-nodes.yaml operator-only token=\"xxx\" endpoint=\"xxx\"  # Operator on all nodes including control-plane"
    echo ""
    echo "See examples/ directory for more tolerations configurations"
    echo ""
}

# Show help function
show_help() {
    echo "OpenTelemetry Setup Automation Script"
    echo ""
    echo "Usage:"
    echo "  $0 token=\"your-token-here\" endpoint=\"your-otel-endpoint\" monitoring-endpoint=\"your-monitoring-endpoint\" username=\"my-user\" password=\"my-pass\"  # For All Sources(Logs, Traces, Metrics and Events) use this option"
    echo "  $0 operator-only token=\"your-token-here\" endpoint=\"your-otel-endpoint\"  # For Traces - Install OpenTelemetry Operator and Collector"
    echo "  $0 logs-only token=\"your-token-here\" endpoint=\"your-otel-endpoint\"  # For Logs - Install only Collector for logs (no operator)"
    echo "  $0 monitoring-only monitoring-endpoint=\"your-monitoring-endpoint\" username=\"user\" password=\"pass\"  # For Metrics - Install only monitoring"
    echo "  $0 events-only  # For Events - Install only Kubernetes Events Agent"
    echo "  $0 uninstall-all  # Use to Uninstall any components installed previously"
    echo ""
    echo "Advanced Options:"
    echo "  env=ENVIRONMENT          Override deployment.environment attribute (e.g., production, staging, dev)"
    echo "                           Updates both collector and auto-instrumentation configurations"
    echo "                           Default: 'staging' for collector, 'local' for instrumentation"
    echo ""
    echo "  cluster=CLUSTER_NAME     Set cluster.name attribute for telemetry data"
    echo "                           If not provided, automatically detected from kubectl current-context"
    echo "                           Example: cluster=prod-us-east-1"
    echo ""
    echo "  tolerations-file=FILE    Apply Kubernetes tolerations and nodeSelector from YAML file"
    echo "                           Allows running components on tainted nodes (e.g., monitoring nodes, control-plane)"
    echo "                           See examples/ directory for sample configurations"
    echo ""
    echo "Examples with Environment and Cluster Override:"
    echo "  # Set environment to production with cluster name"
    echo "  $0 token=\"xxx\" endpoint=\"xxx\" env=production cluster=prod-us-east-1"
    echo ""
    echo "  # Set environment to staging with auto-detected cluster name"
    echo "  $0 operator-only token=\"xxx\" endpoint=\"xxx\" env=staging"
    echo ""
    echo "  # Use custom cluster name only (environment will use default)"
    echo "  $0 token=\"xxx\" endpoint=\"xxx\" cluster=my-k8s-cluster"
    echo ""
    echo "Examples with Tolerations:"
    echo "  # Run on dedicated monitoring nodes"
    echo "  $0 tolerations-file=tolerations.yaml token=\"xxx\" endpoint=\"xxx\" ..."
    echo ""
    echo "  # Run on all nodes including control-plane/master"
    echo "  $0 tolerations-file=examples/tolerations-all-nodes.yaml operator-only token=\"xxx\" endpoint=\"xxx\""
    echo ""
    echo "  # Run on spot/preemptible instances"
    echo "  $0 tolerations-file=examples/tolerations-spot-instances.yaml monitoring-only monitoring-endpoint=\"xxx\" ..."
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Skip token check for uninstall mode, logs-only mode, monitoring-only mode, and events-only mode
    # Note: operator-only mode will check for token later in its specific section
    if [ "$UNINSTALL_MODE" = false ] && [ "$LOGS_ONLY" = false ] && [ "$MONITORING_ONLY" = false ] && [ "$EVENTS_ONLY" = false ] && [ "$OPERATOR_ONLY" = false ] && [ -z "$AUTH_TOKEN" ]; then
        log_error "Auth token is required for installation."
        echo ""
        show_help
        exit 1
    fi

    # Check if endpoint is provided for non-monitoring and non-events modes
    if [ "$UNINSTALL_MODE" = false ] && [ "$MONITORING_ONLY" = false ] && [ "$EVENTS_ONLY" = false ] && [ -z "$OTEL_ENDPOINT" ]; then
        log_error "OTEL endpoint is required for installation."
        log_error "Please provide endpoint=<your-otel-endpoint> parameter."
        echo ""
        show_help
        exit 1
    fi
    
    # Check if monitoring endpoint is provided for modes that include monitoring
    if [ "$UNINSTALL_MODE" = false ] && [ "$MONITORING_ONLY" = true ] && [ -z "$MONITORING_ENDPOINT" ]; then
        log_error "Monitoring endpoint is required for monitoring installation."
        log_error "Please provide monitoring-endpoint=<your-monitoring-endpoint> parameter."
        echo ""
        show_help
        exit 1
    fi
    
    # Check if monitoring endpoint is provided for all sources mode (which includes monitoring)
    if [ "$UNINSTALL_MODE" = false ] && [ "$MONITORING_ONLY" = false ] && [ "$OPERATOR_ONLY" = false ] && [ "$LOGS_ONLY" = false ] && [ "$SETUP_MONITORING" = true ] && [ -z "$MONITORING_ENDPOINT" ]; then
        log_error "Monitoring endpoint is required for all sources installation (includes monitoring)."
        log_error "Please provide monitoring-endpoint=<your-monitoring-endpoint> parameter."
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
            log_info "Using OTEL endpoint: ${OTEL_ENDPOINT:0:30}..."  # Show only first 30 chars for security
            log_info "Using repository: $REPO_URL"
        elif [ "$MONITORING_ONLY" = true ]; then
            log_info "Running in monitoring-only mode"
            log_info "Using monitoring endpoint: ${MONITORING_ENDPOINT:0:30}..."  # Show only first 30 chars for security
        else
            log_info "Using auth token: ${AUTH_TOKEN:0:10}..."  # Show only first 10 chars for security
            log_info "Using OTEL endpoint: ${OTEL_ENDPOINT:0:30}..."  # Show only first 30 chars for security
            if [ "$SETUP_MONITORING" = true ] && [ -n "$MONITORING_ENDPOINT" ]; then
                log_info "Using monitoring endpoint: ${MONITORING_ENDPOINT:0:30}..."  # Show only first 30 chars for security
            fi
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

    # Clone repository with sparse checkout for only otel-collector/otel-operator
    log_info "Cloning repository with sparse checkout (otel-collector/otel-operator only): $REPO_URL"

    # Check if URL contains branch specification (format: url#branch)
    if [[ "$REPO_URL" == *"#"* ]]; then
       # Split URL and branch
       ACTUAL_URL="${REPO_URL%#*}"
       BRANCH="${REPO_URL#*#}"
       log_info "Cloning branch '$BRANCH' from: $ACTUAL_URL"

       # Initialize git repository
       git init
       git remote add origin "$ACTUAL_URL"
       git config core.sparseCheckout true
       echo "otel-collector/otel-operator/" > .git/info/sparse-checkout
       git pull origin "$BRANCH"
    else
      # Clone default branch
      log_info "Cloning default branch from: $REPO_URL"

      # Initialize git repository
      git init
      git remote add origin "$REPO_URL"
      git config core.sparseCheckout true
      echo "otel-collector/otel-operator/" > .git/info/sparse-checkout
      git pull origin main
    fi


    # Navigate to the correct directory
    if [ -d "otel-collector/otel-operator" ]; then
        cd otel-collector/otel-operator
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

    # Update auth token and endpoint in the values file
    update_auth_token
    update_otel_endpoint

    # Update deployment environment if provided
    if [ -n "$DEPLOYMENT_ENV" ]; then
        update_deployment_environment "$DEPLOYMENT_ENV"
    fi

    # Add cluster name attribute to collector values
    update_cluster_name_attribute

    # Load and apply tolerations if provided
    if [ -n "$TOLERATIONS_FILE" ]; then
        load_tolerations_from_file "$TOLERATIONS_FILE"
        apply_tolerations_to_collector_values "last9-otel-collector-values.yaml"
    fi
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
        escaped_token=$(escape_for_sed "$AUTH_TOKEN")
        sed -i.tmp "s|{{AUTH_TOKEN}}|$escaped_token|g" last9-otel-collector-values.yaml
    elif grep -q '${AUTH_TOKEN}' last9-otel-collector-values.yaml; then
        log_info "Found \${AUTH_TOKEN} placeholder"
        escaped_token=$(escape_for_sed "$AUTH_TOKEN")
        sed -i.tmp "s|\${AUTH_TOKEN}|$escaped_token|g" last9-otel-collector-values.yaml
    elif grep -q '{{ \.Values\.authToken }}' last9-otel-collector-values.yaml; then
        log_info "Found Helm template placeholder"
        escaped_token=$(escape_for_sed "$AUTH_TOKEN")
        sed -i.tmp "s|{{ \.Values\.authToken }}|$escaped_token|g" last9-otel-collector-values.yaml
    else
        log_warn "⚠ No auth token placeholder found in the file."
        log_warn "Assuming credentials are already configured in the YAML file."
        log_warn "Skipping token replacement..."
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

# Function to update OTEL endpoint in values file
update_otel_endpoint() {
    log_info "Updating OTEL endpoint placeholder in last9-otel-collector-values.yaml..."
    
    # Check if the values file exists
    if [ ! -f "last9-otel-collector-values.yaml" ]; then
        log_error "last9-otel-collector-values.yaml not found!"
        exit 1
    fi
    
    # Create backup of original file (if not already created by update_auth_token)
    if [ ! -f "last9-otel-collector-values.yaml.backup" ]; then
        cp last9-otel-collector-values.yaml last9-otel-collector-values.yaml.backup
        log_info "Created backup: last9-otel-collector-values.yaml.backup"
    fi
    
    # Replace placeholder with actual endpoint
    log_info "Using OTEL endpoint: ${OTEL_ENDPOINT:0:30}..."
    
    # Handle multiple placeholder formats
    if grep -q '{{YOUR_OTEL_ENDPOINT}}' last9-otel-collector-values.yaml; then
        log_info "Found {{YOUR_OTEL_ENDPOINT}} placeholder"
        escaped_endpoint=$(escape_for_sed "$OTEL_ENDPOINT")
        sed -i.tmp "s|{{YOUR_OTEL_ENDPOINT}}|$escaped_endpoint|g" last9-otel-collector-values.yaml
    elif grep -q '{{OTEL_ENDPOINT}}' last9-otel-collector-values.yaml; then
        log_info "Found {{OTEL_ENDPOINT}} placeholder"
        escaped_endpoint=$(escape_for_sed "$OTEL_ENDPOINT")
        sed -i.tmp "s|{{OTEL_ENDPOINT}}|$escaped_endpoint|g" last9-otel-collector-values.yaml
    elif grep -q '\${OTEL_ENDPOINT}' last9-otel-collector-values.yaml; then
        log_info "Found \${OTEL_ENDPOINT} placeholder"
        escaped_endpoint=$(escape_for_sed "$OTEL_ENDPOINT")
        sed -i.tmp "s|\${OTEL_ENDPOINT}|$escaped_endpoint|g" last9-otel-collector-values.yaml
    elif grep -q 'https://<your_last9_endpoint>' last9-otel-collector-values.yaml; then
        log_info "Found old format https://<your_last9_endpoint> placeholder"
        escaped_endpoint=$(escape_for_sed "$OTEL_ENDPOINT")
        sed -i.tmp "s|https://<your_last9_endpoint>|$escaped_endpoint|g" last9-otel-collector-values.yaml
    else
        log_warn "⚠ No OTEL endpoint placeholder found in the file."
        log_warn "Assuming endpoint is already configured in the YAML file."
        log_warn "Skipping endpoint replacement..."
    fi
    
    # Remove the temporary file created by sed -i
    rm -f last9-otel-collector-values.yaml.tmp
    
    # Verify the change was made
    if grep -q "$OTEL_ENDPOINT" last9-otel-collector-values.yaml && ! grep -q -E '(\{\{|\$\{).*OTEL_ENDPOINT.*(\}\}|\})' last9-otel-collector-values.yaml; then
        log_info "✓ OTEL endpoint placeholder replaced successfully!"
    else
        log_warn "⚠ Could not verify endpoint replacement. Please check the file manually."
    fi
}

# Function to update deployment environment in configuration files
update_deployment_environment() {
    local env="$1"

    if [ -z "$env" ]; then
        log_info "No deployment environment specified, using default values"
        return 0
    fi

    log_info "Setting deployment.environment to: $env"

    # Update collector values file (last9-otel-collector-values.yaml)
    if [ -f "last9-otel-collector-values.yaml" ]; then
        log_info "Updating deployment.environment in collector values file..."

        # Replace deployment.environment value in the set(attributes[...]) line
        sed -i.tmp "s/deployment\.environment\"], \"[^\"]*\"/deployment.environment\"], \"$env\"/" last9-otel-collector-values.yaml
        rm -f last9-otel-collector-values.yaml.tmp

        # Verify the change
        if grep -q "deployment.environment\"], \"$env\"" last9-otel-collector-values.yaml; then
            log_info "✓ Updated deployment.environment=$env in collector values file"
        else
            log_warn "⚠ Could not verify deployment.environment update in collector values file"
        fi
    else
        log_warn "⚠ last9-otel-collector-values.yaml not found, skipping collector environment update"
    fi

    # Update instrumentation file (instrumentation.yaml)
    if [ -f "instrumentation.yaml" ]; then
        log_info "Updating deployment.environment in instrumentation file..."

        # Replace deployment.environment=<value> in all occurrences
        sed -i.tmp "s/deployment\.environment=[^ \"]*/deployment.environment=$env/g" instrumentation.yaml
        rm -f instrumentation.yaml.tmp

        # Verify the change
        if grep -q "deployment.environment=$env" instrumentation.yaml; then
            log_info "✓ Updated deployment.environment=$env in instrumentation file"
        else
            log_warn "⚠ Could not verify deployment.environment update in instrumentation file"
        fi
    else
        log_warn "⚠ instrumentation.yaml not found, skipping instrumentation environment update"
    fi

    log_info "✓ Deployment environment configuration completed"
}

# Function to add cluster name attribute to collector values file
update_cluster_name_attribute() {
    log_info "Adding cluster name attribute to collector values file..."

    # Detect cluster name from kubectl context
    local cluster_name="${CLUSTER_NAME}"

    if [ -z "$cluster_name" ]; then
        log_info "Cluster name not provided, attempting to detect from kubectl..."
        cluster_name=$(kubectl config current-context 2>/dev/null || echo "unknown-cluster")
        log_info "Detected cluster name: $cluster_name"
    else
        log_info "Using provided cluster name: $cluster_name"
    fi

    # Update collector values file (last9-otel-collector-values.yaml)
    if [ -f "last9-otel-collector-values.yaml" ]; then
        # Check if cluster.name attribute already exists
        if grep -q "cluster\.name" last9-otel-collector-values.yaml; then
            log_info "cluster.name attribute already exists, updating value..."
            sed -i.tmp "s/cluster\.name\"], \"[^\"]*\"/cluster.name\"], \"$cluster_name\"/" last9-otel-collector-values.yaml
            rm -f last9-otel-collector-values.yaml.tmp
        else
            log_info "Adding cluster.name attribute after deployment.environment..."
            # Add the cluster.name attribute right after deployment.environment line
            # Using awk to insert a new line after the deployment.environment line
            awk -v cluster="$cluster_name" '
            /set\(attributes\["deployment\.environment"\]/ {
                print
                # Match the indentation of the previous line
                match($0, /^[[:space:]]*/);
                indent = substr($0, RSTART, RLENGTH);
                print indent "- set(attributes[\"cluster.name\"], \"" cluster "\")"
                next
            }
            {print}
            ' last9-otel-collector-values.yaml > last9-otel-collector-values.yaml.tmp
            mv last9-otel-collector-values.yaml.tmp last9-otel-collector-values.yaml
        fi

        # Verify the change
        if grep -q "cluster.name\"], \"$cluster_name\"" last9-otel-collector-values.yaml; then
            log_info "✓ Added/updated cluster.name=$cluster_name in collector values file"
        else
            log_warn "⚠ Could not verify cluster.name addition in collector values file"
        fi
    else
        log_warn "⚠ last9-otel-collector-values.yaml not found, skipping cluster name update"
    fi

    log_info "✓ Cluster name attribute configuration completed"
}

# Function to add cluster name attribute to events agent values file
update_events_agent_cluster_name() {
    log_info "Adding cluster name attribute to events agent values file..."

    # Detect cluster name from kubectl context
    local cluster_name="${CLUSTER_NAME}"

    if [ -z "$cluster_name" ]; then
        log_info "Cluster name not provided, attempting to detect from kubectl..."
        cluster_name=$(kubectl config current-context 2>/dev/null || echo "unknown-cluster")
        log_info "Detected cluster name: $cluster_name"
    else
        log_info "Using provided cluster name: $cluster_name"
    fi

    # Update events agent values file (last9-kube-events-agent-values.yaml)
    if [ -f "last9-kube-events-agent-values.yaml" ]; then
        # Check if cluster.name attribute already exists
        if grep -q "cluster\.name" last9-kube-events-agent-values.yaml; then
            log_info "cluster.name attribute already exists, updating value..."
            sed -i.tmp "s/cluster\.name\"], \"[^\"]*\"/cluster.name\"], \"$cluster_name\"/" last9-kube-events-agent-values.yaml
            rm -f last9-kube-events-agent-values.yaml.tmp
        else
            log_info "Adding cluster.name attribute after deployment.environment..."
            # Add the cluster.name attribute right after deployment.environment line
            # Using awk to insert a new line after the deployment.environment line
            awk -v cluster="$cluster_name" '
            /set\(resource\.attributes\["deployment\.environment"\]/ {
                print
                # Match the indentation of the previous line
                match($0, /^[[:space:]]*/);
                indent = substr($0, RSTART, RLENGTH);
                print indent "- set(resource.attributes[\"cluster.name\"], \"" cluster "\")"
                next
            }
            {print}
            ' last9-kube-events-agent-values.yaml > last9-kube-events-agent-values.yaml.tmp
            mv last9-kube-events-agent-values.yaml.tmp last9-kube-events-agent-values.yaml
        fi

        # Verify the change
        if grep -q "cluster.name\"], \"$cluster_name\"" last9-kube-events-agent-values.yaml; then
            log_info "✓ Added/updated cluster.name=$cluster_name in events agent values file"
        else
            log_warn "⚠ Could not verify cluster.name addition in events agent values file"
        fi
    else
        log_warn "⚠ last9-kube-events-agent-values.yaml not found, skipping cluster name update"
    fi

    log_info "✓ Events agent cluster name attribute configuration completed"
}

# Function to update monitoring endpoint in values file
update_monitoring_endpoint() {
    log_info "Updating monitoring endpoint placeholder in k8s-monitoring-values.yaml..."
    
    # Check if the values file exists
    if [ ! -f "k8s-monitoring-values.yaml" ]; then
        log_error "k8s-monitoring-values.yaml not found!"
        exit 1
    fi
    
    # Create backup of original file (if not already created)
    if [ ! -f "k8s-monitoring-values.yaml.backup" ]; then
        cp k8s-monitoring-values.yaml k8s-monitoring-values.yaml.backup
        log_info "Created backup: k8s-monitoring-values.yaml.backup"
    fi
    
    # Replace placeholder with actual endpoint
    log_info "Using monitoring endpoint: ${MONITORING_ENDPOINT:0:30}..."
    
    # Handle multiple placeholder formats
    if grep -q '{{YOUR_MONITORING_ENDPOINT}}' k8s-monitoring-values.yaml; then
        log_info "Found {{YOUR_MONITORING_ENDPOINT}} placeholder"
        escaped_endpoint=$(escape_for_sed "$MONITORING_ENDPOINT")
        sed -i.tmp "s|{{YOUR_MONITORING_ENDPOINT}}|$escaped_endpoint|g" k8s-monitoring-values.yaml
    elif grep -q '{{MONITORING_ENDPOINT}}' k8s-monitoring-values.yaml; then
        log_info "Found {{MONITORING_ENDPOINT}} placeholder"
        escaped_endpoint=$(escape_for_sed "$MONITORING_ENDPOINT")
        sed -i.tmp "s|{{MONITORING_ENDPOINT}}|$escaped_endpoint|g" k8s-monitoring-values.yaml
    elif grep -q '\${MONITORING_ENDPOINT}' k8s-monitoring-values.yaml; then
        log_info "Found \${MONITORING_ENDPOINT} placeholder"
        escaped_endpoint=$(escape_for_sed "$MONITORING_ENDPOINT")
        sed -i.tmp "s|\${MONITORING_ENDPOINT}|$escaped_endpoint|g" k8s-monitoring-values.yaml
    elif grep -q 'https://app-tsdb.last9.io/v1/metrics/YOUR_CLUSTER_ID/sender/last9/write' k8s-monitoring-values.yaml; then
        log_info "Found old format https://app-tsdb.last9.io/v1/metrics/YOUR_CLUSTER_ID/sender/last9/write placeholder"
        escaped_endpoint=$(escape_for_sed "$MONITORING_ENDPOINT")
        sed -i.tmp "s|https://app-tsdb.last9.io/v1/metrics/YOUR_CLUSTER_ID/sender/last9/write|$escaped_endpoint|g" k8s-monitoring-values.yaml
    else
        log_error "No supported monitoring endpoint placeholder found in the file."
        log_info "Please use one of these placeholders in your YAML file:"
        echo "  - {{YOUR_MONITORING_ENDPOINT}}"
        echo "  - {{MONITORING_ENDPOINT}}"
        echo "  - \${MONITORING_ENDPOINT}"
        echo "  - https://app-tsdb.last9.io/v1/metrics/YOUR_CLUSTER_ID/sender/last9/write (old format)"
        exit 1
    fi
    
    # Remove the temporary file created by sed -i
    rm -f k8s-monitoring-values.yaml.tmp
    
    # Verify the change was made
    if grep -q "$MONITORING_ENDPOINT" k8s-monitoring-values.yaml && ! grep -q -E '(\{\{|\$\{).*MONITORING_ENDPOINT.*(\}\}|\})' k8s-monitoring-values.yaml; then
        log_info "✓ Monitoring endpoint placeholder replaced successfully!"
    else
        log_warn "⚠ Could not verify monitoring endpoint replacement. Please check the file manually."
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

    # Build helm command as array for proper argument handling
    local helm_args=(
        "upgrade" "--install"
        "opentelemetry-operator"
        "open-telemetry/opentelemetry-operator"
        "--version" "$OPERATOR_VERSION"
        "-n" "$NAMESPACE"
        "--create-namespace"
        "--set" "manager.collectorImage.repository=ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s"
        "--set" "admissionWebhooks.certManager.enabled=false"
        "--set" "admissionWebhooks.autoGenerateCert.enabled=true"
    )

    # Add tolerations and nodeSelector if provided
    if [ -n "$TOLERATIONS_FILE_PATH" ]; then
        log_info "Adding tolerations to operator installation..."

        # Note: For operator chart, tolerations and nodeSelector are at root level (no prefix)
        local tolerations_args=$(convert_tolerations_to_helm_set "$TOLERATIONS_FILE_PATH" "")
        if [ -n "$tolerations_args" ]; then
            # Parse --set arguments from tolerations_args string and add to array
            while IFS= read -r arg; do
                [ -n "$arg" ] && helm_args+=("$arg")
            done < <(echo "$tolerations_args" | xargs -n1)
            log_info "✓ Tolerations added to operator"
        fi

        local node_selector_args=$(convert_node_selector_to_helm_set "$TOLERATIONS_FILE_PATH" "")
        if [ -n "$node_selector_args" ]; then
            # Parse --set arguments from node_selector_args string and add to array
            while IFS= read -r arg; do
                [ -n "$arg" ] && helm_args+=("$arg")
            done < <(echo "$node_selector_args" | xargs -n1)
            log_info "✓ NodeSelector added to operator"
        fi
    fi

    # Execute helm command
    helm "${helm_args[@]}"

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
    log_info "Cluster name to replace: $cluster_name"
    # Use awk for more robust replacement that handles special characters better
    awk -v cluster="$cluster_name" '{gsub(/my-cluster-name/, cluster)}1' k8s-monitoring-values.yaml > k8s-monitoring-values.yaml.tmp && mv k8s-monitoring-values.yaml.tmp k8s-monitoring-values.yaml
    
    # Note: Using awk instead of sed for cluster name replacement to handle special characters
    
    # Verify the change was made
    if grep -q "cluster: $cluster_name" k8s-monitoring-values.yaml; then
        log_info "✓ Cluster name placeholder replaced successfully!"
        log_info "Updated line: $(grep 'cluster:' k8s-monitoring-values.yaml)"
    else
        log_warn "⚠ Could not verify cluster name replacement. Please check the file manually."
        log_warn "Current cluster line: $(grep 'cluster:' k8s-monitoring-values.yaml || echo 'Not found')"
    fi
    
    # Update monitoring endpoint placeholder
    update_monitoring_endpoint

    # Load tolerations if provided (needed for kubectl patching later)
    # NOTE: We skip apply_tolerations_to_monitoring_values() to avoid yq lexer issues
    # and rely on kubectl patch approach which is more reliable
    if [ -n "$TOLERATIONS_FILE" ]; then
        # Load tolerations if not already loaded
        if [ -z "$TOLERATIONS_FILE_PATH" ]; then
            load_tolerations_from_file "$TOLERATIONS_FILE"
        fi
        log_info "Tolerations will be applied via kubectl patch after Helm install"
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

    # Patch monitoring components with tolerations and nodeSelector if provided
    # This is the primary method for applying tolerations (more reliable than Helm values)
    if [ -n "$TOLERATIONS_FILE" ]; then
        patch_monitoring_components_tolerations
    fi

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

# Function to update auth token in events agent values file
update_events_agent_auth_token() {
    log_info "Updating auth token in last9-kube-events-agent-values.yaml..."

    # Check if the values file exists
    if [ ! -f "last9-kube-events-agent-values.yaml" ]; then
        log_warn "⚠ last9-kube-events-agent-values.yaml not found, skipping token update"
        return
    fi

    # Create backup of original file
    cp last9-kube-events-agent-values.yaml last9-kube-events-agent-values.yaml.backup
    log_info "Created backup: last9-kube-events-agent-values.yaml.backup"

    # Replace placeholder with actual token
    log_info "Using auth token: ${AUTH_TOKEN:0:20}..."

    # Handle multiple placeholder formats
    if grep -q '{{AUTH_TOKEN}}' last9-kube-events-agent-values.yaml; then
        log_info "Found {{AUTH_TOKEN}} placeholder"
        escaped_token=$(escape_for_sed "$AUTH_TOKEN")
        sed -i.tmp "s|{{AUTH_TOKEN}}|$escaped_token|g" last9-kube-events-agent-values.yaml
    elif grep -q '${AUTH_TOKEN}' last9-kube-events-agent-values.yaml; then
        log_info "Found \${AUTH_TOKEN} placeholder"
        escaped_token=$(escape_for_sed "$AUTH_TOKEN")
        sed -i.tmp "s|\${AUTH_TOKEN}|$escaped_token|g" last9-kube-events-agent-values.yaml
    else
        log_warn "⚠ No auth token placeholder found in events agent values file."
        log_warn "Assuming credentials are already configured."
    fi

    # Remove the temporary file created by sed -i
    rm -f last9-kube-events-agent-values.yaml.tmp
}

# Function to update OTEL endpoint in events agent values file
update_events_agent_endpoint() {
    log_info "Updating OTEL endpoint in last9-kube-events-agent-values.yaml..."

    # Check if the values file exists
    if [ ! -f "last9-kube-events-agent-values.yaml" ]; then
        log_warn "⚠ last9-kube-events-agent-values.yaml not found, skipping endpoint update"
        return
    fi

    # Replace placeholder with actual endpoint
    log_info "Using OTEL endpoint: ${OTEL_ENDPOINT:0:30}..."

    # Handle multiple placeholder formats
    if grep -q '{{OTEL_ENDPOINT}}' last9-kube-events-agent-values.yaml; then
        log_info "Found {{OTEL_ENDPOINT}} placeholder"
        escaped_endpoint=$(escape_for_sed "$OTEL_ENDPOINT")
        sed -i.tmp "s|{{OTEL_ENDPOINT}}|$escaped_endpoint|g" last9-kube-events-agent-values.yaml
    elif grep -q '\${OTEL_ENDPOINT}' last9-kube-events-agent-values.yaml; then
        log_info "Found \${OTEL_ENDPOINT} placeholder"
        escaped_endpoint=$(escape_for_sed "$OTEL_ENDPOINT")
        sed -i.tmp "s|\${OTEL_ENDPOINT}|$escaped_endpoint|g" last9-kube-events-agent-values.yaml
    else
        log_warn "⚠ No OTEL endpoint placeholder found in events agent values file."
        log_warn "Assuming endpoint is already configured."
    fi

    # Remove the temporary file created by sed -i
    rm -f last9-kube-events-agent-values.yaml.tmp
}

# Function to install Kubernetes Events Agent
install_events_agent() {
    log_info "Setting up Kubernetes Events Agent..."

    # Create the namespace first
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    log_info "✓ Namespace $NAMESPACE created/verified"

    # Check if last9-kube-events-agent-values.yaml exists
    if [ ! -f "last9-kube-events-agent-values.yaml" ]; then
        log_error "last9-kube-events-agent-values.yaml not found in current directory"
        exit 1
    fi

    # Update auth token and endpoint in events agent values file
    update_events_agent_auth_token
    update_events_agent_endpoint

    # Add cluster name attribute to events agent values file
    update_events_agent_cluster_name

    # Install/upgrade the events agent
    log_info "Installing/upgrading Last9 Kubernetes Events Agent..."
    helm upgrade --install last9-kube-events-agent open-telemetry/opentelemetry-collector \
        --version 0.125.0 \
        -n "$NAMESPACE" \
        --create-namespace \
        -f last9-kube-events-agent-values.yaml

    log_info "✓ Last9 Kubernetes Events Agent deployed successfully!"

    # Show the deployed resources
    log_info "Events agent resources in $NAMESPACE namespace:"
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=last9-kube-events-agent" 2>/dev/null || true

    log_info "🎉 Kubernetes Events Agent setup completed!"
    echo ""
    echo "Summary:"
    echo "  ✓ Deployed opentelemetry-collector for Kubernetes events"
    echo "  ✓ Added cluster.name attribute to events agent configuration"
    echo "  ✓ Events will be collected and sent to Last9"
    echo ""
    echo "To verify the deployment:"
    echo "  kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=last9-kube-events-agent"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=last9-kube-events-agent"
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

# Function to uninstall Kubernetes Events Agent
uninstall_events_agent() {
    log_info "🗑️  Starting Kubernetes Events Agent uninstallation..."

    # Ask for confirmation
    echo ""
    log_warn "This will remove the Kubernetes Events Agent"
    echo "Components to be removed:"
    echo "  - Helm chart: last9-kube-events-agent"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall cancelled."
        exit 0
    fi

    log_info "Proceeding with uninstallation..."

    # Remove the Helm chart
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "last9-kube-events-agent"; then
        log_info "Uninstalling Kubernetes Events Agent..."
        helm uninstall last9-kube-events-agent -n "$NAMESPACE" || log_warn "Failed to uninstall events agent chart"
    else
        log_info "Kubernetes Events Agent chart not found"
    fi

    # Wait for Helm resources to be cleaned up
    log_info "Waiting for Helm resources to be cleaned up..."
    sleep 5

    log_info "🎉 Kubernetes Events Agent uninstallation completed!"
    echo ""
    echo "Summary of actions taken:"
    echo "  ✓ Removed Helm chart: last9-kube-events-agent"
    echo ""
    echo "To verify cleanup, run:"
    echo "  helm list -n $NAMESPACE | grep last9-kube-events-agent  # Should return nothing"
    echo "  kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=last9-kube-events-agent  # Should return nothing"
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
    log_info "🗑️  Starting complete uninstallation (OpenTelemetry + Monitoring + Events)..."

    # Ask for confirmation
    echo ""
    log_warn "This will remove ALL components installed by this script"
    echo "Components to be removed:"
    echo "  - OpenTelemetry components (operator, collector, instrumentation)"
    echo "  - Last9 monitoring stack (kube-prometheus-stack)"
    echo "  - Kubernetes Events Agent"
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

    # Then uninstall Kubernetes Events Agent
    log_info "Step 2: Uninstalling Kubernetes Events Agent..."
    uninstall_events_agent

    # Finally uninstall OpenTelemetry components
    log_info "Step 3: Uninstalling OpenTelemetry components..."
    uninstall_opentelemetry

    log_info "🎉 Complete uninstallation finished!"
    echo ""
    echo "All components have been removed successfully!"
}

# Function to cleanup temporary files
cleanup() {
    # Always cleanup temporary files unless it's an uninstall operation
    if [ "$UNINSTALL_MODE" = false ] && [ -n "$WORK_DIR" ]; then
        log_info "Cleaning up temporary files..."
        # Go back to the original directory where script was executed
        cd "$ORIGINAL_DIR" 2>/dev/null || cd /tmp

        # Remove the work directory if it exists
        if [ -d "$WORK_DIR" ]; then
            rm -rf "$WORK_DIR"
            log_info "✓ Temporary directory '$WORK_DIR' removed"
        fi
    fi

    # Always cleanup all otel-setup-* directories from where script was run
    # Make sure we're in the original directory
    cd "$ORIGINAL_DIR" 2>/dev/null || true

    if ls otel-setup-* 1> /dev/null 2>&1; then
        log_info "Cleaning up all otel-setup-* directories..."
        rm -rf otel-setup-*
        log_info "✓ All otel-setup-* directories removed"
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
            uninstall_events_agent)
                log_info "Running events agent uninstall..."
                uninstall_events_agent
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
                
                if [ -z "$OTEL_ENDPOINT" ]; then
                    log_error "OTEL endpoint is required for install_collector function"
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
            install_events_agent)
                setup_helm_repos
                install_events_agent
                ;;
            uninstall_last9_monitoring)
                uninstall_last9_monitoring
                ;;
            uninstall_events_agent)
                uninstall_events_agent
                ;;
            uninstall_all)
                uninstall_all
                ;;
            *)
                log_error "Unknown function: $FUNCTION_TO_EXECUTE"
                echo "Available functions: setup_helm_repos, install_operator, install_collector, create_collector_service, create_instrumentation, verify_installation, setup_last9_monitoring, install_events_agent, uninstall_last9_monitoring, uninstall_events_agent, uninstall_all"
                exit 1
                ;;
        esac
        
        # Cleanup for individual functions
        cleanup
        
        log_info "✅ Function '$FUNCTION_TO_EXECUTE' completed successfully!"
    elif [ "$MONITORING_ONLY" = true ]; then
        # Install only Cluster Monitoring (Prometheus stack)
        log_info "Starting Cluster Monitoring installation..."
        
        # Check if credentials and monitoring endpoint are provided
        if [ -z "$LAST9_USERNAME" ] || [ -z "$LAST9_PASSWORD" ]; then
            log_error "Last9 credentials are required for monitoring setup."
            log_error "Please provide username=<value> and password=<value> parameters."
            exit 1
        fi
        
        if [ -z "$MONITORING_ENDPOINT" ]; then
            log_error "Monitoring endpoint is required for monitoring setup."
            log_error "Please provide monitoring-endpoint=<value> parameter."
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
        echo "To add OpenTelemetry later, run: $0 token=\"your-token\" endpoint=\"your-otel-endpoint\""
        echo "To uninstall later, run: $0 uninstall function=\"uninstall_last9_monitoring\""
    elif [ "$EVENTS_ONLY" = true ]; then
        # Install only Kubernetes Events Agent
        log_info "Starting Kubernetes Events Agent installation..."

        setup_repository
        setup_helm_repos
        install_events_agent

        cleanup

        log_info "🎉 Kubernetes Events Agent installation completed successfully!"
        log_info "Next steps:"
        echo "  1. Wait for events agent pod to be in Running state: kubectl get pods -n $NAMESPACE"
        echo "  2. Check events agent logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=last9-kube-events-agent"
        echo "  3. Verify events agent service: kubectl get svc -n $NAMESPACE"
        echo ""
        echo "📝 Note: Kubernetes events will be collected and sent to Last9"
        echo ""
        echo "To add OpenTelemetry later, run: $0 token=\"your-token\" endpoint=\"your-otel-endpoint\""
        echo "To uninstall later, run: $0 uninstall"
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
        echo "To add operator later, run: $0 operator-only token=\"your-token\" endpoint=\"your-otel-endpoint\""
        echo "To add monitoring later, run: $0 token=\"your-token\" endpoint=\"your-otel-endpoint\" monitoring-endpoint=\"your-monitoring-endpoint\" cluster=\"cluster-name\" username=\"user\" password=\"pass\""
        echo "To uninstall later, run: $0 uninstall"
    elif [ "$OPERATOR_ONLY" = true ]; then
        # Install OpenTelemetry Operator and Collector
        log_info "Starting OpenTelemetry Operator and Collector installation..."
        
        # Check if token and endpoint are provided for collector installation
        if [ -z "$AUTH_TOKEN" ]; then
            log_error "Auth token is required for collector installation."
            log_error "Please provide token=<value> parameter for operator-only installation."
            exit 1
        fi
        
        if [ -z "$OTEL_ENDPOINT" ]; then
            log_error "OTEL endpoint is required for collector installation."
            log_error "Please provide endpoint=<value> parameter for operator-only installation."
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
        echo "To add monitoring later, run: $0 token=\"your-token\" endpoint=\"your-otel-endpoint\" monitoring-endpoint=\"your-monitoring-endpoint\" cluster=\"cluster-name\" username=\"user\" password=\"pass\""
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

        # Install Kubernetes Events Agent
        log_info "Installing Kubernetes Events Agent..."
        install_events_agent

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

# Handle script interruption and cleanup
trap cleanup EXIT INT TERM

# Run main function
main "$@"

