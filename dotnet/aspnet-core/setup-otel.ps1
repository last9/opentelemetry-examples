#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-shot OTel auto-instrumentation setup for ASP.NET Core (.NET 6+) on IIS or Kestrel.

.DESCRIPTION
    IIS mode  (default): installs CLR profiler, registers for IIS, configures app pool.
    Kestrel mode:        writes OTEL_* env vars to a .env file for use with dotnet run
                         or a Windows Service / NSSM wrapper.

.PARAMETER Mode
    "iis" (default) or "kestrel"

.PARAMETER AppPoolName
    IIS Application Pool name (IIS mode only).
    IMPORTANT: ASP.NET Core requires the pool's .NET CLR Version = "No Managed Code".
    This script sets that automatically.

.PARAMETER ServiceName
    Value for OTEL_SERVICE_NAME.

.PARAMETER OtlpEndpoint
    OTel Collector endpoint, e.g. http://gateway-vm:4317

.PARAMETER OtlpHeaders
    Optional auth headers, e.g. "Authorization=Basic <base64>"

.PARAMETER Environment
    deployment.environment value. Default: production

.PARAMETER OtelVersion
    OTel .NET Auto-Instrumentation release tag. Default: v1.14.1

.PARAMETER EnvFile
    Path to write the .env file (Kestrel mode only). Default: .\otel.env

.EXAMPLE
    # IIS mode
    .\setup-otel.ps1 -AppPoolName "CoreAppPool" -ServiceName "portal-v2" -OtlpEndpoint "http://howv-gateway01:4317"

    # Kestrel mode — writes otel.env
    .\setup-otel.ps1 -Mode kestrel -ServiceName "portal-v2" -OtlpEndpoint "http://howv-gateway01:4317"
    # Then run: dotnet run (the script prints the exact dotnet run command)
#>
param(
    [ValidateSet("iis","kestrel")]
    [string] $Mode             = "iis",
    [string] $AppPoolName      = "",
    [Parameter(Mandatory)][string] $ServiceName,
    [Parameter(Mandatory)][string] $OtlpEndpoint,
    [string] $OtlpHeaders      = "",
    [string] $Environment      = "production",
    [string] $OtelVersion      = "v1.14.1",
    [string] $EnvFile          = ".\otel.env",
    [switch] $DeployCollectorConfig,
    [string] $CollectorConfigDir = "C:\otelcol\conf.d"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Preflight ─────────────────────────────────────────────────────────────────
if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Error @"

ERROR: This script requires Windows PowerShell 5.1 (Desktop edition).
You are running: $($PSVersionTable.PSEdition) v$($PSVersionTable.PSVersion)

Launch with:
  powershell.exe -Version 5.1 -File setup-otel.ps1 ...

"@
    exit 1
}

$OtelHome = "C:\Program Files\OpenTelemetry .NET AutoInstrumentation"

Write-Host ""
Write-Host "=== OTel .NET Auto-Instrumentation Setup (ASP.NET Core / .NET 6+) ===" -ForegroundColor Cyan
Write-Host "  Mode      : $Mode"
Write-Host "  Service   : $ServiceName"
Write-Host "  Endpoint  : $OtlpEndpoint"
Write-Host "  Version   : $OtelVersion"
Write-Host ""

# ── Step 1: Download & Install ────────────────────────────────────────────────
Write-Host "[1/4] Downloading OTel .NET Auto-Instrumentation $OtelVersion..." -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseUrl = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/$OtelVersion"
Invoke-WebRequest "$baseUrl/opentelemetry-dotnet-instrumentation-windows.zip" `
    -OutFile "$env:TEMP\otel-dotnet.zip" -UseBasicParsing
Invoke-WebRequest "$baseUrl/OpenTelemetry.DotNet.Auto.psm1" `
    -OutFile "$env:TEMP\OTelDotNetAuto.psm1" -UseBasicParsing

Write-Host "[2/4] Installing to $OtelHome..." -ForegroundColor Yellow
New-Item -Path $OtelHome -ItemType Directory -Force | Out-Null
Expand-Archive -Path "$env:TEMP\otel-dotnet.zip" -DestinationPath $OtelHome -Force
Copy-Item "$env:TEMP\OTelDotNetAuto.psm1" "$OtelHome\OpenTelemetry.DotNet.Auto.psm1" -Force

$env:OTEL_DOTNET_AUTO_HOME = $OtelHome
Import-Module "$OtelHome\OpenTelemetry.DotNet.Auto.psm1" -Force
Install-OpenTelemetryCore

