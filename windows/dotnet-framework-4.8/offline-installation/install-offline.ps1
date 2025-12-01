# Offline Installation Script for OpenTelemetry Components
# For use in air-gapped environments (no internet access)
# Requires: Administrator privileges

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("DotNetAuto", "CollectorAgent", "All")]
    [string]$Component,

    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "C:\Program Files",

    [Parameter(Mandatory=$false)]
    [string]$BundlePath = (Split-Path $PSScriptRoot -Parent),

    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " OpenTelemetry Offline Installation" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Component: $Component" -ForegroundColor Yellow
Write-Host "Install Path: $InstallPath" -ForegroundColor Yellow
Write-Host "Bundle Path: $BundlePath" -ForegroundColor Yellow
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "✗ Error: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "  Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Verify packages unless skipped
if (-not $SkipVerification) {
    Write-Host "[Step 1] Verifying package integrity..." -ForegroundColor Cyan
    Write-Host "------------------------------------------------------"
    & "$PSScriptRoot\verify-packages.ps1" -BundlePath $BundlePath
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "✗ Package verification failed. Installation aborted." -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[Step 1] Package verification SKIPPED" -ForegroundColor Yellow
    Write-Host ""
}

# Function to install .NET Auto-Instrumentation
function Install-DotNetAuto {
    Write-Host "`n[Step 2] Installing OpenTelemetry .NET Auto-Instrumentation..." -ForegroundColor Cyan
    Write-Host "------------------------------------------------------"

    # Find the zip file
    $zipFiles = Get-ChildItem "$BundlePath\packages" -Filter "otel-dotnet-auto-*.zip" -ErrorAction SilentlyContinue
    if ($zipFiles.Count -eq 0) {
        throw "OpenTelemetry .NET Auto installation package not found in $BundlePath\packages"
    }

    $zipFile = $zipFiles[0].FullName
    Write-Host "Found: $($zipFiles[0].Name)" -ForegroundColor Green

    # Installation directory
    $otelDir = "$env:ProgramFiles\OpenTelemetry .NET AutoInstrumentation"
    Write-Host "Installing to: $otelDir" -ForegroundColor Gray

    # Create directory
    if (-not (Test-Path $otelDir)) {
        New-Item -ItemType Directory -Path $otelDir -Force | Out-Null
        Write-Host "  ✓ Created installation directory" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Installation directory already exists" -ForegroundColor Yellow
        Write-Host "  Existing installation will be overwritten" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }

    # Extract archive
    Write-Host "Extracting files..." -ForegroundColor Gray
    try {
        Expand-Archive -Path $zipFile -DestinationPath $otelDir -Force
        Write-Host "  ✓ Extracted successfully" -ForegroundColor Green
    }
    catch {
        throw "Failed to extract archive: $_"
    }

    # Copy PowerShell module
    $psModuleSource = "$BundlePath\scripts\OpenTelemetry.DotNet.Auto.psm1"
    if (Test-Path $psModuleSource) {
        Copy-Item $psModuleSource "$otelDir\OpenTelemetry.DotNet.Auto.psm1" -Force
        Write-Host "  ✓ Copied PowerShell module" -ForegroundColor Green
    }

    # Set environment variables (machine-wide)
    Write-Host "`nConfiguring environment variables..." -ForegroundColor Gray

    $envVars = @{
        "OTEL_DOTNET_AUTO_HOME" = $otelDir
        "OTEL_DOTNET_AUTO_INSTRUMENTATION_ENABLED" = "true"
    }

    foreach ($key in $envVars.Keys) {
        [Environment]::SetEnvironmentVariable($key, $envVars[$key], [EnvironmentVariableTarget]::Machine)
        Write-Host "  ✓ Set $key" -ForegroundColor Green
    }

    # Add to PATH
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
    if ($currentPath -notlike "*$otelDir*") {
        $newPath = "$currentPath;$otelDir"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)
        Write-Host "  ✓ Added to system PATH" -ForegroundColor Green
    }

    Write-Host "`n✓ OpenTelemetry .NET Auto-Instrumentation installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Configure Web.config with OTEL_ settings" -ForegroundColor Gray
    Write-Host "  2. For IIS: Run Register-OpenTelemetryForIIS" -ForegroundColor Gray
    Write-Host "  3. Restart IIS: net stop was /y && net start w3svc" -ForegroundColor Gray
    Write-Host ""
}

