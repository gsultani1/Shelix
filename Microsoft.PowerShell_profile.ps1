# ============= Microsoft.PowerShell_profile.ps1 =============
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
$global:DebugModuleLoading = $true  # Set to $true to see module load errors

# Core modules (always load) - use direct dot-sourcing for reliability
. "$PSScriptRoot\IntentAliasSystem.ps1"
. "$PSScriptRoot\ChatProviders.ps1"

# New modular components
if (Test-Path $global:ModulesPath) {
    . "$global:ModulesPath\SafetySystem.ps1"
    . "$global:ModulesPath\TerminalTools.ps1"
    . "$global:ModulesPath\NavigationUtils.ps1"
    . "$global:ModulesPath\PackageManager.ps1"
    . "$global:ModulesPath\WebTools.ps1"
    . "$global:ModulesPath\ProductivityTools.ps1"
    . "$global:ModulesPath\MCPClient.ps1"
}

# ===== Module Reload Functions =====
function Update-IntentAliases {
    . "$PSScriptRoot\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    Write-Host "Intent aliases reloaded." -ForegroundColor Green
}
Set-Alias reload-intents Update-IntentAliases -Force

function Update-ChatProviders {
    . "$PSScriptRoot\ChatProviders.ps1" -ErrorAction SilentlyContinue
    Write-Host "Chat providers reloaded." -ForegroundColor Green
}
Set-Alias reload-providers Update-ChatProviders -Force

function Update-AllModules {
    . "$PSScriptRoot\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    . "$PSScriptRoot\ChatProviders.ps1" -ErrorAction SilentlyContinue
    if (Test-Path $global:ModulesPath) {
        Get-ChildItem "$global:ModulesPath\*.ps1" | ForEach-Object {
            . $_.FullName -ErrorAction SilentlyContinue
        }
    }
    Write-Host "All modules reloaded." -ForegroundColor Green
}
Set-Alias reload-all Update-AllModules -Force

# Prompt with Style
function Prompt {
    $path = (Get-Location).Path.Replace($env:USERPROFILE, '~')
    Write-Host ("[" + (Get-Date -Format "HH:mm:ss") + "] ") -ForegroundColor DarkCyan -NoNewline
    Write-Host ("PS ") -ForegroundColor Cyan -NoNewline
    Write-Host $path -ForegroundColor Yellow -NoNewline
    return "> "
}

# Admin Elevation with proper directory preservation
function sudo {
    Start-Process powershell -Verb runAs -ArgumentList "-NoExit","-WorkingDirectory '$PWD'"
}

# Port utilities
function ports { netstat -ano | findstr :$args }
function procs($name='') { 
    Get-Process | Where-Object { $_.ProcessName -like "*$name*" } | 
    Sort-Object CPU -Descending | 
    Select-Object Id, ProcessName, CPU, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet / 1MB, 2)}} | 
    Format-Table -AutoSize 
}

# Network utilities
function Test-Port($hostname, $port) {
    Test-NetConnection -ComputerName $hostname -Port $port -InformationLevel Quiet
}

function Get-PublicIP {
    try {
        $ip = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip
        Write-Host "Public IP: $ip" -ForegroundColor Green
        return $ip
    } catch {
        Write-Host "Failed to retrieve public IP" -ForegroundColor Red
    }
}

# Backup & Export Tools
function Export-Env {
    $out = "$env:USERPROFILE\Documents\EnvBackup_$(Get-Date -Format yyyyMMdd_HHmmss).txt"
    $envContent = Get-ChildItem Env: | Sort-Object Name | Out-String
    [System.IO.File]::WriteAllText($out, $envContent, [System.Text.Encoding]::UTF8)
    Write-Host "Environment exported to $out" -ForegroundColor Green
}

# Module Auto-Imports (Lazy-loaded for performance)
# Terminal-Icons and posh-git are loaded on-demand, not at startup
$global:LazyModules = @{
    'Terminal-Icons' = $false
    'posh-git' = $false
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

# Lazy-load Terminal-Icons when listing directories
$global:OriginalGetChildItem = $null
function Enable-TerminalIcons {
    if (-not $global:LazyModules['Terminal-Icons']) {
        Import-LazyModule 'Terminal-Icons'
    }
}

# Lazy-load posh-git when in a git directory
function Enable-PoshGit {
    if (-not $global:LazyModules['posh-git']) {
        if (Test-Path .git -ErrorAction SilentlyContinue) {
            Import-LazyModule 'posh-git'
        }
    }
}

# ThreadJob - lazy load on first AI execution for faster startup
$global:LazyModules['ThreadJob'] = $false

function Enable-ThreadJob {
    if (-not $global:LazyModules['ThreadJob']) {
        Import-LazyModule 'ThreadJob'
    }
}

# Aliases to trigger lazy loading
function lz { Enable-TerminalIcons; Get-ChildItem @args | Format-Table -AutoSize }
function gst { Enable-PoshGit; git status @args }

# ===== Fuzzy Finder (fzf) Integration for History =====
$global:FzfAvailable = $null -ne (Get-Command fzf -ErrorAction SilentlyContinue)

function Invoke-FzfHistory {
    <#
    .SYNOPSIS
    Search command history with fzf fuzzy finder
    #>
    if (-not $global:FzfAvailable) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        Write-Host "Falling back to standard history search..." -ForegroundColor Gray
        Get-History | Select-Object -Last 50 | Format-Table -AutoSize
        return
    }
    
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $historyPath) {
        $selected = Get-Content $historyPath | Where-Object { $_ } | Select-Object -Unique | fzf --tac --no-sort --height 40%
        if ($selected) {
            # Add to current session history and execute
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    } else {
        Get-History | ForEach-Object { $_.CommandLine } | fzf --tac --no-sort --height 40% | ForEach-Object {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($_)
        }
    }
}

function Invoke-FzfFile {
    <#
    .SYNOPSIS
    Fuzzy find files in current directory
    #>
    if (-not $global:FzfAvailable) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        return
    }
    
    $selected = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | 
        Select-Object -ExpandProperty FullName | 
        fzf --height 40%
    
    if ($selected) {
        return $selected
    }
}

function Invoke-FzfDirectory {
    <#
    .SYNOPSIS
    Fuzzy find and change to directory
    #>
    if (-not $global:FzfAvailable) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        return
    }
    
    $selected = Get-ChildItem -Recurse -Directory -ErrorAction SilentlyContinue | 
        Select-Object -ExpandProperty FullName | 
        fzf --height 40%
    
    if ($selected) {
        Set-Location $selected
    }
}

# Keyboard shortcut for fzf history (Ctrl+R replacement)
if ($global:FzfAvailable) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
        Invoke-FzfHistory
    }
}

Set-Alias fh Invoke-FzfHistory -Force
Set-Alias ff Invoke-FzfFile -Force
Set-Alias fd Invoke-FzfDirectory -Force

# ===== Persistent User Aliases =====
$global:UserAliasesPath = "$PSScriptRoot\UserAliases.ps1"

function Add-PersistentAlias {
    <#
    .SYNOPSIS
    Add a persistent alias that survives session restarts
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Value,
        [string]$Description = ""
    )
    
    # Create file if doesn't exist
    if (-not (Test-Path $global:UserAliasesPath)) {
        @"
# ===== User-Defined Persistent Aliases =====
# This file is auto-generated. Add aliases using Add-PersistentAlias
# or edit manually and run: reload-aliases

"@ | Out-File $global:UserAliasesPath -Encoding UTF8
    }
    
    # Check if alias already exists
    $content = Get-Content $global:UserAliasesPath -Raw
    if ($content -match "Set-Alias\s+-Name\s+$Name\s+") {
        Write-Host "Alias '$Name' already exists. Use Remove-PersistentAlias first." -ForegroundColor Yellow
        return $false
    }
    
    # Add the alias
    $aliasLine = "Set-Alias -Name $Name -Value $Value -Force"
    if ($Description) {
        $aliasLine = "# $Description`n$aliasLine"
    }
    
    Add-Content $global:UserAliasesPath "`n$aliasLine"
    
    # Apply immediately
    Set-Alias -Name $Name -Value $Value -Force -Scope Global
    
    Write-Host "Alias '$Name' -> '$Value' added and saved." -ForegroundColor Green
    return $true
}

function Remove-PersistentAlias {
    <#
    .SYNOPSIS
    Remove a persistent alias
    #>
    param([Parameter(Mandatory=$true)][string]$Name)
    
    if (-not (Test-Path $global:UserAliasesPath)) {
        Write-Host "No user aliases file found." -ForegroundColor Yellow
        return
    }
    
    $lines = Get-Content $global:UserAliasesPath
    $newLines = $lines | Where-Object { $_ -notmatch "Set-Alias\s+-Name\s+$Name\s+" }
    
    if ($lines.Count -eq $newLines.Count) {
        Write-Host "Alias '$Name' not found in persistent aliases." -ForegroundColor Yellow
        return
    }
    
    $newLines | Out-File $global:UserAliasesPath -Encoding UTF8
    
    # Remove from current session
    Remove-Item "Alias:\$Name" -ErrorAction SilentlyContinue
    
    Write-Host "Alias '$Name' removed." -ForegroundColor Green
}

function Get-PersistentAliases {
    <#
    .SYNOPSIS
    List all persistent user aliases
    #>
    if (-not (Test-Path $global:UserAliasesPath)) {
        Write-Host "No user aliases defined yet." -ForegroundColor Yellow
        Write-Host "Use: Add-PersistentAlias -Name <alias> -Value <command>" -ForegroundColor Gray
        return
    }
    
    Write-Host "`n===== Persistent User Aliases =====" -ForegroundColor Cyan
    Get-Content $global:UserAliasesPath | Where-Object { $_ -match "^Set-Alias" } | ForEach-Object {
        if ($_ -match "Set-Alias\s+-Name\s+(\S+)\s+-Value\s+(\S+)") {
            Write-Host "  $($Matches[1])" -ForegroundColor Green -NoNewline
            Write-Host " -> $($Matches[2])" -ForegroundColor Gray
        }
    }
    Write-Host "===================================`n" -ForegroundColor Cyan
}

