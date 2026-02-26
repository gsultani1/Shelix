# ============= Microsoft.PowerShell_profile.ps1 =============
# The fact that this works is proof that God loves PowerShell developers
# Profile load timing
$global:ProfileLoadStart = Get-Date
$global:ProfileTimings = @{}
$global:BildsyPSVersion = '1.4.1'

# Safe Mode - report errors but continue loading
trap {
    Write-Host "Error loading PowerShell profile: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
    continue
}

# Ensure Rust/Cargo is on PATH if installed
$cargobin = Join-Path $env:USERPROFILE '.cargo\bin'
if ((Test-Path $cargobin) -and $env:PATH -notmatch [regex]::Escape($cargobin)) {
    $env:PATH = "$cargobin;$env:PATH"
}

# Keep UTF-8 and predictable output
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
$ErrorActionPreference = "Stop"
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# ===== PowerShell Profile =====
# Suppress startup noise
if ($Host.UI.RawUI.WindowTitle) { Clear-Host }

# ===== BildsyPS Home (user data, separate from module install path) =====
$global:BildsyPSHome = "$env:USERPROFILE\.bildsyps"
$global:BildsyPSModulePath = $PSScriptRoot

function Initialize-BildsyPSHome {
    # Create the ~/.bildsyps directory tree on first run
    $dirs = @(
        $global:BildsyPSHome
        "$global:BildsyPSHome\config"
        "$global:BildsyPSHome\data"
        "$global:BildsyPSHome\logs"
        "$global:BildsyPSHome\logs\sessions"
        "$global:BildsyPSHome\plugins"
        "$global:BildsyPSHome\plugins\Config"
        "$global:BildsyPSHome\skills"
        "$global:BildsyPSHome\aliases"
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    # First-run migration: copy old files to new locations if they exist
    $migrated = @()
    $oldRoot = $PSScriptRoot

    # Config/.env -> ~/.bildsyps/config/.env
    $oldEnv = "$oldRoot\Config\.env"
    $newEnv = "$global:BildsyPSHome\config\.env"
    if ((Test-Path $oldEnv) -and -not (Test-Path $newEnv)) {
        Copy-Item $oldEnv $newEnv -Force
        $migrated += ".env"
    }

    # ChatConfig.json -> ~/.bildsyps/config/ChatConfig.json
    $oldChat = "$oldRoot\ChatConfig.json"
    $newChat = "$global:BildsyPSHome\config\ChatConfig.json"
    if ((Test-Path $oldChat) -and -not (Test-Path $newChat)) {
        Copy-Item $oldChat $newChat -Force
        $migrated += "ChatConfig.json"
    }

    # ToolPreferences.json -> ~/.bildsyps/config/ToolPreferences.json
    $oldTP = "$oldRoot\ToolPreferences.json"
    $newTP = "$global:BildsyPSHome\config\ToolPreferences.json"
    if ((Test-Path $oldTP) -and -not (Test-Path $newTP)) {
        Copy-Item $oldTP $newTP -Force
        $migrated += "ToolPreferences.json"
    }

    # UserSkills.json -> ~/.bildsyps/skills/UserSkills.json
    $oldSkills = "$oldRoot\UserSkills.json"
    $newSkills = "$global:BildsyPSHome\skills\UserSkills.json"
    if ((Test-Path $oldSkills) -and -not (Test-Path $newSkills)) {
        Copy-Item $oldSkills $newSkills -Force
        $migrated += "UserSkills.json"
    }

    # UserAliases.ps1 -> ~/.bildsyps/aliases/UserAliases.ps1
    $oldAliases = "$oldRoot\UserAliases.ps1"
    $newAliases = "$global:BildsyPSHome\aliases\UserAliases.ps1"
    if ((Test-Path $oldAliases) -and -not (Test-Path $newAliases)) {
        Copy-Item $oldAliases $newAliases -Force
        $migrated += "UserAliases.ps1"
    }

    # NaturalLanguageMappings.json -> ~/.bildsyps/data/NaturalLanguageMappings.json
    $oldNL = "$oldRoot\NaturalLanguageMappings.json"
    $newNL = "$global:BildsyPSHome\data\NaturalLanguageMappings.json"
    if ((Test-Path $oldNL) -and -not (Test-Path $newNL)) {
        Copy-Item $oldNL $newNL -Force
        $migrated += "NaturalLanguageMappings.json"
    }

    # ~/Documents/ChatLogs/ -> ~/.bildsyps/logs/sessions/
    $oldLogs = "$env:USERPROFILE\Documents\ChatLogs"
    $newLogs = "$global:BildsyPSHome\logs\sessions"
    if ((Test-Path $oldLogs) -and (Get-ChildItem $oldLogs -Filter "*.json" -ErrorAction SilentlyContinue).Count -gt 0) {
        $existingNew = (Get-ChildItem $newLogs -Filter "*.json" -ErrorAction SilentlyContinue).Count
        if ($existingNew -eq 0) {
            Copy-Item "$oldLogs\*.json" $newLogs -Force -ErrorAction SilentlyContinue
            $migrated += "ChatLogs ($(( Get-ChildItem $newLogs -Filter '*.json' -ErrorAction SilentlyContinue).Count) sessions)"
        }
    }

    # ~/Documents/ChatLogs/AIExecutionLog.json -> ~/.bildsyps/logs/AIExecutionLog.json
    $oldExecLog = "$env:USERPROFILE\Documents\ChatLogs\AIExecutionLog.json"
    $newExecLog = "$global:BildsyPSHome\logs\AIExecutionLog.json"
    if ((Test-Path $oldExecLog) -and -not (Test-Path $newExecLog)) {
        Copy-Item $oldExecLog $newExecLog -Force
        $migrated += "AIExecutionLog.json"
    }

    # Plugins/ -> ~/.bildsyps/plugins/ (user plugin files only, skip bundled examples)
    $oldPlugins = "$oldRoot\Plugins"
    if (Test-Path $oldPlugins) {
        $userPlugins = Get-ChildItem "$oldPlugins\*.ps1" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_Example*' -and $_.Name -notlike '_Pomodoro*' -and $_.Name -notlike '_QuickNotes*' }
        foreach ($p in $userPlugins) {
            $dest = Join-Path "$global:BildsyPSHome\plugins" $p.Name
            if (-not (Test-Path $dest)) {
                Copy-Item $p.FullName $dest -Force
                $migrated += "Plugin: $($p.Name)"
            }
        }
        # Plugin configs
        $oldPConfig = "$oldPlugins\Config"
        if (Test-Path $oldPConfig) {
            Get-ChildItem "$oldPConfig\*.json" -ErrorAction SilentlyContinue | ForEach-Object {
                $dest = Join-Path "$global:BildsyPSHome\plugins\Config" $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item $_.FullName $dest -Force
                }
            }
        }
    }

    if ($migrated.Count -gt 0) {
        Write-Host "`n[BildsyPS] Migrated $($migrated.Count) item(s) to $global:BildsyPSHome" -ForegroundColor Cyan
        foreach ($m in $migrated) {
            Write-Host "  - $m" -ForegroundColor DarkCyan
        }
        Write-Host "  Old files left in place (safe to remove manually).`n" -ForegroundColor DarkGray
    }
}