# ── OTEL env vars (shared between IIS and Kestrel) ────────────────────────────
$otelEnv = [ordered]@{
    OTEL_SERVICE_NAME             = $ServiceName
    OTEL_RESOURCE_ATTRIBUTES      = "deployment.environment=$Environment,host.name=$env:COMPUTERNAME"
    OTEL_TRACES_EXPORTER          = "otlp"
    OTEL_METRICS_EXPORTER         = "otlp"
    OTEL_LOGS_EXPORTER            = "none"
    OTEL_EXPORTER_OTLP_ENDPOINT   = $OtlpEndpoint
    OTEL_EXPORTER_OTLP_PROTOCOL   = "http/protobuf"
    OTEL_PROPAGATORS              = "tracecontext,baggage"
    OTEL_TRACES_SAMPLER           = "parentbased_traceidratio"
    OTEL_TRACES_SAMPLER_ARG       = "1.0"
    OTEL_DOTNET_AUTO_HOME         = $OtelHome
}
if ($OtlpHeaders -ne "") {
    $otelEnv["OTEL_EXPORTER_OTLP_HEADERS"] = $OtlpHeaders
}

if ($Mode -eq "iis") {
    # ── IIS mode ─────────────────────────────────────────────────────────────
    Import-Module WebAdministration -ErrorAction Stop

    if ($AppPoolName -eq "") {
        Write-Error "-AppPoolName is required in IIS mode."
        exit 1
    }
    if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
        Write-Error "App pool '$AppPoolName' not found."
        exit 1
    }

    Write-Host "[3/4] Registering CLR profiler for IIS and configuring app pool..." -ForegroundColor Yellow

    # ASP.NET Core REQUIRES "No Managed Code" (empty managedRuntimeVersion).
    # Using v4.0 here silently breaks auto-instrumentation.
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value ""
    Write-Host "      Set managedRuntimeVersion = '' (No Managed Code) — required for ASP.NET Core." -ForegroundColor Gray

    Register-OpenTelemetryForIIS  # restarts IIS automatically

    $envVarList = $otelEnv.GetEnumerator() | ForEach-Object { @{ name = $_.Key; value = $_.Value } }
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name environmentVariables -Value $envVarList
    Restart-WebAppPool -Name $AppPoolName

    Write-Host ""
    Write-Host "[4/4] Verifying..." -ForegroundColor Yellow
    Write-Host "      Make a request, then run:" -ForegroundColor Gray
    Write-Host '      Get-Process w3wp | % { $_.Modules | Where ModuleName -like "*OpenTelemetry*" }' -ForegroundColor Gray

} else {
    # ── Kestrel mode ──────────────────────────────────────────────────────────
    Write-Host "[3/4] Writing environment variables to $EnvFile..." -ForegroundColor Yellow

    # CLR profiler env vars required for Kestrel
    $profilerVars = @{
        CORECLR_ENABLE_PROFILING                 = "1"
        CORECLR_PROFILER                         = "{918728DD-259F-4A6A-AC2B-B85E1B658318}"
        CORECLR_PROFILER_PATH_64                 = "$OtelHome\win-x64\OpenTelemetry.AutoInstrumentation.Native.dll"
        CORECLR_PROFILER_PATH_32                 = "$OtelHome\win-x86\OpenTelemetry.AutoInstrumentation.Native.dll"
        DOTNET_ADDITIONAL_DEPS                   = "$OtelHome\AdditionalDeps"
        DOTNET_SHARED_STORE                      = "$OtelHome\store"
        DOTNET_STARTUP_HOOKS                     = "$OtelHome\net\OpenTelemetry.AutoInstrumentation.StartupHook.dll"
    }

    $allVars = $profilerVars + $otelEnv

    $lines = $allVars.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    $lines | Set-Content $EnvFile -Encoding UTF8

    Write-Host ""
    Write-Host "[4/4] Done. Run the app with:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  # Load env vars and run" -ForegroundColor Gray
    Write-Host "  Get-Content '$EnvFile' | ForEach-Object { `$k,`$v = `$_ -split '=',2; [System.Environment]::SetEnvironmentVariable(`$k,`$v) }" -ForegroundColor White
    Write-Host "  dotnet run" -ForegroundColor White
    Write-Host ""
    Write-Host "  # Or for a Windows Service / NSSM, point the service env block at $EnvFile" -ForegroundColor Gray
}

# ── Collector config ──────────────────────────────────────────────────────────
if ($DeployCollectorConfig) {
    $src = Join-Path $PSScriptRoot "otelcol-dotnet.yaml"
    if (Test-Path $src) {
        New-Item -Path $CollectorConfigDir -ItemType Directory -Force | Out-Null
        Copy-Item $src "$CollectorConfigDir\dotnet-iis.yaml" -Force
        Write-Host ""
        Write-Host "Collector config deployed to $CollectorConfigDir\dotnet-iis.yaml" -ForegroundColor Green
        Write-Host "Restart the OTel Collector service to pick it up." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