# Function to install OpenTelemetry Collector
function Install-CollectorAgent {
    Write-Host "`n[Step 2] Installing OpenTelemetry Collector..." -ForegroundColor Cyan
    Write-Host "------------------------------------------------------"

    # Find the MSI file
    $msiFiles = Get-ChildItem "$BundlePath\packages" -Filter "otelcol-contrib-*.msi" -ErrorAction SilentlyContinue
    if ($msiFiles.Count -eq 0) {
        throw "OpenTelemetry Collector MSI not found in $BundlePath\packages"
    }

    $msiFile = $msiFiles[0].FullName
    Write-Host "Found: $($msiFiles[0].Name)" -ForegroundColor Green
    Write-Host "Installing MSI package..." -ForegroundColor Gray

    # Install MSI silently
    try {
        $arguments = @(
            "/i"
            "`"$msiFile`""
            "/quiet"
            "/norestart"
            "/l*v"
            "`"$env:TEMP\otelcol-install.log`""
        )

        $process = Start-Process "msiexec.exe" -ArgumentList $arguments -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Host "  ✓ MSI installed successfully" -ForegroundColor Green
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Host "  ✓ MSI installed (reboot required)" -ForegroundColor Yellow
        }
        else {
            throw "MSI installation failed with exit code: $($process.ExitCode). Check log: $env:TEMP\otelcol-install.log"
        }
    }
    catch {
        throw "Failed to install MSI: $_"
    }

    # Verify installation
    $collectorExe = "$env:ProgramFiles\OpenTelemetry Collector\otelcol-contrib.exe"
    if (Test-Path $collectorExe) {
        Write-Host "  ✓ Collector binary verified" -ForegroundColor Green

        # Get version
        $version = & $collectorExe --version 2>&1 | Select-String "otelcol-contrib version" | ForEach-Object { $_.ToString() }
        Write-Host "  Version: $version" -ForegroundColor Gray
    }
    else {
        throw "Collector binary not found after installation"
    }

    # Create data directories
    Write-Host "`nCreating data directories..." -ForegroundColor Gray
    $dataDirs = @(
        "C:\ProgramData\OpenTelemetry Collector",
        "C:\ProgramData\OpenTelemetry Collector\logs",
        "C:\ProgramData\otel\queue"
    )

    foreach ($dir in $dataDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "  ✓ Created: $dir" -ForegroundColor Green
        }
    }

    Write-Host "`n✓ OpenTelemetry Collector installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Copy config file to: $env:ProgramFiles\OpenTelemetry Collector\config.yaml" -ForegroundColor Gray
    Write-Host "  2. Configure the Windows service" -ForegroundColor Gray
    Write-Host "  3. Start the service: Start-Service otelcol-contrib" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Configuration templates available in: $BundlePath\configs\agent-mode\" -ForegroundColor Yellow
    Write-Host ""
}

# Main installation logic
try {
    switch ($Component) {
        "DotNetAuto" {
            Install-DotNetAuto
        }
        "CollectorAgent" {
            Install-CollectorAgent
        }
        "All" {
            Install-DotNetAuto
            Install-CollectorAgent
        }
    }

    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host " Installation Complete!" -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installed components:" -ForegroundColor Yellow
    if ($Component -eq "DotNetAuto" -or $Component -eq "All") {
        Write-Host "  ✓ OpenTelemetry .NET Auto-Instrumentation" -ForegroundColor Green
    }
    if ($Component -eq "CollectorAgent" -or $Component -== "All") {
        Write-Host "  ✓ OpenTelemetry Collector" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "IMPORTANT: Some environment variables require a system restart to take effect." -ForegroundColor Yellow
    Write-Host "For IIS applications, restart IIS: net stop was /y && net start w3svc" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Documentation: See README.md for next steps" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Red
    Write-Host " Installation Failed" -ForegroundColor Red
    Write-Host "=====================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Verify you are running as Administrator" -ForegroundColor Gray
    Write-Host "  2. Check that all packages are present in $BundlePath\packages" -ForegroundColor Gray
    Write-Host "  3. Verify package integrity: .\verify-packages.ps1" -ForegroundColor Gray
    Write-Host "  4. Check installation logs in: $env:TEMP\" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
