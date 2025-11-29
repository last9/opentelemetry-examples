# .NET Framework 4.8 OpenTelemetry Integration for Air-Gapped Environments

**Comprehensive monitoring for .NET Framework 4.8 applications on Windows Server 2019 → AWS → Last9**

## Overview

This example demonstrates production-ready OpenTelemetry instrumentation for .NET Framework 4.8 applications in **air-gapped datacenters** with telemetry forwarding through AWS to Last9.

### Architecture

```
Air-Gapped Datacenter          AWS Account              Last9
┌─────────────────────┐       ┌──────────────┐       ┌─────────┐
│ .NET App + Agent    │──────>│ AWS Gateway  │──────>│ OTLP    │
│ Oracle + Agent      │       │ (EC2/ECS)    │       │ Inggest │
│ DC Gateway          │       │ Load Balanced│       └─────────┘
└─────────────────────┘       └──────────────┘
```

### Latest Versions

- **OpenTelemetry .NET Auto-Instrumentation**: v1.13.0 (Nov 2024)
- **OpenTelemetry Collector Contrib**: v0.140.0 (Nov 2025)
- **Oracle.ManagedDataAccess**: ≥23.6.0
- **Target Platform**: Windows Server 2019 Datacenter, .NET Framework 4.8

## Quick Start

### Prerequisites

- Windows Server 2019 or later
- .NET Framework 4.8 SDK
- IIS with ASP.NET 4.8
- PowerShell 5.1+
- Administrator privileges
- Network connectivity to datacenter gateway

### 5-Minute Setup (For Testing)

```powershell
# 1. Extract offline bundle (pre-downloaded)
Expand-Archive -Path offline-bundle.zip -DestinationPath C:\otel-install

# 2. Verify package integrity
cd C:\otel-install
.\offline-installation\verify-packages.ps1

# 3. Install .NET Auto-Instrumentation (offline)
.\offline-installation\install-offline.ps1 -Component DotNetAuto

# 4. Install OTel Collector Agent
.\offline-installation\install-offline.ps1 -Component CollectorAgent

# 5. Configure agent
.\agent-mode\install-agent.ps1 -GatewayEndpoint "dc-gateway.internal:4317"

# 6. Deploy sample app (optional)
.\sample-app\deploy-sample-app.ps1

# 7. Restart IIS
net stop was /y
net start w3svc

# 8. Verify instrumentation
.\verify-installation.ps1
```

## What Gets Automatically Instrumented

✅ **ASP.NET Framework** (MVC, Web API, HTTP Modules)
✅ **Oracle Database** (Oracle.ManagedDataAccess ≥23.4.0)
✅ **SQL Server** (System.Data.SqlClient, Microsoft.Data.SqlClient)
✅ **HTTP Client** (HttpClient, WebClient, HttpWebRequest)
✅ **WCF Services** (Client & Server)
✅ **Message Queues** (MSMQ, RabbitMQ)
✅ **Redis** (StackExchange.Redis)
✅ **Custom Logging** (ILogger, log4net, NLog)

## Directory Structure

```
dotnet-framework-4.8/
├── README.md                          # This file
├── offline-installation/              # Air-gap installation
│   ├── packages/                      # Pre-downloaded binaries
│   ├── prepare-offline-bundle.ps1     # Download packages (internet machine)
│   ├── install-offline.ps1            # Install without internet
│   └── verify-packages.ps1            # Checksum verification
├── agent-mode/                        # Per-host collector
│   ├── config-agent.yaml              # Agent configuration
│   ├── install-agent.ps1              # Agent setup script
│   └── setup-dotnet-instrumentation.ps1
├── gateway-datacenter/                # Datacenter gateway
│   ├── config-gateway-dc.yaml         # Gateway configuration
│   ├── config-high-availability.yaml  # Multi-instance setup
│   ├── install-gateway.ps1            # Gateway setup
│   ├── configure-tls.ps1              # mTLS configuration
│   └── certificates/                  # TLS certificates
├── sample-app/                        # Comprehensive demo app
│   ├── SampleWebApp.sln
│   ├── SampleWebApp/                  # ASP.NET application
│   └── deploy-sample-app.ps1
├── configuration/                     # Configuration templates
│   ├── web.config.minimal.xml
│   ├── web.config.advanced.xml
│   └── environment-variables.ps1
├── troubleshooting.md                 # Common issues
├── production-checklist.md            # Deployment validation
└── air-gap-deployment-guide.md        # Complete offline guide
```

## Sample Application Features

The included sample application demonstrates comprehensive instrumentation:

### 1. **Database Operations (Oracle 19c)**
- Connection pooling with automatic instrumentation
- CRUD operations (Create/Read/Update/Delete)
- Stored procedure calls
- Batch operations and transactions
- Connection failure handling
- Query performance tracking

