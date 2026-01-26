# Verify Package Integrity for Offline Installation
# Run this script in the air-gapped environment after transferring files
# Checks SHA256 checksums against checksums.txt

param(
    [Parameter(Mandatory=$false)]
    [string]$BundlePath = "."
)

$ErrorActionPreference = "Stop"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " Package Integrity Verification" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# Check if checksums file exists
$checksumsFile = Join-Path $BundlePath "checksums.txt"
if (-not (Test-Path $checksumsFile)) {
    Write-Host "✗ Error: checksums.txt not found!" -ForegroundColor Red
    Write-Host "  Expected location: $checksumsFile" -ForegroundColor Yellow
    exit 1
}

Write-Host "Reading checksums from: $checksumsFile" -ForegroundColor Gray
Write-Host ""

# Read expected checksums
$expectedChecksums = @{}
Get-Content $checksumsFile | ForEach-Object {
    if ($_.Trim() -ne "") {
        $parts = $_ -split '\s+', 2
        if ($parts.Count -eq 2) {
            $expectedChecksums[$parts[1]] = $parts[0]
        }
    }
}

Write-Host "Found $($expectedChecksums.Count) expected checksums" -ForegroundColor Green
Write-Host ""
Write-Host "Verifying files..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------"

$verifiedCount = 0
$failedCount = 0
$missingCount = 0

foreach ($relativePath in $expectedChecksums.Keys) {
    $filePath = Join-Path $BundlePath $relativePath
    $expectedHash = $expectedChecksums[$relativePath]

    Write-Host "Checking: $relativePath" -ForegroundColor Gray

    if (-not (Test-Path $filePath)) {
        Write-Host "  ✗ MISSING: File not found" -ForegroundColor Red
        $missingCount++
        continue
    }

    # Calculate actual hash
    try {
        $actualHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash

        if ($actualHash -eq $expectedHash) {
            Write-Host "  ✓ OK: Checksum matches" -ForegroundColor Green
            $verifiedCount++
        }
        else {
            Write-Host "  ✗ FAILED: Checksum mismatch!" -ForegroundColor Red
            Write-Host "    Expected: $expectedHash" -ForegroundColor Yellow
            Write-Host "    Actual:   $actualHash" -ForegroundColor Yellow
            $failedCount++
        }
    }
    catch {
        Write-Host "  ✗ ERROR: Failed to calculate hash: $_" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " Verification Results" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verified:  $verifiedCount files" -ForegroundColor Green
if ($failedCount -gt 0) {
    Write-Host "Failed:    $failedCount files" -ForegroundColor Red
}
if ($missingCount -gt 0) {
    Write-Host "Missing:   $missingCount files" -ForegroundColor Red
}
Write-Host ""

if ($failedCount -eq 0 -and $missingCount -eq 0) {
    Write-Host "✓ All packages verified successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can proceed with installation:" -ForegroundColor Cyan
    Write-Host "  .\install-offline.ps1 -Component DotNetAuto" -ForegroundColor Gray
    Write-Host "  .\install-offline.ps1 -Component CollectorAgent" -ForegroundColor Gray
    Write-Host ""
    exit 0
}
else {
    Write-Host "✗ Verification failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "DO NOT PROCEED with installation." -ForegroundColor Yellow
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  - Corrupted files during transfer" -ForegroundColor Gray
    Write-Host "  - Incomplete transfer" -ForegroundColor Gray
    Write-Host "  - Modified files" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Cyan
    Write-Host "  1. Re-transfer the offline bundle" -ForegroundColor Gray
    Write-Host "  2. Verify the archive checksum after transfer" -ForegroundColor Gray
    Write-Host "  3. Extract again and re-run this verification" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
