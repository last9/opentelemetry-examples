#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-shot OTel auto-instrumentation setup for ASP.NET Framework 4.x on IIS.
    Equivalent of Datadog's MSI install — single command, full setup.

.DESCRIPTION
    1. Downloads OTel .NET Automatic Instrumentation
    2. Installs the CLR profiler machine-wide
    3. Registers the profiler for all IIS app pools
    4. Configures the target app pool with OTEL_* environment variables
    5. Deploys the OTel Collector config for IIS + CLR metrics (optional)
    6. Restarts the app pool

.PARAMETER AppPoolName
    IIS Application Pool name for this service.
    Best practice: one dedicated app pool per service (avoids shared-pool silent failures).

.PARAMETER ServiceName
    Value for OTEL_SERVICE_NAME. Appears in Last9 traces as the service identifier.

.PARAMETER OtlpEndpoint
    OTel Collector endpoint, e.g. http://gateway-vm:4317
    For direct-to-Last9: https://otlp.last9.io (also set -OtlpHeaders)

.PARAMETER OtlpHeaders
    Optional auth headers, e.g. "Authorization=Basic <base64>"
    Required when sending directly to Last9 (skip when using a gateway collector).

.PARAMETER Environment
    deployment.environment resource attribute value. Default: production

.PARAMETER OtelVersion
    OTel .NET Auto-Instrumentation release tag. Default: v1.14.1

.PARAMETER DeployCollectorConfig
    If set, copies otelcol-dotnet.yaml to $CollectorConfigDir for IIS + CLR metrics.

.PARAMETER CollectorConfigDir
    Directory where the OTel Collector config snippet should be written.
    Default: C:\otelcol\conf.d

.EXAMPLE
    # Send via gateway collector (recommended for BG)
    .\setup-otel.ps1 `
        -AppPoolName "RareAppPool" `
        -ServiceName "rare" `
        -OtlpEndpoint "http://howv-gateway01:4317" `
        -DeployCollectorConfig

    # Send directly to Last9 (no gateway)
    .\setup-otel.ps1 `
        -AppPoolName "EBSAppPool" `
        -ServiceName "ebs" `
        -OtlpEndpoint "https://otlp.last9.io" `
        -OtlpHeaders "Authorization=Basic <your-base64-token>"
#>
param(
    [Parameter(Mandatory)][string] $AppPoolName,
    [Parameter(Mandatory)][string] $ServiceName,
    [Parameter(Mandatory)][string] $OtlpEndpoint,
    [string] $OtlpHeaders      = "",
    [string] $Environment      = "production",
    [string] $OtelVersion      = "v1.14.1",
    [switch] $DeployCollectorConfig,
    [string] $CollectorConfigDir = "C:\otelcol\conf.d"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Preflight checks ──────────────────────────────────────────────────────────
if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Error @"

ERROR: This script requires Windows PowerShell 5.1 (Desktop edition).
You are running: $($PSVersionTable.PSEdition) v$($PSVersionTable.PSVersion)

Launch with:
  powershell.exe -Version 5.1 -File setup-otel.ps1 -AppPoolName ... -ServiceName ... -OtlpEndpoint ...

"@
    exit 1
}

Import-Module WebAdministration -ErrorAction Stop

if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    Write-Error "App pool '$AppPoolName' not found. Create it in IIS Manager first."
    exit 1
}

$OtelHome = "C:\Program Files\OpenTelemetry .NET AutoInstrumentation"

Write-Host ""
Write-Host "=== OTel .NET Auto-Instrumentation Setup (.NET Framework) ===" -ForegroundColor Cyan
Write-Host "  App Pool  : $AppPoolName"
Write-Host "  Service   : $ServiceName"
Write-Host "  Endpoint  : $OtlpEndpoint"
Write-Host "  Version   : $OtelVersion"
Write-Host "  Env       : $Environment"
Write-Host ""

# ── Step 1: Download ──────────────────────────────────────────────────────────
Write-Host "[1/5] Downloading OTel .NET Auto-Instrumentation $OtelVersion..." -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseUrl = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/$OtelVersion"
Invoke-WebRequest "$baseUrl/opentelemetry-dotnet-instrumentation-windows.zip" `
    -OutFile "$env:TEMP\otel-dotnet.zip" -UseBasicParsing
Invoke-WebRequest "$baseUrl/OpenTelemetry.DotNet.Auto.psm1" `
    -OutFile "$env:TEMP\OTelDotNetAuto.psm1" -UseBasicParsing