Initialize-BildsyPSHome

# ===== Module Loading =====
$global:ModulesPath = "$PSScriptRoot\Modules"
$global:DebugModuleLoading = $false  # Set to $true to see module load errors

# Modular components - load in dependency order
if (Test-Path $global:ModulesPath) {
    # Core utilities (no dependencies)
    . "$global:ModulesPath\ConfigLoader.ps1"       # Load .env config FIRST
    . "$global:ModulesPath\PlatformUtils.ps1"      # Cross-platform helpers
    . "$global:ModulesPath\SecurityUtils.ps1"      # Path/URL security
    . "$global:ModulesPath\SecretScanner.ps1"      # Secret detection (before CommandValidation so scan runs early)
    . "$global:ModulesPath\CommandValidation.ps1"  # Command safety tables
    
    # System and utilities
    . "$global:ModulesPath\SystemUtilities.ps1"    # uptime, hwinfo, ports, procs, sudo, PATH
    . "$global:ModulesPath\ArchiveUtils.ps1"       # zip, unzip
    . "$global:ModulesPath\DockerTools.ps1"        # Docker shortcuts
    . "$global:ModulesPath\DevTools.ps1"           # IDE launchers, dev checks
    
    # AI and chat infrastructure
    . "$global:ModulesPath\NaturalLanguage.ps1"    # NL to command translation
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
    
    # Context awareness
    . "$global:ModulesPath\BrowserAwareness.ps1"   # Browser tab awareness
    . "$global:ModulesPath\VisionTools.ps1"        # Vision model support (screenshot, image analysis)
    . "$global:ModulesPath\OCRTools.ps1"           # Tesseract OCR + pdftotext integration
    . "$global:ModulesPath\CodeArtifacts.ps1"      # AI code generation artifacts
    . "$global:ModulesPath\AppBuilder.ps1"        # Prompt-to-executable pipeline

    # User experience
    . "$global:ModulesPath\FzfIntegration.ps1"     # Fuzzy finder
    . "$global:ModulesPath\PersistentAliases.ps1"  # User-defined aliases
    . "$global:ModulesPath\ProfileHelp.ps1"        # Help and tips
    
    # Chat session (depends on many modules)
    . "$global:ModulesPath\ToastNotifications.ps1"   # Toast notifications
    . "$global:ModulesPath\FolderContext.ps1"        # Folder awareness for AI context
    . "$global:ModulesPath\ChatStorage.ps1"          # SQLite chat persistence + FTS5 search
    . "$global:ModulesPath\ChatSession.ps1"          # LLM chat loop
    . "$global:ModulesPath\AgentHeartbeat.ps1"       # Cron-triggered agent tasks
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
    # Re-merge user skills and plugins since reloading core wipes the global hashtables
    $global:LoadedUserSkills = [ordered]@{}
    Import-UserSkills -Quiet
    $global:LoadedPlugins = [ordered]@{}
    Import-BildsyPSPlugins -Quiet
    Write-Host "Intent aliases reloaded (skills + plugins re-merged)." -ForegroundColor Green
}
Set-Alias reload-intents Update-IntentAliases -Force

