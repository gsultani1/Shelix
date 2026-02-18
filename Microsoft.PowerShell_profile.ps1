# ============= Microsoft.PowerShell_profile.ps1 =============
# The fact that this works is proof that God loves PowerShell developers
# Profile load timing
$global:ProfileLoadStart = Get-Date
$global:ProfileTimings = @{}

# Safe Mode - report errors but continue loading
trap {
    Write-Host "Error loading PowerShell profile: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
    continue
}

# Keep UTF-8 and predictable output
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
$ErrorActionPreference = "Stop"
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# ===== PowerShell Profile =====
# Suppress startup noise
if ($Host.UI.RawUI.WindowTitle) { Clear-Host }

# ===== Module Loading =====
$global:ModulesPath = "$PSScriptRoot\Modules"
$global:DebugModuleLoading = $false  # Set to $true to see module load errors

# Modular components - load in dependency order
if (Test-Path $global:ModulesPath) {
    # Core utilities (no dependencies)
    . "$global:ModulesPath\ConfigLoader.ps1"       # Load .env config FIRST
    . "$global:ModulesPath\PlatformUtils.ps1"      # Cross-platform helpers
    . "$global:ModulesPath\SecurityUtils.ps1"      # Path/URL security
    . "$global:ModulesPath\CommandValidation.ps1"  # Command safety tables
    
    # System and utilities
    . "$global:ModulesPath\SystemUtilities.ps1"    # uptime, hwinfo, ports, procs, sudo, PATH
    . "$global:ModulesPath\ArchiveUtils.ps1"       # zip, unzip
    . "$global:ModulesPath\DockerTools.ps1"        # Docker shortcuts
    . "$global:ModulesPath\DevTools.ps1"           # IDE launchers, dev checks
    
    # AI and chat infrastructure
    . "$global:ModulesPath\NaturalLanguage.ps1"    # NL to command translation
    . "$global:ModulesPath\AIExecution.ps1"        # AI command execution gateway
    . "$global:ModulesPath\ResponseParser.ps1"     # Parse AI responses
    
    # Document and productivity
    . "$global:ModulesPath\DocumentTools.ps1"      # OpenXML document creation
    . "$global:ModulesPath\SafetySystem.ps1"       # AI execution safety
    . "$global:ModulesPath\TerminalTools.ps1"      # Terminal tool integration
    . "$global:ModulesPath\NavigationUtils.ps1"    # Directory shortcuts
    . "$global:ModulesPath\PackageManager.ps1"     # Tool installation
    . "$global:ModulesPath\WebTools.ps1"           # Web search
    . "$global:ModulesPath\ProductivityTools.ps1"  # Clipboard, git, calendar
    . "$global:ModulesPath\MCPClient.ps1"          # MCP server integration
    
    # User experience
    . "$global:ModulesPath\FzfIntegration.ps1"     # Fuzzy finder
    . "$global:ModulesPath\PersistentAliases.ps1"  # User-defined aliases
    . "$global:ModulesPath\ProfileHelp.ps1"        # Help and tips
    
    # Chat session (depends on many modules)
    . "$global:ModulesPath\ToastNotifications.ps1"   # Toast notifications
    . "$global:ModulesPath\FolderContext.ps1"        # Folder awareness for AI context
    . "$global:ModulesPath\ChatSession.ps1"          # LLM chat loop
}

# Core modules (load AFTER modules so real functions exist before stub checks)
. "$global:ModulesPath\IntentAliasSystem.ps1"
. "$global:ModulesPath\ChatProviders.ps1"

# Plugins (load AFTER core so registries exist for merging)
. "$global:ModulesPath\PluginLoader.ps1"

# ===== Module Reload Functions =====
function Update-IntentAliases {
    . "$global:ModulesPath\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    # Re-merge plugins since reloading core wipes the global hashtables
    $global:LoadedPlugins = [ordered]@{}
    Import-ShelixPlugins -Quiet
    Write-Host "Intent aliases reloaded (plugins re-merged)." -ForegroundColor Green
}
Set-Alias reload-intents Update-IntentAliases -Force

function Update-ChatProviders {
    . "$global:ModulesPath\ChatProviders.ps1" -ErrorAction SilentlyContinue
    Write-Host "Chat providers reloaded." -ForegroundColor Green
}
Set-Alias reload-providers Update-ChatProviders -Force

function Update-ShelixPlugins {
    # Unregister all current plugin contributions, then re-load from disk
    foreach ($pName in @($global:LoadedPlugins.Keys)) {
        Unregister-ShelixPlugin -Name $pName
    }
    Import-ShelixPlugins
}
Set-Alias reload-plugins Update-ShelixPlugins -Force

function Update-AllModules {
    . "$global:ModulesPath\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    . "$global:ModulesPath\ChatProviders.ps1" -ErrorAction SilentlyContinue
    if (Test-Path $global:ModulesPath) {
        Get-ChildItem "$global:ModulesPath\*.ps1" | ForEach-Object {
            . $_.FullName -ErrorAction SilentlyContinue
        }
    }
    # Re-merge plugins after core reload
    $global:LoadedPlugins = [ordered]@{}
    Import-ShelixPlugins
    Write-Host "All modules reloaded." -ForegroundColor Green
}
Set-Alias reload-all Update-AllModules -Force

# ===== Prompt with Style =====
function Prompt {
    $path = (Get-Location).Path.Replace($env:USERPROFILE, '~')
    Write-Host ("[" + (Get-Date -Format "HH:mm:ss") + "] ") -ForegroundColor DarkCyan -NoNewline
    Write-Host ("PS ") -ForegroundColor Cyan -NoNewline
    Write-Host $path -ForegroundColor Yellow -NoNewline
    return "> "
}

# ===== Lazy Module Loading =====
$global:LazyModules = @{
    'Terminal-Icons' = $false
    'posh-git'       = $false
    'ThreadJob'      = $false
}

function Import-LazyModule {
    param([string]$Name)
    if (-not $global:LazyModules[$Name]) {
        $loadTime = Measure-Command {
            Import-Module $Name -ErrorAction SilentlyContinue
        }
        $global:LazyModules[$Name] = $true
        Write-Host "Loaded $Name ($([math]::Round($loadTime.TotalMilliseconds))ms)" -ForegroundColor DarkGray
    }
}

function Enable-TerminalIcons {
    if (-not $global:LazyModules['Terminal-Icons']) {
        Import-LazyModule 'Terminal-Icons'
    }
}

function Enable-PoshGit {
    if (-not $global:LazyModules['posh-git']) {
        if (Test-Path .git -ErrorAction SilentlyContinue) {
            Import-LazyModule 'posh-git'
        }
    }
}

function Enable-ThreadJob {
    if (-not $global:LazyModules['ThreadJob']) {
        Import-LazyModule 'ThreadJob'
    }
}

# Aliases to trigger lazy loading
function lz { Enable-TerminalIcons; Get-ChildItem @args | Format-Table -AutoSize }
function gst { Enable-PoshGit; git status @args }

# ===== Profile Reload =====
Set-Alias reload ". $PROFILE" -Force

# ===== Startup Message =====
$global:ProfileLoadTime = (Get-Date) - $global:ProfileLoadStart
Write-Host "`nPowerShell $($PSVersionTable.PSVersion) on $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "Profile loaded in $([math]::Round($global:ProfileLoadTime.TotalMilliseconds))ms | Session: $($global:SessionId)" -ForegroundColor DarkGray
Write-Host "Type 'tips' for quick reference, 'profile-timing' for load details" -ForegroundColor DarkGray
