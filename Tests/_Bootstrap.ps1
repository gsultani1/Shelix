# ===== _Bootstrap.ps1 =====
# Shared test bootstrap: loads BildsyPS modules with temp isolation.
# Dot-source this at the top of each .Tests.ps1 file.
# Sets $global:BildsyPSHome to a temp directory so no production data is touched.

param(
    [switch]$SkipIntents,
    [switch]$SkipChat,
    [switch]$SkipAgent,
    [switch]$SkipVision,
    [switch]$SkipAppBuilder,
    [switch]$SkipHeartbeat,
    [switch]$Minimal
)

$ErrorActionPreference = 'Stop'

# Resolve paths
$script:RepoRoot = Split-Path $PSScriptRoot -Parent
$global:ModulesPath = Join-Path $script:RepoRoot 'Modules'
$global:BildsyPSVersion = '1.3.0'

# Create isolated temp home
$global:TestTempRoot = Join-Path $env:TEMP "bildsyps_test_$(Get-Random)"
$global:BildsyPSHome = $global:TestTempRoot

$testDirs = @(
    "$global:BildsyPSHome\config",
    "$global:BildsyPSHome\logs\sessions",
    "$global:BildsyPSHome\data",
    "$global:BildsyPSHome\builds",
    "$global:BildsyPSHome\plugins",
    "$global:BildsyPSHome\skills",
    "$global:BildsyPSHome\aliases"
)
foreach ($d in $testDirs) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

# Paths that modules reference
$global:ChatLogsPath = "$global:BildsyPSHome\logs\sessions"
$global:ConfigPath = "$global:BildsyPSHome\config"
$global:EnvFilePath = "$global:BildsyPSHome\config\.env"

# Profile-level globals that modules may reference
if (-not $global:ProfileTimings) { $global:ProfileTimings = @{} }

# Reset ChatStorage state so each test file gets a fresh DB
$global:ChatDbPath = "$global:BildsyPSHome\data\bildsyps.db"
$global:ChatDbReady = $false

# ===== Load modules in dependency order =====

# Core utilities (no dependencies)
. "$global:ModulesPath\ConfigLoader.ps1"
. "$global:ModulesPath\PlatformUtils.ps1"
. "$global:ModulesPath\SecurityUtils.ps1"

# SecretScanner may reference paths from SecurityUtils
if (Test-Path "$global:ModulesPath\SecretScanner.ps1") {
    . "$global:ModulesPath\SecretScanner.ps1"
}

. "$global:ModulesPath\CommandValidation.ps1"
. "$global:ModulesPath\SafetySystem.ps1"

if ($Minimal) {
    # Still define cleanup helper even in minimal mode
    function Remove-TestTempRoot {
        try { [Microsoft.Data.Sqlite.SqliteConnection]::ClearAllPools() } catch {}
        $global:ChatDbReady = $false
        if ($global:TestTempRoot -and (Test-Path $global:TestTempRoot)) {
            Remove-Item $global:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    return
}

# AI infrastructure
. "$global:ModulesPath\NaturalLanguage.ps1"
. "$global:ModulesPath\ResponseParser.ps1"

# Code artifacts (needed by AppBuilder)
. "$global:ModulesPath\CodeArtifacts.ps1"

# Vision
if (-not $SkipVision) {
    if (Test-Path "$global:ModulesPath\VisionTools.ps1") {
        . "$global:ModulesPath\VisionTools.ps1"
    }
}

# Chat storage (SQLite)
if (-not $SkipChat) {
    . "$global:ModulesPath\ChatStorage.ps1"
}

# Chat providers
. "$global:ModulesPath\ChatProviders.ps1"

# Intent system (loads IntentRegistry, IntentActions, IntentActionsSystem, WorkflowEngine, IntentRouter, AgentTools, AgentLoop)
if (-not $SkipIntents) {
    . "$global:ModulesPath\IntentAliasSystem.ps1"
}

# AppBuilder (depends on ChatProviders, CodeArtifacts, SecretScanner, ChatStorage)
if (-not $SkipAppBuilder) {
    if (Test-Path "$global:ModulesPath\AppBuilder.ps1") {
        . "$global:ModulesPath\AppBuilder.ps1"
    }
}

# Heartbeat (depends on AgentLoop, ChatStorage)
if (-not $SkipHeartbeat) {
    if (Test-Path "$global:ModulesPath\AgentHeartbeat.ps1") {
        . "$global:ModulesPath\AgentHeartbeat.ps1"
    }
}

# ===== Test Cleanup Helper =====
function Remove-TestTempRoot {
    # Clear SQLite connection pool to release file locks
    try { [Microsoft.Data.Sqlite.SqliteConnection]::ClearAllPools() } catch {}
    $global:ChatDbReady = $false
    if ($global:TestTempRoot -and (Test-Path $global:TestTempRoot)) {
        Remove-Item $global:TestTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
