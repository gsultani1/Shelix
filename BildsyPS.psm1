# ===== BildsyPS.psm1 =====
# Root module for the BildsyPS PowerShell module.
# Replicates the profile load order for use with Import-Module.

$ModuleRoot = $PSScriptRoot
$global:BildsyPSModulePath = $ModuleRoot
$global:ModulesPath = "$ModuleRoot\Modules"
$global:BildsyPSVersion = '1.3.0'

# ===== Initialize BildsyPSHome =====
$global:BildsyPSHome = "$env:USERPROFILE\.bildsyps"

function Initialize-BildsyPSHome {
    $dirs = @(
        "$global:BildsyPSHome\config",
        "$global:BildsyPSHome\logs\sessions",
        "$global:BildsyPSHome\plugins",
        "$global:BildsyPSHome\skills",
        "$global:BildsyPSHome\aliases",
        "$global:BildsyPSHome\data"
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}

Initialize-BildsyPSHome

# ===== Module Loading (dependency order) =====
if (Test-Path $global:ModulesPath) {
    # Core utilities (no dependencies)
    . "$global:ModulesPath\ConfigLoader.ps1"
    . "$global:ModulesPath\PlatformUtils.ps1"
    . "$global:ModulesPath\SecurityUtils.ps1"
    . "$global:ModulesPath\SecretScanner.ps1"
    . "$global:ModulesPath\CommandValidation.ps1"

    # System and utilities
    . "$global:ModulesPath\SystemUtilities.ps1"
    . "$global:ModulesPath\ArchiveUtils.ps1"
    . "$global:ModulesPath\DockerTools.ps1"
    . "$global:ModulesPath\DevTools.ps1"

    # AI and chat infrastructure
    . "$global:ModulesPath\NaturalLanguage.ps1"
    . "$global:ModulesPath\ResponseParser.ps1"

    # Document and productivity
    . "$global:ModulesPath\DocumentTools.ps1"
    . "$global:ModulesPath\SafetySystem.ps1"
    . "$global:ModulesPath\TerminalTools.ps1"
    . "$global:ModulesPath\NavigationUtils.ps1"
    . "$global:ModulesPath\PackageManager.ps1"
    . "$global:ModulesPath\WebTools.ps1"
    . "$global:ModulesPath\ProductivityTools.ps1"
    . "$global:ModulesPath\MCPClient.ps1"

    # Context awareness
    . "$global:ModulesPath\BrowserAwareness.ps1"
    . "$global:ModulesPath\VisionTools.ps1"
    . "$global:ModulesPath\OCRTools.ps1"
    . "$global:ModulesPath\CodeArtifacts.ps1"
    . "$global:ModulesPath\AppBuilder.ps1"

    # User experience
    . "$global:ModulesPath\FzfIntegration.ps1"
    . "$global:ModulesPath\PersistentAliases.ps1"
    . "$global:ModulesPath\ProfileHelp.ps1"

    # Chat session (depends on many modules)
    . "$global:ModulesPath\ToastNotifications.ps1"
    . "$global:ModulesPath\FolderContext.ps1"
    . "$global:ModulesPath\ChatStorage.ps1"
    . "$global:ModulesPath\ChatSession.ps1"
    . "$global:ModulesPath\AgentHeartbeat.ps1"
}

# Core modules (load AFTER modules so real functions exist before stub checks)
. "$global:ModulesPath\IntentAliasSystem.ps1"
. "$global:ModulesPath\ChatProviders.ps1"

# User skills (load AFTER intents so registries exist, BEFORE plugins)
. "$global:ModulesPath\UserSkills.ps1"

# Plugins (load AFTER core so registries exist for merging)
. "$global:ModulesPath\PluginLoader.ps1"

# ===== Module Reload Functions =====
function Update-IntentAliases {
    . "$global:ModulesPath\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    $global:LoadedUserSkills = [ordered]@{}
    Import-UserSkills -Quiet
    $global:LoadedPlugins = [ordered]@{}
    Import-BildsyPSPlugins -Quiet
    Write-Host "Intent aliases reloaded (skills + plugins re-merged)." -ForegroundColor Green
}

function Update-UserSkills {
    Unregister-UserSkills
    Import-UserSkills
}

function Update-ChatProviders {
    . "$global:ModulesPath\ChatProviders.ps1" -ErrorAction SilentlyContinue
    Write-Host "Chat providers reloaded." -ForegroundColor Green
}

function Update-BildsyPSPlugins {
    foreach ($pName in @($global:LoadedPlugins.Keys)) {
        Unregister-BildsyPSPlugin -Name $pName
    }
    Import-BildsyPSPlugins
}

function Update-AllModules {
    . "$global:ModulesPath\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    . "$global:ModulesPath\ChatProviders.ps1" -ErrorAction SilentlyContinue
    if (Test-Path $global:ModulesPath) {
        Get-ChildItem "$global:ModulesPath\*.ps1" | ForEach-Object {
            . $_.FullName -ErrorAction SilentlyContinue
        }
    }
    $global:LoadedPlugins = [ordered]@{}
    Import-BildsyPSPlugins
    Write-Host "All modules reloaded." -ForegroundColor Green
}

# ===== Install Helper =====
function Install-BildsyPS {
    <#
    .SYNOPSIS
    Initialize BildsyPS user directories and copy example configs.
    Optionally adds Import-Module BildsyPS to the user's profile.

    .PARAMETER AddToProfile
    If set, appends 'Import-Module BildsyPS' to the user's PowerShell profile.
    #>
    param([switch]$AddToProfile)

    Initialize-BildsyPSHome

    # Copy example configs to user config dir if they don't already exist
    $templatesDir = "$ModuleRoot\templates"
    if (Test-Path $templatesDir) {
        Get-ChildItem $templatesDir -File | ForEach-Object {
            $destName = $_.Name -replace '\.example', ''
            $destPath = Join-Path "$global:BildsyPSHome\config" $destName
            if (-not (Test-Path $destPath)) {
                Copy-Item $_.FullName $destPath
                Write-Host "  Created: $destPath" -ForegroundColor Green
            }
        }
    }

    Write-Host "`nBildsyPS home initialized at: $global:BildsyPSHome" -ForegroundColor Cyan
    Write-Host "  config:  $global:BildsyPSHome\config\" -ForegroundColor DarkGray
    Write-Host "  data:    $global:BildsyPSHome\data\" -ForegroundColor DarkGray
    Write-Host "  logs:    $global:BildsyPSHome\logs\" -ForegroundColor DarkGray
    Write-Host "  plugins: $global:BildsyPSHome\plugins\" -ForegroundColor DarkGray
    Write-Host "  skills:  $global:BildsyPSHome\skills\" -ForegroundColor DarkGray

    if ($AddToProfile) {
        $profilePath = $PROFILE.CurrentUserAllHosts
        if (-not $profilePath) { $profilePath = $PROFILE }
        $profileContent = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
        if ($profileContent -notmatch 'Import-Module\s+BildsyPS') {
            "`nImport-Module BildsyPS" | Out-File $profilePath -Append -Encoding UTF8
            Write-Host "`nAdded 'Import-Module BildsyPS' to $profilePath" -ForegroundColor Green
        }
        else {
            Write-Host "`n'Import-Module BildsyPS' already in profile." -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "`nTo auto-load BildsyPS, run: Install-BildsyPS -AddToProfile" -ForegroundColor DarkGray
    }
}

# ===== Reload Aliases =====
Set-Alias reload-intents  Update-IntentAliases  -Force
Set-Alias reload-skills   Update-UserSkills     -Force
Set-Alias reload-providers Update-ChatProviders  -Force
Set-Alias reload-plugins  Update-BildsyPSPlugins  -Force
Set-Alias reload-all      Update-AllModules     -Force

Write-Verbose "BildsyPS $global:BildsyPSVersion loaded. Type 'tips' for quick reference."
