# Prepare Offline Installation Bundle for Air-Gapped Environments
# Run this script on a machine WITH internet access
# Creates offline-bundle.zip for transfer to air-gapped datacenter

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\offline-bundle",

    [Parameter(Mandatory=$false)]
    [string]$OtelDotNetVersion = "1.13.0",

    [Parameter(Mandatory=$false)]
    [string]$OtelCollectorVersion = "0.140.0"
)

$ErrorActionPreference = "Stop"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " OpenTelemetry Offline Bundle Preparation" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will download all required packages for air-gapped installation:"
Write-Host "  - OpenTelemetry .NET Auto-Instrumentation v$OtelDotNetVersion"
Write-Host "  - OpenTelemetry Collector Contrib v$OtelCollectorVersion"
Write-Host "  - Oracle.ManagedDataAccess NuGet packages"
Write-Host "  - Sample application dependencies"
Write-Host ""

# Create output directory
if (Test-Path $OutputPath) {
    Write-Host "Cleaning existing output directory..." -ForegroundColor Yellow
    Remove-Item $OutputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
New-Item -ItemType Directory -Path "$OutputPath\packages" -Force | Out-Null
New-Item -ItemType Directory -Path "$OutputPath\scripts" -Force | Out-Null
New-Item -ItemType Directory -Path "$OutputPath\configs" -Force | Out-Null

# Function to download file with progress
function Download-File {
    param(
        [string]$Url,
        [string]$OutputFile
    )

    Write-Host "Downloading: $Url" -ForegroundColor Green
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputFile -UseBasicParsing
        Write-Host "  ✓ Downloaded: $(Split-Path $OutputFile -Leaf)" -ForegroundColor Green

        # Get file size
        $fileSize = (Get-Item $OutputFile).Length / 1MB
        Write-Host "  Size: $($fileSize.ToString('F2')) MB" -ForegroundColor Gray
    }
    catch {
        Write-Host "  ✗ Failed: $_" -ForegroundColor Red
        throw
    }
    $ProgressPreference = 'Continue'
}

# Function to calculate SHA256 hash
function Get-FileHashSHA256 {
    param([string]$FilePath)
    $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
    return $hash.Hash
}

Write-Host "`n[1/5] Downloading OpenTelemetry .NET Auto-Instrumentation..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------"

# Download .NET Auto-Instrumentation
$dotnetAutoUrl = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/v$OtelDotNetVersion/opentelemetry-dotnet-instrumentation-windows.zip"
$dotnetAutoFile = "$OutputPath\packages\otel-dotnet-auto-$OtelDotNetVersion.zip"
Download-File -Url $dotnetAutoUrl -OutputFile $dotnetAutoFile

# Also download PowerShell module
$psModuleUrl = "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/v$OtelDotNetVersion/OpenTelemetry.DotNet.Auto.psm1"
$psModuleFile = "$OutputPath\scripts\OpenTelemetry.DotNet.Auto.psm1"
Download-File -Url $psModuleUrl -OutputFile $psModuleFile

Write-Host "`n[2/5] Downloading OpenTelemetry Collector..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------"

# Download Collector for Windows
$collectorUrl = "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v$OtelCollectorVersion/otelcol-contrib_${OtelCollectorVersion}_windows_amd64.msi"
$collectorFile = "$OutputPath\packages\otelcol-contrib-$OtelCollectorVersion.msi"
Download-File -Url $collectorUrl -OutputFile $collectorFile

Write-Host "`n[3/5] Downloading Oracle.ManagedDataAccess..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------"

# Download Oracle.ManagedDataAccess via NuGet
$nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$nugetFile = "$OutputPath\packages\nuget.exe"
Download-File -Url $nugetUrl -OutputFile $nugetFile

Write-Host "Installing Oracle.ManagedDataAccess via NuGet..."
& $nugetFile install Oracle.ManagedDataAccess -Version 23.6.0 -OutputDirectory "$OutputPath\packages\nuget-packages" -NonInteractive

Write-Host "`n[4/5] Copying installation scripts..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------"

# Copy installation scripts
$scriptFiles = @(
    "install-offline.ps1",
    "verify-packages.ps1"
)

foreach ($script in $scriptFiles) {
    $sourcePath = Join-Path $PSScriptRoot $script
    $destPath = Join-Path "$OutputPath\scripts" $script

    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath $destPath -Force
        Write-Host "  ✓ Copied: $script" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Not found: $script (will need to be added manually)" -ForegroundColor Yellow
    }
}

# Copy config templates
Write-Host "`nCopying configuration templates..."
$parentDir = Split-Path $PSScriptRoot -Parent
$configDirs = @("agent-mode", "gateway-datacenter", "configuration")

foreach ($dir in $configDirs) {
    $sourceDir = Join-Path $parentDir $dir
    if (Test-Path $sourceDir) {
        $destDir = Join-Path "$OutputPath\configs" $dir
        Copy-Item $sourceDir $destDir -Recurse -Force
        Write-Host "  ✓ Copied configs from: $dir" -ForegroundColor Green
    }
}

Write-Host "`n[5/5] Generating checksums..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------"

# Generate checksums for all packages
$checksumFile = "$OutputPath\checksums.txt"
$checksums = @()