function Update-UserAliases {
    if (Test-Path $global:UserAliasesPath) {
        . $global:UserAliasesPath
        Write-Host "User aliases reloaded." -ForegroundColor Green
    }
}

Set-Alias add-alias Add-PersistentAlias -Force
Set-Alias remove-alias Remove-PersistentAlias -Force
Set-Alias list-aliases Get-PersistentAliases -Force
Set-Alias reload-aliases Update-UserAliases -Force

# Load user aliases if file exists
if (Test-Path $global:UserAliasesPath) {
    . $global:UserAliasesPath
}

# Quick restart
function restart-ps { Start-Process powershell -ArgumentList '-NoExit' ; exit }

# Uptime Alias
function uptime { 
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $span = (Get-Date) - $boot
    Write-Host "System uptime: $($span.Days) days, $($span.Hours) hours, $($span.Minutes) minutes" -ForegroundColor Green
}

# Get Hardware Info
function hwinfo {
    Write-Host "`n===== Hardware Info =====" -ForegroundColor Cyan
    Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory |
        Format-List
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors |
        Format-List
}

# ===== Core Environment Management =====
function Update-Environment {
    [CmdletBinding()]
    param([switch]$VerboseOutput)
    
    try {
        $before = $env:PATH.Length
        $envVars = @{
            'System' = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
            'User'   = 'HKCU:\Environment'
        }
        
        foreach ($scope in $envVars.Keys) {
            $path = $envVars[$scope]
            if (Test-Path $path) {
                (Get-Item $path -ErrorAction SilentlyContinue).GetValueNames() | ForEach-Object {
                    $value = (Get-ItemProperty -Path $path -Name $_ -ErrorAction SilentlyContinue).$_
                    if ($null -ne $value) {
                        $expandedValue = [Environment]::ExpandEnvironmentVariables($value)
                        Set-Item -Path "env:$_" -Value $expandedValue -Force
                        if ($VerboseOutput) { Write-Host "[$scope] $_=$expandedValue" -ForegroundColor DarkGray }
                    }
                }
            }
        }
        
        $after = $env:PATH.Length
        Write-Host "Environment refreshed. PATH: $before -> $after chars" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to refresh environment: $_"
    }
}
Set-Alias refreshenv Update-Environment
Set-Alias reload ". $PROFILE"

# ===== Navigation & Git (defined in Modules/NavigationUtils.ps1) =====
# Duplicates removed - NavigationUtils.ps1 provides: .., ..., ~, docs, desktop, downloads
# Git shortcuts: gs, ga, gc, gp, gl, gb, gco, and more
# Utilities: touch, mkcd, which, size, tree, zip/unzip

# ===== System Utilities (kept here - not in NavigationUtils) =====
function grep($pattern, $path = '*') { 
    Select-String -Pattern $pattern -Path $path -ErrorAction SilentlyContinue
}

