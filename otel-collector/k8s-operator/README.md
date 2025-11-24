# Last9 OpenTelemetry Conflict-Free Installation

Simple tools to eliminate common installation conflicts when setting up Last9 OpenTelemetry monitoring on Kubernetes.

## 🎯 Problem Solved

Customers frequently encountered these issues during Last9 setup:

1. **CRD Ownership Conflicts**: When Dynatrace, New Relic, or other tools already installed OpenTelemetry operator
2. **Port Conflicts**: node-exporter, Prometheus conflicting with existing monitoring infrastructure
3. **Manual Patching**: Users had to manually run kubectl commands to resolve conflicts

## ✅ Solution: High Ports + Smart CRD Strategy

Our approach eliminates conflicts by:

### 1. **High Ports (40000+)**
Following successful operators like Dash0, we use high ports that virtually never conflict:

- Node Exporter: `40001` (instead of 8080/9100)
- Prometheus: `40002` (instead of 9090)
- Kube State Metrics: `40003` (instead of 8080)
- OpenTelemetry Collector HTTP: `40004`
- OpenTelemetry Collector gRPC: `40005`

### 2. **Smart CRD Strategy**
- Detects existing OpenTelemetry CRDs automatically
- Uses `--skip-crds` if CRDs exist (100% safe, no ownership conflicts)
- Installs CRDs normally if none exist
- Compatible with ANY existing operator installation

## 🚀 Quick Start

```bash
# Download the enhanced tools
curl -O https://raw.githubusercontent.com/last9/opentelemetry-examples/main/otel-collector/k8s-operator/last9-conflict-resolver.sh
curl -O https://raw.githubusercontent.com/last9/opentelemetry-examples/main/otel-collector/k8s-operator/last9-enhanced-setup.sh
chmod +x *.sh

# Run conflict-free setup
./last9-enhanced-setup.sh --force-crd-takeover -- \
  monitoring-endpoint="YOUR_METRICS_URL" \
  username="YOUR_USERNAME" \
  password="YOUR_PASSWORD"
```

## 📁 Files

### `last9-conflict-resolver.sh`
Core conflict detection and smart configuration:
- Detects existing OpenTelemetry CRDs
- Uses `--skip-crds` strategy when CRDs exist
- Generates Helm values with high ports
- Can be used standalone

### `last9-enhanced-setup.sh`
Complete setup wrapper:
- Runs conflict detection automatically
- Downloads and executes the main Last9 setup script
- Uses conflict-free configuration

## 🔧 Advanced Usage

### Conflict Detection Only
```bash
# Just check for conflicts and generate config
./last9-conflict-resolver.sh

# Specify cluster name and output directory
./last9-conflict-resolver.sh --cluster-name production --output-dir ./configs
```

### Different Installation Modes
```bash
# Monitoring only (no traces)
./last9-enhanced-setup.sh -- \
  monitoring-only monitoring-endpoint="..." username="..." password="..."

# Full observability
./last9-enhanced-setup.sh -- \
  endpoint="..." token="..." \
  monitoring-endpoint="..." username="..." password="..."
```

## 🧪 Testing

Both scripts can be tested safely:

```bash
# Test help functionality
./last9-conflict-resolver.sh --help
./last9-enhanced-setup.sh --help

# Test conflict detection (read-only)
./last9-conflict-resolver.sh --cluster-name test --output-dir /tmp
```

## 📋 Customer Impact

### Before:
- ❌ Manual kubectl patches for CRD conflicts
- ❌ Port conflicts causing installation failures
- ❌ Multiple support tickets per installation
- ❌ Manual troubleshooting for each environment

### After:
- ✅ **Zero manual steps** for standard installations
- ✅ **No port conflicts** (using high ports 40000+)
- ✅ **No CRD conflicts** (smart --skip-crds strategy)
- ✅ **Works with any existing operator** (Dynatrace, New Relic, etc.)

## 💡 Design Principles

1. **Conflict Avoidance**: Use high ports and `--skip-crds` to avoid conflicts entirely
2. **Simple & Safe**: Never break existing installations, one command for most cases
3. **Smart Detection**: Automatically adapt to existing infrastructure
4. **Enterprise Ready**: Works with any existing operator setup

## 📞 Support

If you encounter issues:

1. Run conflict detection: `./last9-conflict-resolver.sh`
2. Check the generated install script: `/tmp/last9-install-commands.sh`
3. Verify kubectl access and cluster connectivity
4. Contact Last9 support with the conflict resolver output