Get-ChildItem "$OutputPath\packages" -File -Recurse | ForEach-Object {
    $hash = Get-FileHashSHA256 -FilePath $_.FullName
    $relativePath = $_.FullName.Replace("$OutputPath\", "")
    $checksums += "$hash  $relativePath"
    Write-Host "  ✓ $($_.Name)" -ForegroundColor Green
}

$checksums | Out-File $checksumFile -Encoding UTF8
Write-Host "`nChecksums saved to: checksums.txt" -ForegroundColor Green

# Create README
Write-Host "`nCreating README..." -ForegroundColor Cyan
$readmeContent = @"
# OpenTelemetry Offline Installation Bundle

**Created**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**OpenTelemetry .NET Auto**: v$OtelDotNetVersion
**OpenTelemetry Collector**: v$OtelCollectorVersion

## Contents

\`\`\`
offline-bundle/
├── packages/
│   ├── otel-dotnet-auto-$OtelDotNetVersion.zip     (.NET Auto-Instrumentation)
│   ├── otelcol-contrib-$OtelCollectorVersion.msi   (OpenTelemetry Collector)
│   ├── nuget-packages/                             (Oracle.ManagedDataAccess)
│   └── nuget.exe                                   (NuGet CLI)
├── scripts/
│   ├── OpenTelemetry.DotNet.Auto.psm1             (PowerShell module)
│   ├── install-offline.ps1                        (Installation script)
│   └── verify-packages.ps1                        (Verification script)
├── configs/
│   ├── agent-mode/                                (Agent configurations)
│   ├── gateway-datacenter/                        (Gateway configurations)
│   └── configuration/                             (Web.config templates)
├── checksums.txt                                  (SHA256 checksums)
└── README.md                                      (This file)
\`\`\`

## Installation Steps (Air-Gapped Environment)

### 1. Transfer Bundle
Transfer this entire directory to your air-gapped environment via approved method:
- USB drive
- Secure file transfer
- Approved transfer mechanism

### 2. Verify Integrity
\`\`\`powershell
cd offline-bundle
.\scripts\verify-packages.ps1
\`\`\`

### 3. Install .NET Auto-Instrumentation
\`\`\`powershell
.\scripts\install-offline.ps1 -Component DotNetAuto
\`\`\`

### 4. Install OpenTelemetry Collector
\`\`\`powershell
.\scripts\install-offline.ps1 -Component CollectorAgent
\`\`\`

### 5. Configure Agent
\`\`\`powershell
# Copy appropriate config from configs/agent-mode/
# Edit with your gateway endpoint and service name
# Deploy to: C:\ProgramData\OpenTelemetry Collector\config.yaml
\`\`\`

### 6. Start Services
\`\`\`powershell
# Start OpenTelemetry Collector service
Start-Service otelcol-contrib

# For IIS applications:
Import-Module .\scripts\OpenTelemetry.DotNet.Auto.psm1
Register-OpenTelemetryForIIS

# Restart IIS
net stop was /y
net start w3svc
\`\`\`

## Verification

\`\`\`powershell
# Check collector health
Invoke-WebRequest -Uri http://localhost:13133

# Check metrics
Invoke-WebRequest -Uri http://localhost:8888/metrics | Select-String "otelcol"
\`\`\`

## Support

For issues:
1. Check logs: C:\ProgramData\OpenTelemetry Collector\logs\
2. Verify checksums match checksums.txt
3. Ensure all ports are accessible (4317, 4318, 13133, 8888)
4. Review network connectivity to gateway

---
Generated by: prepare-offline-bundle.ps1
"@

$readmeContent | Out-File "$OutputPath\README.md" -Encoding UTF8

# Create version info file
$versionInfo = @{
    "created" = Get-Date -Format "o"
    "otel_dotnet_version" = $OtelDotNetVersion
    "otel_collector_version" = $OtelCollectorVersion
    "powershell_version" = $PSVersionTable.PSVersion.ToString()
    "os_version" = [System.Environment]::OSVersion.VersionString
} | ConvertTo-Json

$versionInfo | Out-File "$OutputPath\version-info.json" -Encoding UTF8

Write-Host "`n=====================================================" -ForegroundColor Cyan
Write-Host " Bundle Preparation Complete!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output directory: $OutputPath" -ForegroundColor Yellow
Write-Host ""

# Calculate total size
$totalSize = (Get-ChildItem $OutputPath -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Total bundle size: $($totalSize.ToString('F2')) MB" -ForegroundColor Yellow
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Review the contents in: $OutputPath"
Write-Host "  2. Create archive for transfer:"
Write-Host "     Compress-Archive -Path '$OutputPath\*' -DestinationPath 'offline-bundle.zip'"
Write-Host "  3. Calculate archive checksum:"
Write-Host "     Get-FileHash -Path 'offline-bundle.zip' -Algorithm SHA256"
Write-Host "  4. Transfer offline-bundle.zip to air-gapped environment"
Write-Host "  5. Verify checksum after transfer"
Write-Host "  6. Run verify-packages.ps1 before installation"
Write-Host ""
Write-Host "Documentation: See README.md in ../README.md" -ForegroundColor Gray