### 2. **External API Calls**
- HttpClient requests with distributed tracing
- Retry logic with Polly
- Timeout handling
- Header propagation (W3C TraceContext)
- Async and sync operations

### 3. **Background Processing**
- Background job scheduling
- Async task processing
- Long-running operations
- Queue-based processing (MSMQ)
- Status tracking

### 4. **Caching Layer**
- Memory cache operations
- Redis cache (optional)
- Cache hit/miss tracking
- Cache invalidation patterns

### 5. **Error Scenarios**
- Exception handling and tracking
- Database connection failures
- External service timeouts
- 404/500 error instrumentation

## Three-Tier Architecture

### Tier 1: Agent Mode (Per Windows Server)

**Purpose**: Collect telemetry from local applications and forward to datacenter gateway

**Configuration**: `agent-mode/config-agent.yaml`

```yaml
receivers:
  otlp:  # Receives from .NET auto-instrumentation
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
  hostmetrics:  # Windows host metrics
    scrapers: [cpu, memory, disk, filesystem, network]

exporters:
  otlp/gateway:
    endpoint: "dc-gateway-01.internal:4317"  # Datacenter gateway
    sending_queue:
      enabled: true
      storage: file_storage  # Survives restarts

extensions:
  file_storage:  # Persistent queue
    directory: C:\ProgramData\otel\queue
```

### Tier 2: Gateway Mode (Datacenter)

**Purpose**: Aggregate telemetry from all agents, filter sensitive data, forward to AWS

**Configuration**: `gateway-datacenter/config-gateway-dc.yaml`

```yaml
receivers:
  otlp:  # Receives from agents
    protocols:
      grpc:
        tls:  # mTLS for security
          cert_file: /etc/otel/certs/gateway-cert.pem

processors:
  attributes:  # Remove sensitive data before leaving datacenter
    actions:
      - key: password
        action: delete
      - key: credit_card
        action: delete

exporters:
  otlp/aws:
    endpoint: "otel-gateway.aws.company.com:4317"  # AWS gateway
    sending_queue:
      enabled: true
      queue_size: 50000  # Large buffer for network issues
      storage: file_storage
```

### Tier 3: Gateway Mode (AWS)

**Purpose**: Receive from datacenter, forward to Last9

**Location**: See `../aws-gateway/` directory

## Offline Installation

### Step 1: Prepare Offline Bundle (Internet-Connected Machine)

```powershell
# Run on a machine WITH internet access
.\offline-installation\prepare-offline-bundle.ps1

# This downloads:
# - OpenTelemetry .NET Auto v1.13.0 (MSI installer)
# - OpenTelemetry Collector v0.140.0 (MSI installer)
# - Oracle.ManagedDataAccess NuGet packages
# - Sample application dependencies
# - TLS certificates (if generated)
# - Installation scripts
# - Configuration templates

# Creates: offline-bundle.zip (approximately 150 MB)
```

### Step 2: Transfer to Air-Gapped Environment

```powershell
# Transfer via approved method (USB, secure file transfer, etc.)
# Verify file integrity after transfer

.\offline-installation\verify-packages.ps1
# Checks SHA256 checksums for all packages
```

### Step 3: Install on Windows Servers

```powershell
# Install .NET Auto-Instrumentation
.\offline-installation\install-offline.ps1 -Component DotNetAuto

# Install OTel Collector
.\offline-installation\install-offline.ps1 -Component CollectorAgent

# Configure agent mode
.\agent-mode\install-agent.ps1 `
    -GatewayEndpoint "dc-gateway.internal:4317" `
    -ServiceName "order-api" `
    -Environment "production"
```

## Web.config Configuration

For ASP.NET Framework applications, configure OpenTelemetry via `appSettings`:

```xml
<configuration>
  <appSettings>
    <!-- OpenTelemetry Configuration -->
    <add key="OTEL_SERVICE_NAME" value="order-processing-api" />
    <add key="OTEL_EXPORTER_OTLP_ENDPOINT" value="http://localhost:4318" />
    <add key="OTEL_TRACES_SAMPLER" value="always_on" />
    <add key="OTEL_RESOURCE_ATTRIBUTES" value="deployment.environment=production,service.version=1.0.0" />

    <!-- Oracle Connection (use environment variables for passwords) -->
    <add key="OracleConnectionString" value="Data Source=oracle-db:1521/ORCL;User Id=app_user;Password=%ORACLE_PASSWORD%;" />

    <!-- External Services -->
    <add key="PaymentGatewayUrl" value="https://payment-gateway.internal" />
  </appSettings>
