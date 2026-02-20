# ===== run-tests.ps1 =====
# BildsyPS test launcher. Requires Pester 5.x.
#
# Usage:
#   .\run-tests.ps1              # Offline tests only (no API keys needed)
#   .\run-tests.ps1 -Live        # Include live LLM tests
#   .\run-tests.ps1 -All         # All tests including admin (elevated shell)
#   .\run-tests.ps1 -File Agent  # Run only files matching "Agent"

param(
    [switch]$Live,
    [switch]$All,
    [string]$File
)

$ErrorActionPreference = 'Stop'

# Ensure Pester 5.x is available
$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
if (-not $pester) {
    Write-Host 'Pester 5.x not found. Install with: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser' -ForegroundColor Red
    exit 1
}

Import-Module Pester -MinimumVersion 5.0

$testsDir = Join-Path $PSScriptRoot 'Tests'

# Build file filter
$testFiles = if ($File) {
    Get-ChildItem $testsDir -Filter "*$File*.Tests.ps1"
} else {
    Get-ChildItem $testsDir -Filter '*.Tests.ps1'
}

if ($testFiles.Count -eq 0) {
    Write-Host "No test files found matching '$File'" -ForegroundColor Yellow
    exit 1
}

# Build Pester config
$config = New-PesterConfiguration
$config.Run.Path = $testFiles.FullName
$config.Output.Verbosity = 'Detailed'

if ($All) {
    # Run everything
}
elseif ($Live) {
    $config.Filter.ExcludeTag = @('Admin')
}
else {
    $config.Filter.ExcludeTag = @('Live', 'Admin')
}

$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $PSScriptRoot 'Tests\TestResults.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

Write-Host "`n===== BildsyPS Test Runner =====" -ForegroundColor Cyan
Write-Host "  Files: $($testFiles.Count)" -ForegroundColor Gray
$modeLabel = if ($All) { 'All (offline + live + admin)' } elseif ($Live) { 'Offline + Live' } else { 'Offline only' }
Write-Host "  Mode:  $modeLabel" -ForegroundColor Gray
Write-Host "============================`n" -ForegroundColor Cyan

Invoke-Pester -Configuration $config