# ===== PATH Management =====
function Show-Path { 
    $env:PATH -split ';' | Where-Object {$_} | Sort-Object | ForEach-Object { 
        $cleanPath = $_.TrimEnd('\')
        $color = if (Test-Path $cleanPath) { 'Green' } else { 'Red' }
        Write-Host $cleanPath -ForegroundColor $color
    }
}

function Add-PathUser($dir) { 
    if (Test-Path $dir) {
        $cleanDir = $dir.TrimEnd('\')
        $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $paths = $current -split ';' | ForEach-Object { $_.TrimEnd('\') }
        
        if ($paths -notcontains $cleanDir) {
            [Environment]::SetEnvironmentVariable('PATH', "$current;$cleanDir", 'User')
            refreshenv
            Write-Host "Added to user PATH: $cleanDir" -ForegroundColor Green
        } else {
            Write-Host "Already in PATH: $cleanDir" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Directory not found: $dir" -ForegroundColor Red
    }
}

function Add-PathSystem($dir) {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Requires elevated privileges. Run with sudo." -ForegroundColor Red
        return
    }
    
    if (Test-Path $dir) {
        $cleanDir = $dir.TrimEnd('\')
        $current = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $paths = $current -split ';' | ForEach-Object { $_.TrimEnd('\') }
        
        if ($paths -notcontains $cleanDir) {
            [Environment]::SetEnvironmentVariable('PATH', "$current;$cleanDir", 'Machine')
            refreshenv
            Write-Host "Added to system PATH: $cleanDir" -ForegroundColor Green
        } else {
            Write-Host "Already in PATH: $cleanDir" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Directory not found: $dir" -ForegroundColor Red
    }
}

# ===== File Operations =====
function ll { Get-ChildItem -Force | Format-Table -AutoSize }
function la { Get-ChildItem -Force -Hidden | Format-Table -AutoSize }
function lsd { Get-ChildItem -Directory | Format-Table -AutoSize }
function lsf { Get-ChildItem -File | Format-Table -AutoSize }

# ===== Archive Operations =====
function Compress-ToZip($source, $destination) {
    if (!(Test-Path $source)) {
        Write-Host "Source not found: $source" -ForegroundColor Red
        return
    }
    if (!$destination) {
        $destination = "$source.zip"
    }
    Compress-Archive -Path $source -DestinationPath $destination -Force
    Write-Host "Compressed to: $destination" -ForegroundColor Green
}

function Expand-FromZip($source, $destination) {
    if (!(Test-Path $source)) {
        Write-Host "Archive not found: $source" -ForegroundColor Red
        return
    }
    if (!$destination) {
        $destination = (Get-Item $source).DirectoryName
    }
    Expand-Archive -Path $source -DestinationPath $destination -Force
    Write-Host "Extracted to: $destination" -ForegroundColor Green
}

Set-Alias zip Compress-ToZip
Set-Alias unzip Expand-FromZip

# ===== Docker Shortcuts =====
function dps { docker ps }
function dpsa { docker ps -a }
function dlog { 
    param([Parameter(Mandatory=$true)][string]$container)
    docker logs -f $container 
}
function dexec { 
    param([Parameter(Mandatory=$true)][string]$container)
    docker exec -it $container /bin/bash 
}
function dstop { docker stop $(docker ps -q) }

# ===== Development Shortcuts =====
function open($path = '.') { 
    if (Test-Path $path) { 
        Start-Process explorer $path 
    } else { 
        Write-Host "Path not found: $path" -ForegroundColor Red 
    }
}

function code($path = '.') { 
    if (Get-Command code -ErrorAction SilentlyContinue) {
        if (Test-Path $path) { 
            & code $path 
        } else { 
            Write-Host "Path not found: $path" -ForegroundColor Red 
        }
    } else {
        Write-Host "VS Code not found in PATH" -ForegroundColor Red
    }
}

function cursor($path = '.') { 
    if (Get-Command cursor -ErrorAction SilentlyContinue) {
        if (Test-Path $path) { 
            & cursor $path 
        } else { 
            Write-Host "Path not found: $path" -ForegroundColor Red 
        }
    } else {
        Write-Host "Cursor not found in PATH" -ForegroundColor Red
    }
}

# ===== System Information =====
function Get-SystemInfo {
    Write-Host "`n===== System Information =====" -ForegroundColor Cyan
    Write-Host "Machine: $env:COMPUTERNAME" -ForegroundColor Yellow
    Write-Host "User: $env:USERNAME" -ForegroundColor Yellow
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "OS: $(Get-ComputerInfo | Select-Object -ExpandProperty WindowsProductName)" -ForegroundColor Yellow
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $span = (Get-Date) - $boot
    Write-Host "Uptime: $($span.Days)d $($span.Hours)h $($span.Minutes)m" -ForegroundColor Yellow
    Write-Host "==============================`n" -ForegroundColor Cyan
}

# ===== Quick Diagnostics =====
function Test-DevTools {
    $tools = @('git','node','python','dotnet','ffmpeg','code','cursor','docker')
    Write-Host "`n===== Development Tools Check =====" -ForegroundColor Cyan
    foreach ($tool in $tools) {
        $found = Get-Command $tool -ErrorAction SilentlyContinue
        if ($found) {
            Write-Host "[OK] $tool" -ForegroundColor Green
        } else {
            Write-Host "[MISSING] $tool" -ForegroundColor Red
        }
    }
    Write-Host "===================================`n" -ForegroundColor Cyan
}

# ===== Help & Tips =====
function Show-ProfileTips {
    Write-Host "`n===== PowerShell Profile Quick Reference =====" -ForegroundColor Cyan
    Write-Host "`nSystem & Diagnostics:" -ForegroundColor Yellow
    Write-Host "  sysinfo, hwinfo, uptime     - System information" -ForegroundColor White
    Write-Host "  devcheck                    - Verify dev tools" -ForegroundColor White
    Write-Host "  Show-Path                   - View PATH entries" -ForegroundColor White
    Write-Host "  refreshenv                  - Reload environment" -ForegroundColor White
    Write-Host "  sudo                        - Elevate to admin" -ForegroundColor White
    Write-Host "  ports [number]              - Check port usage" -ForegroundColor White
    Write-Host "  procs [name]                - List processes" -ForegroundColor White
    Write-Host "  Test-Port [host] [port]     - Test connectivity" -ForegroundColor White
    Write-Host "  Get-PublicIP                - Show public IP" -ForegroundColor White
    
    Write-Host "`nGit Shortcuts:" -ForegroundColor Yellow
    Write-Host "  gs, ga, gc [msg], gp, gl, gb, gco [branch]" -ForegroundColor White
    
    Write-Host "`nNavigation:" -ForegroundColor Yellow
    Write-Host "  .., ..., ~, docs, desktop, downloads" -ForegroundColor White
    
    Write-Host "`nDocker:" -ForegroundColor Yellow
    Write-Host "  dps, dpsa, dlog [container], dexec [container], dstop" -ForegroundColor White
    
    Write-Host "`nArchive:" -ForegroundColor Yellow
    Write-Host "  zip [source] [dest], unzip [source] [dest]" -ForegroundColor White
    
    Write-Host "`nLLM Chat:" -ForegroundColor Yellow
    Write-Host "  chat [provider]             - Start chat (default: ollama)" -ForegroundColor White
    Write-Host "  chat-ollama                 - Chat with local Ollama" -ForegroundColor White
    Write-Host "  chat-anthropic              - Chat with Claude API" -ForegroundColor White
    Write-Host "  chat-local                  - Chat with LM Studio" -ForegroundColor White
    Write-Host "  providers                   - Show available providers" -ForegroundColor White
    Write-Host "  Set-ChatApiKey              - Configure API keys" -ForegroundColor White
    Write-Host "  Get-ChatHistory             - View saved sessions" -ForegroundColor White
    Write-Host "  Import-Chat [file]          - Restore session" -ForegroundColor White
    
    Write-Host "`nAI Execution:" -ForegroundColor Yellow
    Write-Host "  AI can now execute commands automatically using:" -ForegroundColor White
    Write-Host "  - EXECUTE: [command]        - Direct execution syntax" -ForegroundColor White
    Write-Host "  - JSON: {\"action\":\"execute\",\"command\":\"...\"}" -ForegroundColor White
    Write-Host "  - All executions are logged and limited to $global:MaxExecutionsPerMessage per message" -ForegroundColor White
    
    Write-Host "`nSafe Actions:" -ForegroundColor Yellow
    Write-Host "  actions                     - View all safe command categories" -ForegroundColor White
    Write-Host "  actions -Category [name]    - View commands in category" -ForegroundColor White
    Write-Host "  safe-check [command]        - Check command safety level" -ForegroundColor White
    Write-Host "  safe-run [command]          - Execute command with confirmation" -ForegroundColor White
    Write-Host "  ai-exec [command]           - Execute command via AI dispatcher" -ForegroundColor White
    Write-Host "  exec-log                    - View AI execution log" -ForegroundColor White
    
    Write-Host "`nSafety & Undo:" -ForegroundColor Yellow
    Write-Host "  session-info                - View current session audit info" -ForegroundColor White
    Write-Host "  file-history                - View tracked file operations" -ForegroundColor White
    Write-Host "  undo                        - Undo last file operation" -ForegroundColor White
    Write-Host "  undo -Count N               - Undo last N file operations" -ForegroundColor White
    
    Write-Host "`nTerminal Tools:" -ForegroundColor Yellow
    Write-Host "  tools                       - Show installed terminal tools" -ForegroundColor White
    Write-Host "  cath [file]                 - Cat with syntax highlighting (bat)" -ForegroundColor White
    Write-Host "  md [file]                   - Render markdown (glow)" -ForegroundColor White
    Write-Host "  br                          - File explorer (broot)" -ForegroundColor White
    Write-Host "  vd [file]                   - Data viewer (visidata)" -ForegroundColor White
    Write-Host "  fh, ff, fd                  - Fuzzy history/file/dir (fzf)" -ForegroundColor White
    Write-Host "  rg [pattern]                - Fast search (ripgrep)" -ForegroundColor White
    
    Write-Host "`nModule Management:" -ForegroundColor Yellow
    Write-Host "  reload-all                  - Reload all modules" -ForegroundColor White
    Write-Host "  reload-intents              - Reload intent system" -ForegroundColor White
    Write-Host "  reload-providers            - Reload chat providers" -ForegroundColor White
    
    Write-Host "`n==============================================`n" -ForegroundColor Cyan
}

# ===== Aliases =====
Set-Alias np notepad
Set-Alias ex explorer
Set-Alias sysinfo Get-SystemInfo
Set-Alias devcheck Test-DevTools
Set-Alias tips Show-ProfileTips
Set-Alias help-profile Show-ProfileTips

# ===== AI Intent Dispatcher System =====
$global:AIExecutionLog = @()
$global:MaxExecutionsPerMessage = 3
$global:ExecutionLogPath = "$env:USERPROFILE\Documents\ChatLogs\AIExecutionLog.json"

# Session tracking for audit trail
$global:SessionId = [guid]::NewGuid().ToString().Substring(0,12)
$global:SessionStartTime = Get-Date
$global:UserId = $env:USERNAME
$global:ComputerName = $env:COMPUTERNAME

# Rate limiting configuration
$global:RateLimitWindow = 60  # seconds
$global:MaxExecutionsPerWindow = 10
$global:ExecutionTimestamps = @()

# Undo/Rollback tracking for file operations
$global:FileOperationHistory = @()
$global:MaxUndoHistory = 50

function Test-RateLimit {
    <#
    .SYNOPSIS
    Check if execution is within rate limits
    #>
    $now = Get-Date
    $windowStart = $now.AddSeconds(-$global:RateLimitWindow)
    
    # Clean old timestamps using ForEach to avoid $_ scope issues
    $validTimestamps = New-Object System.Collections.ArrayList
    foreach ($ts in $global:ExecutionTimestamps) {
        if ($ts -gt $windowStart) {
            [void]$validTimestamps.Add($ts)
        }
    }
    $global:ExecutionTimestamps = @($validTimestamps)
    
    # Check if under limit
    if ($global:ExecutionTimestamps.Count -ge $global:MaxExecutionsPerWindow) {
        $sortedTs = $global:ExecutionTimestamps | Sort-Object
        $oldestInWindow = $sortedTs[0]
        $waitTime = [math]::Ceiling(($oldestInWindow.AddSeconds($global:RateLimitWindow) - $now).TotalSeconds)
        return @{
            Allowed = $false
            Message = "Rate limit exceeded. $($global:ExecutionTimestamps.Count) executions in last $global:RateLimitWindow seconds. Wait $waitTime seconds."
            WaitSeconds = $waitTime
        }
    }
    
    return @{ Allowed = $true }
}

function Add-ExecutionTimestamp {
    $global:ExecutionTimestamps += Get-Date
}

function Add-FileOperation {
    <#
    .SYNOPSIS
    Track a file operation for potential undo
    #>
    param(
        [string]$Operation,  # Create, Copy, Move, Delete
        [string]$Path,
        [string]$OriginalPath = $null,
        [string]$BackupPath = $null,
        [string]$ExecutionId
    )
    
    $entry = @{
        Id = [guid]::NewGuid().ToString().Substring(0,8)
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SessionId = $global:SessionId
        UserId = $global:UserId
        Operation = $Operation
        Path = $Path
        OriginalPath = $OriginalPath
        BackupPath = $BackupPath
        ExecutionId = $ExecutionId
        Undone = $false
    }
    
    $global:FileOperationHistory += $entry
    
    # Trim history if too large
    if ($global:FileOperationHistory.Count -gt $global:MaxUndoHistory) {
        $global:FileOperationHistory = $global:FileOperationHistory[-$global:MaxUndoHistory..-1]
    }
    
    return $entry.Id
}

function Undo-LastFileOperation {
    <#
    .SYNOPSIS
    Undo the last file operation if possible
    #>
    param([int]$Count = 1)
    
    $undoable = $global:FileOperationHistory | Where-Object { -not $_.Undone } | Select-Object -Last $Count
    
    if ($undoable.Count -eq 0) {
        Write-Host "No operations to undo." -ForegroundColor Yellow
        return @{ Success = $false; Message = "No operations to undo" }
    }
    
    $results = @()
    foreach ($op in $undoable) {
        Write-Host "Undoing: $($op.Operation) - $($op.Path)" -ForegroundColor Cyan
        
        try {
            switch ($op.Operation) {
                'Create' {
                    if (Test-Path $op.Path) {
                        Remove-Item $op.Path -Force
                        Write-Host "  Deleted created file: $($op.Path)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    } else {
                        Write-Host "  File no longer exists: $($op.Path)" -ForegroundColor Yellow
                        $results += @{ Success = $false; Operation = $op; Message = "File not found" }
                    }
                }
                'Copy' {
                    if (Test-Path $op.Path) {
                        Remove-Item $op.Path -Force
                        Write-Host "  Deleted copied file: $($op.Path)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    }
                }
                'Move' {
                    if ((Test-Path $op.Path) -and $op.OriginalPath) {
                        Move-Item $op.Path $op.OriginalPath -Force
                        Write-Host "  Moved back to: $($op.OriginalPath)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    }
                }
                'Delete' {
                    if ($op.BackupPath -and (Test-Path $op.BackupPath)) {
                        Copy-Item $op.BackupPath $op.Path -Force
                        Write-Host "  Restored from backup: $($op.Path)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    } else {
                        Write-Host "  Cannot restore - no backup available" -ForegroundColor Red
                        $results += @{ Success = $false; Operation = $op; Message = "No backup" }
                    }
                }
                default {
                    Write-Host "  Unknown operation type: $($op.Operation)" -ForegroundColor Yellow
                    $results += @{ Success = $false; Operation = $op; Message = "Unknown operation" }
                }
            }
        } catch {
            Write-Host "  Undo failed: $($_.Exception.Message)" -ForegroundColor Red
            $results += @{ Success = $false; Operation = $op; Message = $_.Exception.Message }
        }
    }
    
    return $results
}

function Get-FileOperationHistory {
    <#
    .SYNOPSIS
    View recent file operations that can be undone
    #>
    param(
        [int]$Last = 10,
        [switch]$ShowAll
    )
    
    $ops = if ($ShowAll) { $global:FileOperationHistory } else { $global:FileOperationHistory | Select-Object -Last $Last }
    
    if ($ops.Count -eq 0) {
        Write-Host "No file operations recorded." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n===== File Operation History =====" -ForegroundColor Cyan
    foreach ($op in $ops) {
        $statusColor = if ($op.Undone) { 'DarkGray' } else { 'White' }
        $undoStatus = if ($op.Undone) { "[UNDONE]" } else { "" }
        Write-Host "[$($op.Timestamp)] $($op.Operation.PadRight(8)) $undoStatus" -ForegroundColor $statusColor -NoNewline
        Write-Host " $($op.Path)" -ForegroundColor Gray
    }
    Write-Host "=================================`n" -ForegroundColor Cyan
}

function Get-SessionInfo {
    <#
    .SYNOPSIS
    Display current session information for audit purposes
    #>
    $duration = (Get-Date) - $global:SessionStartTime
    
    Write-Host "`n===== Session Information =====" -ForegroundColor Cyan
    Write-Host "  Session ID: $($global:SessionId)" -ForegroundColor White
    Write-Host "  User: $($global:UserId)@$($global:ComputerName)" -ForegroundColor White
    Write-Host "  Started: $($global:SessionStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Duration: $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor White
    Write-Host "  Executions this session: $($global:AIExecutionLog.Count)" -ForegroundColor White
    Write-Host "  File operations tracked: $($global:FileOperationHistory.Count)" -ForegroundColor White
    Write-Host "================================`n" -ForegroundColor Cyan
}

Set-Alias undo Undo-LastFileOperation -Force
Set-Alias file-history Get-FileOperationHistory -Force
Set-Alias session-info Get-SessionInfo -Force

function Invoke-AIExec {
    <#
    .SYNOPSIS
    Universal AI command execution gateway with safety validation and logging
    
    .DESCRIPTION
    Central dispatcher that validates, confirms, executes, and logs AI-requested commands.
    Provides a single choke point for all AI command execution with comprehensive safety checks.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [string]$RequestSource = "AI",
        [switch]$AutoConfirm,
        [switch]$DryRun
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $executionId = [guid]::NewGuid().ToString().Substring(0,8)
    
    # Log the attempt with full audit trail
    $logEntry = @{
        Id = $executionId
        Timestamp = $timestamp
        SessionId = $global:SessionId
        UserId = $global:UserId
        ComputerName = $global:ComputerName
        Source = $RequestSource
        Command = $Command
        Status = "Attempted"
        Output = ""
        Error = $null
        Confirmed = $false
        ExecutionTime = 0
    }
    
    try {
        # Step 0: Check rate limit
        $rateCheck = Test-RateLimit
        if (-not $rateCheck.Allowed) {
            $logEntry.Status = "RateLimited"
            $logEntry.Error = $rateCheck.Message
            $global:AIExecutionLog += $logEntry
            
            Write-Host "[AIExec-$executionId] RATE LIMITED: $($rateCheck.Message)" -ForegroundColor Red
            return @{
                Success = $false
                Output = $rateCheck.Message
                Error = $true
                ExecutionId = $executionId
                RateLimited = $true
            }
        }
        
        # Step 1: Validate command is in safe actions list
        Write-Host "[AIExec-$executionId] Validating command: $Command" -ForegroundColor DarkCyan
        $validation = Test-PowerShellCommand $Command
        
        if (-not $validation.IsValid) {
            $logEntry.Status = "Rejected"
            $logEntry.Error = "Command not in safe actions list"
            $global:AIExecutionLog += $logEntry
            
            Write-Host "[AIExec-$executionId] REJECTED: Command '$Command' is not in the safe actions list" -ForegroundColor Red
            return @{
                Success = $false
                Output = "Command '$Command' is not in the safe actions list"
                Error = $true
                ExecutionId = $executionId
            }
        }
        
        Write-Host "[AIExec-$executionId] Command validated: $($validation.Category) - $($validation.SafetyLevel)" -ForegroundColor Green
        
        # Step 2: Handle confirmation for non-read-only commands
        if ($validation.SafetyLevel -ne 'ReadOnly' -and -not $AutoConfirm -and -not $DryRun) {
            Write-Host "  [AIExec-$executionId] Command requires confirmation" -ForegroundColor Yellow
            $confirmed = Show-CommandConfirmation $Command $validation.SafetyLevel $validation.Description
            $logEntry.Confirmed = $confirmed
            
            if (-not $confirmed) {
                $logEntry.Status = "Cancelled"
                $logEntry.Error = "User cancelled execution"
                $global:AIExecutionLog += $logEntry
                
                Write-Host " [AIExec-$executionId] Execution cancelled by user" -ForegroundColor Yellow
                return @{
                    Success = $false
                    Output = "Command execution cancelled by user"
                    Error = $false
                    ExecutionId = $executionId
                }
            }
        } else {
            $logEntry.Confirmed = $true
        }
        
        # Step 3: Execute command (or simulate for dry run)
        if ($DryRun) {
            Write-Host " [AIExec-$executionId] DRY RUN - Would execute: $Command" -ForegroundColor Magenta
            $logEntry.Status = "DryRun"
            $logEntry.Output = "Dry run completed - command would be executed"
            $global:AIExecutionLog += $logEntry
            
            return @{
                Success = $true
                Output = "DRY RUN: Command '$Command' would be executed"
                Error = $false
                ExecutionId = $executionId
                DryRun = $true
            }
        }
        
        Write-Host " [AIExec-$executionId] Executing command..." -ForegroundColor Cyan
        $startTime = Get-Date
        
        # Execute directly with error handling (simpler and more compatible with PS 5.1)
        try {
            $output = Invoke-Expression $Command 2>&1 | Out-String
            $executionTime = ((Get-Date) - $startTime).TotalSeconds
            
            $logEntry.Status = "Success"
            $logEntry.Output = $output.Trim()
            $logEntry.ExecutionTime = $executionTime
            $global:AIExecutionLog += $logEntry
            
            # Record execution for rate limiting
            Add-ExecutionTimestamp
            
            Write-Host " [AIExec-$executionId] Command completed successfully ($([math]::Round($executionTime, 2))s)" -ForegroundColor Green
            
            return @{
                Success = $true
                Output = $output.Trim()
                Error = $false
                ExecutionId = $executionId
                ExecutionTime = $executionTime
            }
        }
        catch {
            $executionTime = ((Get-Date) - $startTime).TotalSeconds
            $errorMsg = $_.Exception.Message
            
            $logEntry.Status = "ExecutionError"
            $logEntry.Error = $errorMsg
            $logEntry.ExecutionTime = $executionTime
            $global:AIExecutionLog += $logEntry
            
            Write-Host " [AIExec-$executionId] Command error: $errorMsg" -ForegroundColor Red
            
            return @{
                Success = $false
                Output = "Error: $errorMsg"
                Error = $true
                ExecutionId = $executionId
            }
        }
        
    } catch {
        $logEntry.Status = "Error"
        $logEntry.Error = $_.Exception.Message
        if ($startTime) {
            $logEntry.ExecutionTime = ((Get-Date) - $startTime).TotalSeconds
        }
        $global:AIExecutionLog += $logEntry
        
        Write-Host " [AIExec-$executionId] Execution failed: $($_.Exception.Message)" -ForegroundColor Red
        
        return @{
            Success = $false
            Output = "Error: $($_.Exception.Message)"
            Error = $true
            ExecutionId = $executionId
        }
    } finally {
        # Save execution log to disk
        Save-AIExecutionLog
    }
}

function Save-AIExecutionLog {
    try {
        $logDir = Split-Path $global:ExecutionLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        # Keep only last 1000 entries to prevent log bloat
        if ($global:AIExecutionLog.Count -gt 1000) {
            $global:AIExecutionLog = $global:AIExecutionLog[-1000..-1]
        }
        
        $jsonContent = $global:AIExecutionLog | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($global:ExecutionLogPath, $jsonContent, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Host "Warning: Failed to save execution log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-AIExecutionLog {
    param(
        [int]$Last = 10,
        [string]$Status = "",
        [switch]$ShowAll
    )
    
    $logs = $global:AIExecutionLog
    
    if ($Status) {
        $logs = $logs | Where-Object { $_.Status -eq $Status }
    }
    
    if (-not $ShowAll) {
        $logs = $logs | Select-Object -Last $Last
    }
    
    $logs | ForEach-Object {
        $statusColor = switch ($_.Status) {
            'Success' { 'Green' }
            'Error' { 'Red' }
            'Timeout' { 'Yellow' }
            'Rejected' { 'Red' }
            'Cancelled' { 'Yellow' }
            'DryRun' { 'Magenta' }
            default { 'Gray' }
        }
        
        Write-Host "[$($_.Timestamp)] [$($_.Id)] " -ForegroundColor Gray -NoNewline
        Write-Host $_.Status -ForegroundColor $statusColor -NoNewline
        Write-Host " - $($_.Command)" -ForegroundColor White
        
        if ($_.Output -and $_.Output.Length -gt 0) {
            $truncatedOutput = if ($_.Output.Length -gt 100) { $_.Output.Substring(0, 100) + "..." } else { $_.Output }
            Write-Host "    Output: $truncatedOutput" -ForegroundColor DarkGray
        }
        
        if ($_.Error) {
            Write-Host "    Error: $($_.Error)" -ForegroundColor Red
        }
        
        if ($_.ExecutionTime -gt 0) {
            Write-Host "    Time: $([math]::Round($_.ExecutionTime, 2))s" -ForegroundColor DarkCyan
        }
        
        Write-Host ""
    }
}

# Load existing execution log on startup
if (Test-Path $global:ExecutionLogPath) {
    try {
        $global:AIExecutionLog = Get-Content $global:ExecutionLogPath -Raw | ConvertFrom-Json
        if (-not $global:AIExecutionLog) { $global:AIExecutionLog = @() }
    } catch {
        $global:AIExecutionLog = @()
    }
}

# ===== LLM Chat Shell with Enhanced Error Handling and Token Awareness =====
$global:ChatSessionHistory = @()

function Get-EstimatedTokenCount {
    $totalChars = ($global:ChatSessionHistory | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum
    return [math]::Ceiling($totalChars / 4)
}

# ===== Data-Driven Natural Language Mappings =====
$global:NLMappingsPath = "$PSScriptRoot\NaturalLanguageMappings.json"
$global:NLMappings = $null

function Import-NaturalLanguageMappings {
    <#
    .SYNOPSIS
    Load natural language mappings from JSON file
    #>
    if (Test-Path $global:NLMappingsPath) {
        try {
            $global:NLMappings = Get-Content $global:NLMappingsPath -Raw | ConvertFrom-Json
            return $true
        } catch {
            Write-Host "Warning: Failed to load NL mappings: $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }
    return $false
}

# Load mappings on startup
Import-NaturalLanguageMappings | Out-Null

function Convert-NaturalLanguageToCommand {
    param([string]$InputText)
    
    $lowerInput = $InputText.ToLower().Trim()
    
    # Try data-driven mappings first if loaded
    if ($global:NLMappings) {
        # Check exact command mappings
        $commands = $global:NLMappings.mappings.commands
        if ($commands.PSObject.Properties.Name -contains $lowerInput) {
            $command = $commands.$lowerInput
            Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
            return "EXECUTE: $command"
        }
        
        # Check for "please" variants
        $cleanInput = $lowerInput -replace '^please\s+', '' -replace '\s+please$', ''
        if ($commands.PSObject.Properties.Name -contains $cleanInput) {
            $command = $commands.$cleanInput
            Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
            return "EXECUTE: $command"
        }
        
        # Check application shortcuts (e.g., "open word" -> "Start-Process winword")
        $apps = $global:NLMappings.mappings.applications
        foreach ($verb in @('open', 'start', 'launch', 'run')) {
            if ($lowerInput -match "^$verb\s+(.+)$") {
                $appName = $Matches[1].Trim()
                if ($apps.PSObject.Properties.Name -contains $appName) {
                    $executable = $apps.$appName
                    $command = "Start-Process $executable"
                    Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
                    return "EXECUTE: $command"
                }
            }
        }
        
        # Check regex patterns
        $patterns = $global:NLMappings.mappings.patterns
        foreach ($pattern in $patterns.PSObject.Properties) {
            if ($lowerInput -match $pattern.Name) {
                $command = $pattern.Value
                # Replace capture groups
                for ($i = 1; $i -le 9; $i++) {
                    if ($Matches[$i]) {
                        $command = $command -replace "\`$$i", $Matches[$i]
                    }
                }
                Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
                return "EXECUTE: $command"
            }
        }
    }
    
    # Fallback: hardcoded mappings for reliability
    $fallbackMappings = @{
        'open word' = 'Start-Process winword'
        'open excel' = 'Start-Process excel'
        'open notepad' = 'Start-Process notepad'
        'open calculator' = 'Start-Process calc'
        'list files' = 'Get-ChildItem'
        'show files' = 'Get-ChildItem'
        'show processes' = 'Get-Process'
        'list processes' = 'Get-Process'
    }
    
    foreach ($phrase in $fallbackMappings.Keys) {
        if ($lowerInput -eq $phrase -or $lowerInput -match [regex]::Escape($phrase)) {
            $command = $fallbackMappings[$phrase]
            Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
            return "EXECUTE: $command"
        }
    }
    
    # No translation needed
    return $InputText
}

function Get-TokenEstimate {
    <#
    .SYNOPSIS
    Get chars-per-token estimate for a provider from config
    #>
    param([string]$Provider = 'default')
    
    if ($global:NLMappings -and $global:NLMappings.tokenEstimates) {
        $estimates = $global:NLMappings.tokenEstimates
        if ($estimates.providers.PSObject.Properties.Name -contains $Provider) {
            return $estimates.providers.$Provider
        }
        return $estimates.default
    }
    return 4.0  # Default fallback
}

function Start-ChatSession {
    param(
        [ValidateSet('ollama', 'anthropic', 'lmstudio', 'openai')]
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model = $null,
        [double]$Temperature = 0.7,
        [int]$MaxTokens = 4096,
        [switch]$IncludeSafeCommands,
        [switch]$Stream,
        [switch]$AutoTrim
    )
    
    # Get provider config
    $providerConfig = $global:ChatProviders[$Provider]
    if (-not $providerConfig) {
        Write-Host "Unknown provider: $Provider" -ForegroundColor Red
        return
    }
    
    # Use default model if not specified
    if (-not $Model) {
        $Model = $providerConfig.DefaultModel
    }
    
    # Check API key if required
    if ($providerConfig.ApiKeyRequired) {
        $apiKey = Get-ChatApiKey $Provider
        if (-not $apiKey) {
            Write-Host "API key required for $($providerConfig.Name)." -ForegroundColor Red
            Write-Host "Set it with: Set-ChatApiKey -Provider $Provider -ApiKey 'your-key'" -ForegroundColor Yellow
            return
        }
    }

    Write-Host "`nEntering LLM chat mode" -ForegroundColor Cyan
    Write-Host "  Provider: $($providerConfig.Name)" -ForegroundColor Gray
    Write-Host "  Model: $Model" -ForegroundColor Gray
    if ($Stream) { Write-Host "  Streaming: enabled" -ForegroundColor Gray }
    if ($AutoTrim) { Write-Host "  Auto-trim: enabled" -ForegroundColor Gray }
    Write-Host "Type 'exit' to quit, 'clear' to reset, 'save' to archive, 'tokens' for usage, 'switch' to change provider." -ForegroundColor DarkGray
    
    # Clear history and initialize with safe commands context if requested
    $global:ChatSessionHistory = @()
    $systemPrompt = $null
    
    if ($IncludeSafeCommands) {
        $safeCommandsPrompt = Get-SafeCommandsPrompt
        
        # Anthropic handles system prompts differently
        if ($Provider -eq 'anthropic') {
            $systemPrompt = $safeCommandsPrompt
        } else {
            # For OpenAI-compatible APIs, add as user message with acknowledgment
            $global:ChatSessionHistory += @{ role = "user"; content = $safeCommandsPrompt }
            $global:ChatSessionHistory += @{ role = "assistant"; content = "Understood. I have access to PowerShell commands and intent actions. I'm ready to help." }
        }
        Write-Host "Safe commands context loaded." -ForegroundColor Green
    }
    Write-Host ""

    $continue = $true
    while ($continue) {
        Write-Host -NoNewline "`nYou> " -ForegroundColor Yellow
        $inputText = Read-Host

        switch -Regex ($inputText) {
            '^exit$'   { 
                Write-Host "`nSession ended." -ForegroundColor Green
                $continue = $false
                break
            }
            '^clear$'  { 
                $global:ChatSessionHistory = @()
                Write-Host "Memory cleared." -ForegroundColor DarkGray
                continue 
            }
            '^save$'   { 
                Save-Chat
                continue 
            }
            '^tokens$' { 
                $est = Get-EstimatedTokenCount
                Write-Host "Estimated tokens in context: $est / $MaxTokens" -ForegroundColor Cyan
                continue 
            }
            '^commands$' {
                Write-Host "`nSafe PowerShell Commands Available:" -ForegroundColor Cyan
                Get-SafeActions
                continue
            }
            '^switch$' {
                Show-ChatProviders
                Write-Host "Current: $Provider" -ForegroundColor Cyan
                $newProvider = Read-Host "Enter provider name (or press Enter to keep current)"
                if ($newProvider -and $global:ChatProviders.ContainsKey($newProvider)) {
                    $Provider = $newProvider
                    $providerConfig = $global:ChatProviders[$Provider]
                    $Model = $providerConfig.DefaultModel
                    Write-Host "Switched to $($providerConfig.Name) ($Model)" -ForegroundColor Green
                }
                continue
            }
            '^model\s+(.+)$' {
                $Model = $Matches[1]
                Write-Host "Model changed to: $Model" -ForegroundColor Green
                continue
            }
            '^\s*$'    { continue }
        }

        if (-not $continue) { break }

        # Don't preprocess user input - let the AI interpret naturally
        # The AI will use intents/commands in its response which we parse
        $global:ChatSessionHistory += @{ role = "user"; content = $inputText }
        
        $estimatedTokens = Get-EstimatedTokenCount
        
        # Auto-trim context if enabled and approaching limit
        if ($AutoTrim -and $estimatedTokens -gt ($MaxTokens * 0.8)) {
            $trimResult = Get-TrimmedMessages -Messages $global:ChatSessionHistory -MaxTokens $MaxTokens -KeepFirstN 2
            if ($trimResult.Trimmed) {
                $global:ChatSessionHistory = $trimResult.Messages
                Write-Host "  [Auto-trimmed: removed $($trimResult.RemovedCount) old messages]" -ForegroundColor DarkYellow
                $estimatedTokens = $trimResult.EstimatedTokens
            }
        } elseif ($estimatedTokens -gt ($MaxTokens * 0.8)) {
            Write-Host "  Approaching token limit ($estimatedTokens / $MaxTokens). Consider using 'clear' to reset." -ForegroundColor Yellow
        }

        # Prepare messages for API call
        $messagesToSend = $global:ChatSessionHistory

        try {
            # Show thinking indicator (not for streaming - it prints directly)
            if (-not $Stream) {
                Write-Host "`n:<) Thinking..." -ForegroundColor DarkGray
            } else {
                Write-Host "`nAI> " -ForegroundColor Cyan -NoNewline
            }
            
            # Use unified chat completion with optional streaming
            $response = Invoke-ChatCompletion -Messages $messagesToSend -Provider $Provider -Model $Model -Temperature $Temperature -MaxTokens $MaxTokens -SystemPrompt $systemPrompt -Stream:$Stream
            
            $reply = $response.Content

            # Store AI response as-is (don't translate - that's only for user input)
            $global:ChatSessionHistory += @{ role = "assistant"; content = $reply }

            # Only show formatted output if not streaming (streaming already printed)
            if (-not $response.Streamed) {
                Write-Host "`nAI>" -ForegroundColor Cyan
                $parsedReply = Convert-JsonIntent $reply
                Format-Markdown $parsedReply
            } else {
                # For streamed responses, still process intents/commands
                $parsedReply = Convert-JsonIntent $reply
                # Intent execution results will be shown inline
            }
            
            # Show token usage if available
            if ($response.Usage) {
                $totalTokens = $response.Usage.total_tokens
                if ($totalTokens) {
                    Write-Host "`n[Tokens: $totalTokens]" -ForegroundColor DarkGray
                }
            }
        }
        catch {
            Write-Host "`nERROR: Request failed" -ForegroundColor Red
            Write-Host "$($_.Exception.Message)" -ForegroundColor Yellow
            
            # Remove the failed user message from history
            if ($global:ChatSessionHistory.Count -gt 0) {
                $global:ChatSessionHistory = $global:ChatSessionHistory[0..($global:ChatSessionHistory.Count - 2)]
            }
        }
    }
}

function Get-CommandSafetyLevel($command) {
    $baseCommand = ($command -split '\s+')[0].ToLower()
    
    foreach ($level in $global:CommandSafety.Keys) {
        if ($global:CommandSafety[$level] -contains $baseCommand) {
            return $level
        }
    }
    return 'Unknown'
}

function Show-CommandConfirmation($command, $safetyLevel, $description) {
    
    switch ($safetyLevel) {
        'SafeWrite' {
            Write-Host "`nSAFE WRITE OPERATION" -ForegroundColor Yellow
            Write-Host "Command: $command" -ForegroundColor White
            Write-Host "Description: $description" -ForegroundColor Gray
            Write-Host "This command will create/modify files but is considered safe." -ForegroundColor Gray
            
            do {
                $response = Read-Host "Proceed? (y/n)"
            } while ($response -notin @('y', 'n', 'yes', 'no'))
            
            return $response -in @('y', 'yes')
        }
        
        'RequiresConfirmation' {
            Write-Host "`n CONFIRMATION REQUIRED" -ForegroundColor Red
            Write-Host "Command: $command" -ForegroundColor White
            Write-Host "Description: $description" -ForegroundColor Gray
            Write-Host "This command can modify system state or execute code." -ForegroundColor Yellow
            Write-Host "Please review carefully before proceeding." -ForegroundColor Yellow
            
            do {
                $response = Read-Host "Are you sure you want to proceed? (yes/no)"
            } while ($response -notin @('yes', 'no'))
            
            return $response -eq 'yes'
        }
        
        default {
            return $true  # ReadOnly commands don't need confirmation
        }
    }
}

function Test-PowerShellCommand($command) {
    # Extract the base command (first word)
    $baseCommand = ($command -split '\s+')[0].ToLower()
    
    # Check if command exists in Actions table
    foreach ($category in $global:Actions.Keys) {
        if ($global:Actions[$category].ContainsKey($baseCommand)) {
            $safetyLevel = Get-CommandSafetyLevel $baseCommand
            return @{
                IsValid = $true
                Category = $category
                Description = $global:Actions[$category][$baseCommand]
                Command = $baseCommand
                SafetyLevel = $safetyLevel
            }
        }
    }
    
    return @{
        IsValid = $false
        Command = $baseCommand
        SafetyLevel = 'Unknown'
    }
}

function Invoke-SafeCommand($command) {
    # Execute a safe command with proper validation and confirmation
    $validation = Test-PowerShellCommand $command
    
    if (-not $validation.IsValid) {
        return @{
            Success = $false
            Output = "Command '$command' is not in the safe actions list"
            Error = $true
        }
    }
    
    # Check if confirmation is needed
    if ($validation.SafetyLevel -ne 'ReadOnly') {
        Write-Host "`nCommand requires confirmation: $command" -ForegroundColor Yellow
        $confirmed = Show-CommandConfirmation $command $validation.SafetyLevel $validation.Description
        if (-not $confirmed) {
            return @{
                Success = $false
                Output = "Command execution cancelled by user"
                Error = $false
            }
        }
    }
    
    try {
        Write-Host "Executing: $command" -ForegroundColor Cyan
        $output = Invoke-Expression $command | Out-String
        Write-Host "Command completed successfully." -ForegroundColor Green
        
        return @{
            Success = $true
            Output = $output.Trim()
            Error = $false
        }
    } catch {
        return @{
            Success = $false
            Output = "Error: $($_.Exception.Message)"
            Error = $true
        }
    }
}

function Convert-JsonIntent($text) {
    # Enhanced parser for JSON content and PowerShell command validation with automatic execution
    $lines = $text -split "`n"
    $result = @()
    $inJsonBlock = $false
    $inCodeBlock = $false
    $jsonBuffer = @()
    $braceCount = 0
    $codeBlockType = ''
    $executionResults = @()
    $executionCount = 0
    
    foreach ($line in $lines) {
        # Handle code blocks
        if ($line -match '^```(\w*)') {
            if (-not $inCodeBlock) {
                $inCodeBlock = $true
                $codeBlockType = $Matches[1].ToLower()
                $result += $line
            } else {
                $inCodeBlock = $false
                $codeBlockType = ''
                $result += $line
            }
            continue
        }
        
        # Process PowerShell commands in code blocks
        if ($inCodeBlock -and ($codeBlockType -eq 'powershell' -or $codeBlockType -eq 'ps1' -or $codeBlockType -eq '')) {
            # Check if line looks like a PowerShell command
            if ($line -match '^\s*([a-zA-Z][a-zA-Z0-9-]*)(\s|$)') {
                $validation = Test-PowerShellCommand $line.Trim()
                if ($validation.IsValid) {
                    $safetyIcon = switch ($validation.SafetyLevel) {
                        'ReadOnly' { 'READONLY' }
                        'SafeWrite' { 'SAFEWRITE' }
                        'RequiresConfirmation' { 'CONFIRM' }
                        default { 'UNKNOWN' }
                    }
                    $result += "$line  # $safetyIcon $($validation.SafetyLevel): $($validation.Category) - $($validation.Description)"
                } else {
                    $result += "$line  #  Not in safe actions list"
                }
            } else {
                $result += $line
            }
            continue
        }
        
        # Handle JSON execution requests and intent actions
        if (-not $inCodeBlock -and -not $inJsonBlock) {
            # Check for JSON intent action request
            if ($line -match '^\s*\{.*"intent".*:.*\}\s*$') {
                try {
                    $jsonRequest = $line | ConvertFrom-Json
                    if ($jsonRequest.intent -and $executionCount -lt $global:MaxExecutionsPerMessage) {
                        $executionCount++
                        $result += "**Intent Action**: ``$($jsonRequest.intent)``"
                        $result += ""
                        
                        # Extract first parameter - AI may use 'param', 'query', 'path', 'url', 'name', etc.
                        $param1 = if ($jsonRequest.param) { $jsonRequest.param }
                                  elseif ($jsonRequest.query) { $jsonRequest.query }
                                  elseif ($jsonRequest.path) { $jsonRequest.path }
                                  elseif ($jsonRequest.url) { $jsonRequest.url }
                                  elseif ($jsonRequest.name) { $jsonRequest.name }
                                  elseif ($jsonRequest.topic) { $jsonRequest.topic }
                                  elseif ($jsonRequest.text) { $jsonRequest.text }
                                  else { "" }
                        
                        # Use the intent router
                        $intentResult = Invoke-IntentAction -Intent $jsonRequest.intent -Param $param1 -Param2 $jsonRequest.param2 -AutoConfirm
                        $executionResults += $intentResult
                        
                        if ($intentResult.Success) {
                            $result += "**Intent Executed** (ID: $($intentResult.IntentId))"
                            if ($intentResult.Output) {
                                $result += "$($intentResult.Output)"
                            }
                            if ($intentResult.ExecutionTime) {
                                $result += "*Execution time: $([math]::Round($intentResult.ExecutionTime, 2))s*"
                            }
                        } else {
                            $result += "**Intent Failed** (ID: $($intentResult.IntentId))"
                            $result += "``$($intentResult.Output)``"
                        }
                        $result += ""
                        continue
                    }
                } catch {
                    # Not valid intent JSON, continue with normal processing
                }
            }
            
            # Check for JSON execution request
            if ($line -match '^\s*\{.*"action".*:.*"execute".*\}\s*$' -or $line -match '^\s*\{.*"execute".*:.*\}\s*$') {
                try {
                    $jsonRequest = $line | ConvertFrom-Json
                    $commandToExecute = ""
                    
                    # Support different JSON formats
                    if ($jsonRequest.action -eq "execute" -and $jsonRequest.command) {
                        $commandToExecute = $jsonRequest.command
                    } elseif ($jsonRequest.execute) {
                        $commandToExecute = $jsonRequest.execute
                    }
                    
                    if ($commandToExecute -and $executionCount -lt $global:MaxExecutionsPerMessage) {
                        $executionCount++
                        $result += "**JSON Execution Request**: ``$commandToExecute``"
                        $result += ""
                        
                        # Use the new AI dispatcher
                        $execResult = Invoke-AIExec -Command $commandToExecute -RequestSource "AI-JSON"
                        $executionResults += $execResult
                        
                        if ($execResult.Success) {
                            $result += "**Execution Successful** (ID: $($execResult.ExecutionId))"
                            if ($execResult.Output -and $execResult.Output.Length -gt 0) {
                                $result += '```'
                                $result += $execResult.Output
                                $result += '```'
                            }
                            if ($execResult.ExecutionTime) {
                                $result += "*Execution time: $([math]::Round($execResult.ExecutionTime, 2))s*"
                            }
                        } else {
                            if ($execResult.Error) {
                                $result += "**Execution Failed** (ID: $($execResult.ExecutionId))"
                            } else {
                                $result += "**Execution Cancelled** (ID: $($execResult.ExecutionId))"
                            }
                            $result += "``$($execResult.Output)``"
                        }
                        $result += ""
                        continue
                    } elseif ($executionCount -ge $global:MaxExecutionsPerMessage) {
                        $result += "**Execution limit reached** ($global:MaxExecutionsPerMessage per message)"
                        $result += ""
                    }
                } catch {
                    # Not valid JSON, continue with normal processing
                }
            }
            
            # Check for execution request syntax: EXECUTE: command or RUN: command
            if ($line -match '^\s*(EXECUTE|RUN):\s*(.+)$') {
                $commandToExecute = $Matches[2].Trim()
                
                if ($executionCount -lt $global:MaxExecutionsPerMessage) {
                    $executionCount++
                    $result += "**Executing Command**: ``$commandToExecute``"
                    $result += ""
                    
                    # Use the new AI dispatcher instead of Execute-SafeCommand
                    $execResult = Invoke-AIExec -Command $commandToExecute -RequestSource "AI-EXECUTE"
                    $executionResults += $execResult
                    
                    if ($execResult.Success) {
                        $result += "**Execution Successful** (ID: $($execResult.ExecutionId))"
                        if ($execResult.Output -and $execResult.Output.Length -gt 0) {
                            $result += '```'
                            $result += $execResult.Output
                            $result += '```'
                        }
                        if ($execResult.ExecutionTime) {
                            $result += "*Execution time: $([math]::Round($execResult.ExecutionTime, 2))s*"
                        }
                    } else {
                        if ($execResult.Error) {
                            $result += "**Execution Failed** (ID: $($execResult.ExecutionId))"
                        } else {
                            $result += "**Execution Cancelled** (ID: $($execResult.ExecutionId))"
                        }
                        $result += "``$($execResult.Output)``"
                    }
                    $result += ""
                    continue
                } else {
                    $result += "**Execution limit reached** ($global:MaxExecutionsPerMessage per message)"
                    $result += "Command: ``$commandToExecute``"
                    $result += ""
                    continue
                }
            }
            # Regular command suggestion (no execution)
            elseif ($line -match '^\s*([a-zA-Z][a-zA-Z0-9-]*)(\s|$)' -and $line -notmatch '^\s*#') {
                $validation = Test-PowerShellCommand $line.Trim()
                if ($validation.IsValid) {
                    $safetyIcon = switch ($validation.SafetyLevel) {
                        'ReadOnly' { 'Read Only' }
                        'SafeWrite' { 'Safe Write' }
                        'RequiresConfirmation' { 'Confirmation Required' }
                        default { 'Clarification Required' }
                    }

                    $result += '```powershell'
                    $result += "$($line.Trim())  # $safetyIcon $($validation.SafetyLevel): $($validation.Category)"
                    $result += '```'
                    $result += "Description: $($validation.Description)"
                    $result += "**To execute this command, use**: ``EXECUTE: $($line.Trim())``"

                    # Add confirmation prompt for non-read-only commands
                    if ($validation.SafetyLevel -ne 'ReadOnly') {
                        $result += ""
                        $result += "Confirmation Required: This command requires user confirmation before execution."
                        if ($validation.SafetyLevel -eq 'RequiresConfirmation') {
                            $result += "High Impact: Please review this command carefully as it can modify system state."
                        }
                    }
                    continue
                }
            }
        }

        # Handle JSON detection (existing logic)
        if (-not $inCodeBlock) {
            # Detect potential JSON start
            if ($line -match '^\s*\{' -or ($line -match '\{.*:.*\}' -and $line -match '".*"')) {
                $inJsonBlock = $true
                $jsonBuffer = @($line)
                $braceCount = ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count - ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count

                # Check if it's a single-line JSON
                if ($braceCount -eq 0) {
                    try {
                        $jsonObj = $line | ConvertFrom-Json -ErrorAction Stop
                        $result += '```json'
                        $result += ($jsonObj | ConvertTo-Json -Depth 10)
                        $result += '```'
                        $inJsonBlock = $false
                        $jsonBuffer = @()
                    } catch {
                        # Not valid JSON, treat as regular text
                        $result += $line
                        $inJsonBlock = $false
                        $jsonBuffer = @()
                    }
                }
            }
            elseif ($inJsonBlock) {
                $jsonBuffer += $line
                $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count - ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count

                # Check if JSON block is complete
                if ($braceCount -le 0) {
                    $jsonText = $jsonBuffer -join "`n"
                    try {
                        $jsonObj = $jsonText | ConvertFrom-Json -ErrorAction Stop
                        $result += '```json'
                        $result += ($jsonObj | ConvertTo-Json -Depth 10)
                        $result += '```'
                    } catch {
                        # Not valid JSON, add as regular text
                        $result += $jsonBuffer
                    }
                    $inJsonBlock = $false
                    $jsonBuffer = @()
                    $braceCount = 0
                }
            }
            else {
                # Regular text line
                $result += $line
            }
        } else {
            # Inside code block, add as-is
            $result += $line
        }
    }
    
    # Handle incomplete JSON blocks (add as regular text)
    if ($inJsonBlock -and $jsonBuffer.Count -gt 0) {
        $result += $jsonBuffer
    }
    
    # Add execution results to chat history for AI feedback loop
    if ($executionResults.Count -gt 0) {
        $executionSummary = "\n\n--- Execution Summary ---\n"
        foreach ($execResult in $executionResults) {
            $status = if ($execResult.Success) { "✅ SUCCESS" } elseif ($execResult.Error) { "❌ ERROR" } else { "🚫 CANCELLED" }
            $executionSummary += "$status (ID: $($execResult.ExecutionId)): $($execResult.Output.Substring(0, [Math]::Min(100, $execResult.Output.Length)))\n"
        }
        $executionSummary += "--- End Summary ---"
        
        # Add to chat history so AI can see execution results
        $global:ChatSessionHistory += @{ role = "system"; content = $executionSummary }
    }
    
    return $result -join "`n"
}

function Format-Markdown($text) {
    # Ensure we have a string
    if ($null -eq $text -or $text -isnot [string]) {
        if ($text) { Write-Host $text }
        return
    }
    
    # Use glow if available for beautiful markdown rendering
    if ($global:UseGlowForMarkdown -and (Get-Command glow -ErrorAction SilentlyContinue)) {
        try {
            Write-Output $text | glow -
            return
        } catch {
            # Fall through to ANSI rendering
        }
    }
    
    # Fallback: ANSI escape sequence rendering
    $lines = $text -split "`n"
    $inCode = $false
    
    foreach ($line in $lines) {
        if ($line -match '^```') {
            $inCode = -not $inCode
            Write-Host '```' -ForegroundColor DarkGray
            continue
        }

        if ($inCode) {
            if ($line -match '^(#|//)') {
                Write-Host $line -ForegroundColor DarkGreen
            } elseif ($line -match '(\$|\w+\s*=)') {
                Write-Host $line -ForegroundColor Yellow
            } elseif ($line -match 'function|def|class|import|from|if|else|return|for|while|const|let|var') {
                Write-Host $line -ForegroundColor Magenta
            } else {
                Write-Host $line -ForegroundColor Gray
            }
        } else {
            # Handle headers
            if ($line -match '^#{1,3}\s+(.+)$') {
                Write-Host $Matches[1] -ForegroundColor Cyan
            }
            # Handle bold **text** - strip markers and print
            elseif ($line -match '\*\*(.+?)\*\*') {
                $cleaned = $line -replace '\*\*(.+?)\*\*', '$1'
                Write-Host $cleaned -ForegroundColor White
            }
            # Handle inline code `text` - strip markers and print in yellow
            elseif ($line -match '`(.+?)`') {
                $cleaned = $line -replace '`(.+?)`', '$1'
                Write-Host $cleaned -ForegroundColor Yellow
            }
            else {
                Write-Host $line -ForegroundColor White
            }
        }
    }
}

# ===== Persistence Helpers =====
function Save-Chat {
    $path = "$env:USERPROFILE\Documents\ChatLogs"
    if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
    Get-ChildItem $path -Filter "*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force
    $file = "$path\Chat_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $jsonContent = $global:ChatSessionHistory | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($file, $jsonContent, [System.Text.Encoding]::UTF8)
    Write-Host "Chat saved to $file" -ForegroundColor Green
}


function Import-Chat($file) {
    if (Test-Path $file) {
        $global:ChatSessionHistory = Get-Content $file -Raw | ConvertFrom-Json
        Write-Host "Chat history loaded: $file" -ForegroundColor Cyan
    } else {
        Write-Host "File not found: $file" -ForegroundColor Red
    }
}

function Get-ChatHistory {
    $path = "$env:USERPROFILE\Documents\ChatLogs"
    if (Test-Path $path) {
        Get-ChildItem $path -Filter "*.json" | Sort-Object LastWriteTime -Descending | 
        Select-Object Name, LastWriteTime | Format-Table -AutoSize
    } else {
        Write-Host "No chat logs directory found" -ForegroundColor Yellow
    }
}

function chat {
    param(
        [ValidateSet('ollama', 'anthropic', 'lmstudio', 'openai')]
        [string]$Provider = $global:DefaultChatProvider,
        [switch]$Stream,
        [switch]$AutoTrim
    )
    Start-ChatSession -Provider $Provider -IncludeSafeCommands -Stream:$Stream -AutoTrim:$AutoTrim
}

function chat-ollama { Start-ChatSession -Provider ollama -IncludeSafeCommands -Stream -AutoTrim }
function chat-anthropic { Start-ChatSession -Provider anthropic -IncludeSafeCommands -AutoTrim }
function chat-local { Start-ChatSession -Provider lmstudio -IncludeSafeCommands -Stream -AutoTrim }

# ===== Safe Actions Table with Safety Classifications =====
# Safety Levels: 'ReadOnly', 'SafeWrite', 'RequiresConfirmation'

# Command Safety Classifications
$global:CommandSafety = @{
    # Read-Only Commands (no confirmation needed)
    'ReadOnly' = @(
        'get-computerinfo', 'get-process', 'get-service', 'get-hotfix', 'get-eventlog',
        'get-wmiobject', 'get-ciminstance', 'get-date', 'get-uptime', 'get-timezone',
        'get-childitem', 'get-item', 'get-itemproperty', 'get-content', 'test-path',
        'resolve-path', 'get-location', 'get-psdrive', 'measure-object', 'select-string',
        'test-netconnection', 'get-netadapter', 'get-netipaddress', 'get-netroute',
        'resolve-dnsname', 'test-connection', 'get-nettcpconnection',
        'convertto-json', 'convertfrom-json', 'convertto-csv', 'convertfrom-csv', 'convertto-xml',
        'format-table', 'format-list', 'sort-object', 'group-object', 'where-object', 'select-object',
        'measure-command', 'get-random',
        'get-variable', 'get-alias', 'get-command', 'get-module', 'get-pssnapin',
        'get-executionpolicy', 'get-host', 'get-culture',
        'get-help', 'get-member', 'compare-object'
    )
    
    # Safe Write Operations (minimal confirmation)
    'SafeWrite' = @(
        'new-temporaryfile', 'out-file', 'export-csv', 'export-clixml'
    )
    
    # Requires Confirmation (potentially impactful)
    'RequiresConfirmation' = @(
        'copy-item', 'compress-archive', 'expand-archive', 'invoke-expression', 'invoke-command', 'start-process'
    )
}

$global:Actions = @{
    # System Information (Read-only)
    'SystemInfo' = @{
        'get-computerinfo' = 'Get detailed computer information'
        'get-process' = 'List running processes'
        'get-service' = 'List system services'
        'get-hotfix' = 'List installed updates'
        'get-eventlog' = 'Read event logs (specify -LogName)'
        'get-wmiobject' = 'Query WMI objects (read-only)'
        'get-ciminstance' = 'Query CIM instances (read-only)'
        'get-date' = 'Get current date and time'
        'get-uptime' = 'Get system uptime'
        'get-timezone' = 'Get system timezone'
    }
    
    # File System (Read-only and safe writes)
    'FileSystem' = @{
        'get-childitem' = 'List directory contents'
        'get-item' = 'Get file/directory information'
        'get-itemProperty' = 'Get file/directory properties'
        'get-content' = 'Read file contents'
        'test-path' = 'Test if path exists'
        'resolve-path' = 'Resolve path to absolute'
        'get-location' = 'Get current directory'
        'get-psdrive' = 'List available drives'
        'measure-object' = 'Measure file/object properties'
        'select-string' = 'Search text in files'
    }
    
    # Network (Read-only)
    'Network' = @{
        'test-netconnection' = 'Test network connectivity'
        'get-netadapter' = 'Get network adapters'
        'get-netipaddress' = 'Get IP addresses'
        'get-netroute' = 'Get routing table'
        'resolve-dnsname' = 'Resolve DNS names'
        'test-connection' = 'Ping hosts'
        'get-nettcpconnection' = 'Get TCP connections'
    }
    
    # Text Processing
    'TextProcessing' = @{
        'convertto-json' = 'Convert objects to JSON'
        'convertfrom-json' = 'Parse JSON to objects'
        'convertto-csv' = 'Convert objects to CSV'
        'convertfrom-csv' = 'Parse CSV to objects'
        'convertto-xml' = 'Convert objects to XML'
        'format-table' = 'Format output as table'
        'format-list' = 'Format output as list'
        'sort-object' = 'Sort objects'
        'group-object' = 'Group objects'
        'where-object' = 'Filter objects'
        'select-object' = 'Select object properties'
    }
    
    # Math and Calculations
    'Math' = @{
        'measure-command' = 'Measure command execution time'
        'get-random' = 'Generate random numbers'
        'get-date' = 'Date calculations'
    }
    
    # Environment (Read-only)
    'Environment' = @{
        'get-variable' = 'Get PowerShell variables'
        'get-alias' = 'Get command aliases'
        'get-command' = 'Get available commands'
        'get-module' = 'Get loaded modules'
        'get-pssnapin' = 'Get PowerShell snap-ins'
        'get-executionpolicy' = 'Get execution policy'
        'get-host' = 'Get PowerShell host info'
        'get-culture' = 'Get system culture'
    }
    
    # Safe File Operations
    'SafeFileOps' = @{
        'new-temporaryfile' = 'Create temporary file'
        'copy-item' = 'Copy files (use with caution)'
        'out-file' = 'Write to file (specify path)'
        'export-csv' = 'Export to CSV file'
        'export-clixml' = 'Export to XML file'
        'compress-archive' = 'Create ZIP archives'
        'expand-archive' = 'Extract ZIP archives'
    }
    
    # Registry (Read-only)
    'Registry' = @{
        'get-itemproperty' = 'Read registry values'
        'get-childitem' = 'List registry keys'
        'test-path' = 'Test registry path exists'
    }
    
    # PowerShell Specific
    'PowerShell' = @{
        'get-help' = 'Get command help'
        'get-member' = 'Get object members'
        'measure-object' = 'Measure object properties'
        'compare-object' = 'Compare objects'
        'invoke-expression' = 'Execute PowerShell expressions (use carefully)'
        'invoke-command' = 'Execute commands (local only)'
    }
    
    # Application Launching
    'ApplicationLaunch' = @{
        'start-process' = 'Launch applications and executables'
    }
}

function Get-SafeActions {
    param(
        [string]$Category = '',
        [string]$Command = ''
    )
    
    if ($Command) {
        # Search for specific command across all categories
        foreach ($cat in $global:Actions.Keys) {
            if ($global:Actions[$cat].ContainsKey($Command.ToLower())) {
                return @{
                    Category = $cat
                    Command = $Command.ToLower()
                    Description = $global:Actions[$cat][$Command.ToLower()]
                }
            }
        }
        Write-Host "Command '$Command' not found in safe actions" -ForegroundColor Yellow
        return $null
    }
    
    if ($Category) {
        # Show commands in specific category
        if ($global:Actions.ContainsKey($Category)) {
            Write-Host "`n===== $Category Commands =====" -ForegroundColor Cyan
            $global:Actions[$Category].GetEnumerator() | Sort-Object Key | ForEach-Object {
                Write-Host "  $($_.Key)" -ForegroundColor Green -NoNewline
                Write-Host " - $($_.Value)" -ForegroundColor Gray
            }
            Write-Host ""
        } else {
            Write-Host "Category '$Category' not found" -ForegroundColor Red
            Write-Host "Available categories: $($global:Actions.Keys -join ', ')" -ForegroundColor Yellow
        }
    } else {
        # Show all categories
        Write-Host "`n===== Safe Actions Categories =====" -ForegroundColor Cyan
        $global:Actions.Keys | Sort-Object | ForEach-Object {
            $count = $global:Actions[$_].Count
            Write-Host "  $_" -ForegroundColor Green -NoNewline
            Write-Host " ($count commands)" -ForegroundColor Gray
        }
        Write-Host "`nUse 'Get-SafeActions -Category <name>' to see commands in a category" -ForegroundColor DarkGray
        Write-Host "Use 'Get-SafeActions -Command <name>' to check if a command is safe" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Test-SafeAction {
    param([Parameter(Mandatory=$true)][string]$Command)
    
    $validation = Test-PowerShellCommand $Command
    if ($validation.IsValid) {
        $safetyIcon = switch ($validation.SafetyLevel) {
            'ReadOnly' { 'READONLY' }
            'SafeWrite' { 'SafeWrite' }
            'RequiresConfirmation' { 'Confirm' }
            default { '?' }
        }
        
        Write-Host "$safetyIcon '$Command' is a safe action ($($validation.SafetyLevel))" -ForegroundColor Green
        Write-Host "   Category: $($validation.Category)" -ForegroundColor Gray
        Write-Host "   Description: $($validation.Description)" -ForegroundColor Gray
        
        if ($validation.SafetyLevel -ne 'ReadOnly') {
            Write-Host "   WARNING: Requires confirmation before execution" -ForegroundColor Yellow
        }
        
        return $true
    } else {
        Write-Host "WARNING: '$Command' is not in the safe actions list" -ForegroundColor Red
        return $false
    }
}

function Invoke-SafeAction {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [switch]$Force
    )
    
    $validation = Test-PowerShellCommand $Command
    
    if (-not $validation.IsValid) {
        Write-Host "WARNING: Command '$Command' is not in the safe actions list" -ForegroundColor Red
        return $false
    }
    
    # Check if confirmation is needed
    if (-not $Force -and $validation.SafetyLevel -ne 'ReadOnly') {
        $confirmed = Show-CommandConfirmation $Command $validation.SafetyLevel $validation.Description
        if (-not $confirmed) {
            Write-Host "Command execution cancelled by user." -ForegroundColor Yellow
            return $false
        }
    }
    
    try {
        Write-Host "Executing: $Command" -ForegroundColor Cyan
        Invoke-Expression $Command
        Write-Host "Command completed successfully." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "Error executing command: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Set-Alias actions Get-SafeActions
Set-Alias safe-check Test-SafeAction
Set-Alias safe-run Invoke-SafeAction
Set-Alias ai-exec Invoke-AIExec
Set-Alias exec-log Get-AIExecutionLog

function Get-SafeCommandsPrompt {
    # Generate a concise system message for LLM
    $prompt = @'
You are a helpful PowerShell assistant. Use INTENTS to perform actions.

CRITICAL: Output JSON intents on their own line, NOT inside code blocks!

DOCUMENTS (creates and opens):
{"intent":"create_docx","name":"My Document"}
{"intent":"create_xlsx","name":"My Spreadsheet"}

APPS:
{"intent":"open_word"}
{"intent":"open_notepad"}
{"intent":"open_excel"}

CLIPBOARD:
{"intent":"clipboard_read"}
{"intent":"clipboard_write","text":"content"}

FILES:
{"intent":"read_file","path":"file.txt"}
{"intent":"file_stats","path":"file.txt"}

GIT:
{"intent":"git_status"}
{"intent":"git_log"}
{"intent":"git_commit","message":"message"}

CALENDAR:
{"intent":"calendar_today"}
{"intent":"calendar_week"}

WEB:
{"intent":"web_search","query":"search terms"}
{"intent":"wikipedia","query":"topic"}

POWERSHELL (only if no intent exists):
EXECUTE: Get-Process

RULES:
1. Use intents FIRST - they are safer and simpler
2. JSON must be on its own line, NOT in code blocks
3. For "create a doc called X" use: {"intent":"create_docx","name":"X"}
4. Be proactive - execute actions immediately
'@
    
    return $prompt
}

# ===== Startup Message with Load Timing =====
$global:ProfileLoadTime = (Get-Date) - $global:ProfileLoadStart
Write-Host "`nPowerShell $($PSVersionTable.PSVersion) on $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "Profile loaded in $([math]::Round($global:ProfileLoadTime.TotalMilliseconds))ms | Session: $($global:SessionId)" -ForegroundColor DarkGray
Write-Host "Type 'tips' for quick reference, 'profile-timing' for load details" -ForegroundColor DarkGray

function Get-ProfileTiming {
    <#
    .SYNOPSIS
    Display profile load timing information
    #>
    Write-Host "`n===== Profile Load Timing =====" -ForegroundColor Cyan
    Write-Host "  Total load time: $([math]::Round($global:ProfileLoadTime.TotalMilliseconds))ms" -ForegroundColor White
    Write-Host "  Session ID: $($global:SessionId)" -ForegroundColor Gray
    Write-Host "  Session started: $($global:SessionStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    
    Write-Host "`nLazy-loaded modules:" -ForegroundColor Yellow
    foreach ($mod in $global:LazyModules.Keys) {
        $status = if ($global:LazyModules[$mod]) { "Loaded" } else { "Not loaded (on-demand)" }
        $color = if ($global:LazyModules[$mod]) { "Green" } else { "DarkGray" }
        Write-Host "  $mod : $status" -ForegroundColor $color
    }
    
    Write-Host "`nTo load modules manually:" -ForegroundColor Yellow
    Write-Host "  Enable-TerminalIcons  - Load Terminal-Icons" -ForegroundColor Gray
    Write-Host "  Enable-PoshGit        - Load posh-git" -ForegroundColor Gray
    Write-Host "================================`n" -ForegroundColor Cyan
}

Set-Alias profile-timing Get-ProfileTiming -Force