function Update-UserSkills {
    Unregister-UserSkills
    Import-UserSkills
}
Set-Alias reload-skills Update-UserSkills -Force

function Update-ChatProviders {
    . "$global:ModulesPath\ChatProviders.ps1" -ErrorAction SilentlyContinue
    Write-Host "Chat providers reloaded." -ForegroundColor Green
}
Set-Alias reload-providers Update-ChatProviders -Force

function Update-BildsyPSPlugins {
    # Unregister all current plugin contributions, then re-load from disk
    foreach ($pName in @($global:LoadedPlugins.Keys)) {
        Unregister-BildsyPSPlugin -Name $pName
    }
    Import-BildsyPSPlugins
}
Set-Alias reload-plugins Update-BildsyPSPlugins -Force

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
    Import-BildsyPSPlugins
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

# ===== Startup Secret Scan =====
if (Get-Command Invoke-StartupSecretScan -ErrorAction SilentlyContinue) {
    Invoke-StartupSecretScan
}

# ===== Startup Message =====
$global:ProfileLoadTime = (Get-Date) - $global:ProfileLoadStart
Write-Host "`nPowerShell $($PSVersionTable.PSVersion) on $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "Profile loaded in $([math]::Round($global:ProfileLoadTime.TotalMilliseconds))ms | Session: $($global:SessionId)" -ForegroundColor DarkGray
Write-Host "Type 'tips' for quick reference, 'profile-timing' for load details" -ForegroundColor DarkGray