# ── Step 2: Install ───────────────────────────────────────────────────────────
Write-Host "[2/5] Installing to $OtelHome..." -ForegroundColor Yellow
New-Item -Path $OtelHome -ItemType Directory -Force | Out-Null
Expand-Archive -Path "$env:TEMP\otel-dotnet.zip" -DestinationPath $OtelHome -Force
Copy-Item "$env:TEMP\OTelDotNetAuto.psm1" "$OtelHome\OpenTelemetry.DotNet.Auto.psm1" -Force

$env:OTEL_DOTNET_AUTO_HOME = $OtelHome
Import-Module "$OtelHome\OpenTelemetry.DotNet.Auto.psm1" -Force
Install-OpenTelemetryCore

# ── Step 3: Register for IIS ──────────────────────────────────────────────────
# Sets the CLR profiler environment variables machine-wide for IIS.
# This performs an IIS restart automatically.
Write-Host "[3/5] Registering CLR profiler for IIS (will restart IIS)..." -ForegroundColor Yellow
Register-OpenTelemetryForIIS

# ── Step 4: Configure app pool ────────────────────────────────────────────────
Write-Host "[4/5] Configuring app pool '$AppPoolName'..." -ForegroundColor Yellow

$envVars = @(
    @{ name = 'OTEL_SERVICE_NAME';           value = $ServiceName },
    @{ name = 'OTEL_RESOURCE_ATTRIBUTES';    value = "deployment.environment=$Environment,host.name=$env:COMPUTERNAME" },
    @{ name = 'OTEL_TRACES_EXPORTER';        value = 'otlp' },
    @{ name = 'OTEL_METRICS_EXPORTER';       value = 'otlp' },
    @{ name = 'OTEL_LOGS_EXPORTER';          value = 'none' },
    @{ name = 'OTEL_EXPORTER_OTLP_ENDPOINT'; value = $OtlpEndpoint },
    @{ name = 'OTEL_EXPORTER_OTLP_PROTOCOL'; value = 'http/protobuf' },
    @{ name = 'OTEL_PROPAGATORS';            value = 'tracecontext,baggage' },
    @{ name = 'OTEL_TRACES_SAMPLER';         value = 'parentbased_traceidratio' },
    @{ name = 'OTEL_TRACES_SAMPLER_ARG';     value = '1.0' }
)

if ($OtlpHeaders -ne "") {
    $envVars += @{ name = 'OTEL_EXPORTER_OTLP_HEADERS'; value = $OtlpHeaders }
}

Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name environmentVariables -Value $envVars
Restart-WebAppPool -Name $AppPoolName

# ── Step 5: Deploy collector config (optional) ────────────────────────────────
if ($DeployCollectorConfig) {
    Write-Host "[5/5] Deploying IIS + CLR metrics collector config..." -ForegroundColor Yellow
    $src = Join-Path $PSScriptRoot "otelcol-dotnet.yaml"
    if (Test-Path $src) {
        New-Item -Path $CollectorConfigDir -ItemType Directory -Force | Out-Null
        Copy-Item $src "$CollectorConfigDir\dotnet-iis.yaml" -Force
        Write-Host "      Collector config written to $CollectorConfigDir\dotnet-iis.yaml" -ForegroundColor Gray
        Write-Host "      Restart the OTel Collector service to pick it up." -ForegroundColor Gray
    } else {
        Write-Warning "otelcol-dotnet.yaml not found next to setup-otel.ps1 — skipping."
    }
} else {
    Write-Host "[5/5] Skipping collector config deploy (use -DeployCollectorConfig to enable)." -ForegroundColor Gray
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "Verify profiler loaded (run after first request):" -ForegroundColor Cyan
Write-Host '  Get-Process w3wp | % { $_.Modules | Where ModuleName -like "*OpenTelemetry*" }'
Write-Host ""
Write-Host "Check app pool env vars:" -ForegroundColor Cyan
Write-Host "  (Get-ItemProperty 'IIS:\AppPools\$AppPoolName').environmentVariables.Collection | Select name, value"
Write-Host ""
Write-Host "Troubleshoot missing spans:" -ForegroundColor Cyan
Write-Host '  Get-ChildItem $env:TEMP -Filter "otel-dotnet-auto-*" | Sort LastWriteTime -Desc | Select -First 1 | Get-Content | Select -Last 30'
