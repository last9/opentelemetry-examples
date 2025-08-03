# Individual Function Execution Guide

This guide explains how to execute individual functions from the OpenTelemetry setup script for upgrading specific Helm charts or components.

## Available Functions

The script supports executing these individual functions:

1. **`setup_helm_repos`** - Sets up Helm repositories
2. **`install_operator`** - Installs/upgrades OpenTelemetry Operator
3. **`install_collector`** - Installs/upgrades OpenTelemetry Collector
4. **`create_collector_service`** - Creates collector service
5. **`create_instrumentation`** - Creates instrumentation
6. **`verify_installation`** - Verifies the installation

## Usage Examples

### 1. Setup Helm Repositories Only
```bash
./setup-otel.sh function="setup_helm_repos"
```

### 2. Install/Upgrade OpenTelemetry Operator Only
```bash
./setup-otel.sh function="install_operator"
```

### 3. Install/Upgrade OpenTelemetry Collector with Default Values
```bash
./setup-otel.sh function="install_collector" token="your-auth-token-here"
```

### 4. Install/Upgrade OpenTelemetry Collector with Custom Values File
```bash
./setup-otel.sh function="install_collector" token="your-auth-token-here" values="custom-values.yaml"
```
**Note:** The values file should be in your current directory, not in the git repository.

### 5. Create Collector Service Only
```bash
./setup-otel.sh function="create_collector_service" token="your-auth-token-here"
```

### 6. Create Instrumentation Only
```bash
./setup-otel.sh function="create_instrumentation" token="your-auth-token-here"
```

### 7. Verify Installation
```bash
./setup-otel.sh function="verify_installation"
```

## Parameters

### Required Parameters
- **`function`** - The name of the function to execute
- **`token`** - Authentication token (required for functions that need authentication)

### Optional Parameters
- **`values`** - Custom values file path (for `install_collector` function)
- **`repo`** - Git repository URL (for functions that need repository access)

## Function Dependencies

Some functions have dependencies that are automatically handled:

- **`install_operator`** - Automatically runs `setup_helm_repos` first
- **`install_collector`** - Automatically runs `setup_repository` and `setup_helm_repos` first
- **`create_collector_service`** - Automatically runs `setup_repository` first
- **`create_instrumentation`** - Automatically runs `setup_repository` first

## Helm Chart Upgrade Examples

### Upgrade OpenTelemetry Operator
```bash
./setup-otel.sh function="install_operator"
```

### Upgrade OpenTelemetry Collector with Custom Values
```bash
./setup-otel.sh function="install_collector" token="your-token" values="my-custom-values.yaml"
```
**Note:** The values file should be in your current directory.

### Upgrade OpenTelemetry Collector with Default Values
```bash
./setup-otel.sh function="install_collector" token="your-token"
```

## Notes

1. **Token Requirement**: Functions that need authentication (like `install_collector`, `create_collector_service`, `create_instrumentation`) require the `token` parameter.

2. **Values File**: When using the `values` parameter, make sure your custom values file is in your current directory and contains the necessary configuration for the OpenTelemetry Collector. The script will automatically replace `{{AUTH_TOKEN}}` placeholder with your provided token.

3. **Namespace**: All operations use the `last9` namespace by default.

4. **Repository**: Functions that need repository access will clone the default repository unless specified with the `repo` parameter.

5. **Error Handling**: The script includes proper error handling and will exit if prerequisites are not met.

## Troubleshooting

- If a function fails, check the prerequisites (helm, kubectl, git)
- Ensure you have proper cluster access
- Verify your authentication token is correct
- Check that custom values files are properly formatted 