</configuration>
```

**Security Note**: Use environment variables or encrypted config sections for sensitive values.

## IIS Configuration

```powershell
# Register OpenTelemetry for IIS
Import-Module "C:\Program Files\OpenTelemetry .NET AutoInstrumentation\OpenTelemetry.DotNet.Auto.psm1"
Register-OpenTelemetryForIIS

# Create application pool
New-WebAppPool -Name "OrderApiAppPool"

# Deploy application
New-Website -Name "OrderApi" `
    -PhysicalPath "C:\inetpub\wwwroot\OrderApi" `
    -ApplicationPool "OrderApiAppPool" `
    -Port 443 `
    -Protocol https

# CRITICAL: Restart IIS properly
net stop was /y
net start w3svc
# Do NOT use iisreset - it doesn't fully reload environment variables
```

## Verification

### 1. Check Agent Health

```powershell
# Health check endpoint
Invoke-WebRequest -Uri http://localhost:13133 -UseBasicParsing

# Check metrics endpoint
Invoke-WebRequest -Uri http://localhost:8888/metrics -UseBasicParsing | Select-String "otelcol_exporter_sent_spans"
```

### 2. Generate Test Traffic

```powershell
# Test .NET application endpoint
Invoke-WebRequest -Uri https://localhost/health -UseBasicParsing

# Test Oracle database query endpoint
Invoke-WebRequest -Uri https://localhost/api/orders -UseBasicParsing

# Test external API call endpoint
Invoke-WebRequest -Uri https://localhost/api/payments/check/12345 -Method GET
```

### 3. Verify in Last9

1. Log in to https://app.last9.io
2. Navigate to **Traces**
3. Filter by `service.name="order-processing-api"`
4. Verify traces appear within 1-2 minutes
5. Check for spans: HTTP requests, database queries, external calls

## Performance Impact

**Typical overhead**: <1% CPU, <100MB memory per agent

**Benchmarks**:
- HTTP request latency: +0.5-2ms
- Database query overhead: +0.1-0.5ms
- Memory per trace: ~2-5KB
- Network bandwidth: ~10-50KB/sec (depends on traffic)

## Troubleshooting

### No Traces Appearing

```powershell
# 1. Check if instrumentation is loaded
Get-Process -Name w3wp | Select-Object -ExpandProperty Modules | Where-Object {$_.ModuleName -like "*OpenTelemetry*"}

# 2. Check collector logs
Get-Content "C:\ProgramData\OpenTelemetry Collector\logs\otelcol.log" -Tail 50

# 3. Verify agent can reach gateway
Test-NetConnection -ComputerName dc-gateway.internal -Port 4317

# 4. Check queue status
Get-ChildItem "C:\ProgramData\otel\queue" -Recurse | Measure-Object -Property Length -Sum
```

### High Memory Usage

```yaml
# Add memory limiter to agent config
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
```

### Network Connectivity Issues

Persistent queues ensure data isn't lost during network outages. Check queue size:

```powershell
# Monitor queue growth
Get-Item "C:\ProgramData\otel\queue" | Select-Object -ExpandProperty Length / 1MB

# Alert if > 1GB (indicates prolonged outage)
```

See [troubleshooting.md](./troubleshooting.md) for more details.

## Security Considerations

### 1. Credentials

❌ **Never hardcode credentials in config files**
✅ **Use environment variables or Windows Credential Manager**

```powershell
# Set environment variable securely
[Environment]::SetEnvironmentVariable("ORACLE_PASSWORD", "SecurePassword123", "Machine")
```

### 2. TLS Certificates

All communication between tiers uses mTLS:
- Agent ←→ Datacenter Gateway: mTLS
- Datacenter Gateway ←→ AWS Gateway: mTLS
- AWS Gateway ←→ Last9: HTTPS

See `gateway-datacenter/certificates/README-certificates.md` for setup.

### 3. Data Filtering

Sensitive data is removed at the **datacenter gateway** before leaving your network:

```yaml
processors:
  attributes:
    actions:
      - key: password
        action: delete
      - key: credit_card
        action: delete
      - key: ssn
        action: delete
```

## Production Deployment Checklist

See [production-checklist.md](./production-checklist.md) for complete validation.

## Additional Resources

- **OpenTelemetry .NET Documentation**: https://opentelemetry.io/docs/languages/dotnet/
- **Collector Documentation**: https://opentelemetry.io/docs/collector/
- **Last9 Documentation**: https://docs.last9.io
- **GitHub Issues**: https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/issues

## Support

For issues specific to this integration:
1. Check [troubleshooting.md](./troubleshooting.md)
2. Review collector logs
3. Test network connectivity between tiers
4. Verify certificate configuration

---

**Generated for**: Windows Server 2019 DC + .NET Framework 4.8 + Oracle 19c
**Target**: Last9 via AWS Gateway
**Version**: OpenTelemetry Collector v0.140.0, .NET Auto v1.13.0
