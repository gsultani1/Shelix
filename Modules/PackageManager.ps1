# ===== PackageManager.ps1 =====
# Auto-install missing tools, health checks, and configuration system

# ===== Tool Registry =====
$global:ToolRegistry = @{
    'bat' = @{
        Name = 'bat'
        Description = 'Syntax-highlighted cat replacement'
        WingetId = 'sharkdp.bat'
        TestCommand = 'bat'
        Category = 'FileViewing'
        Optional = $false
    }
    'glow' = @{
        Name = 'glow'
        Description = 'Terminal markdown renderer'
        WingetId = 'charmbracelet.glow'
        TestCommand = 'glow'
        Category = 'Markdown'
        Optional = $false
    }
    'fzf' = @{
        Name = 'fzf'
        Description = 'Fuzzy finder for files and history'
        WingetId = 'junegunn.fzf'
        TestCommand = 'fzf'
        Category = 'Search'
        Optional = $false
    }
    'ripgrep' = @{
        Name = 'ripgrep'
        Description = 'Fast recursive grep'
        WingetId = 'BurntSushi.ripgrep.MSVC'
        TestCommand = 'rg'
        Category = 'Search'
        Optional = $false
    }
    'broot' = @{
        Name = 'broot'
        Description = 'Interactive file explorer'
        WingetId = 'Canop.broot'
        TestCommand = 'broot'
        Category = 'FileExplorer'
        Optional = $true
    }
    'lsd' = @{
        Name = 'lsd'
        Description = 'Modern ls with icons'
        WingetId = 'lsd-rs.lsd'
        TestCommand = 'lsd'
        Category = 'FileViewing'
        Optional = $true
    }
    'delta' = @{
        Name = 'delta'
        Description = 'Better git diff viewer'
        WingetId = 'dandavison.delta'
        TestCommand = 'delta'
        Category = 'Git'
        Optional = $true
    }
    'ollama' = @{
        Name = 'ollama'
        Description = 'Local LLM runtime'
        WingetId = 'Ollama.Ollama'
        TestCommand = 'ollama'
        Category = 'AI'
        Optional = $false
    }
}

# ===== User Preferences =====
$global:ToolPreferencesPath = "$global:BildsyPSHome\config\ToolPreferences.json"
$global:ToolPreferences = $null

function Import-ToolPreferences {
    if (Test-Path $global:ToolPreferencesPath) {
        try {
            $global:ToolPreferences = Get-Content $global:ToolPreferencesPath -Raw | ConvertFrom-Json
            return $true
        } catch {
            Write-Host "Warning: Failed to load ToolPreferences.json" -ForegroundColor Yellow
        }
    }
    # Default preferences
    $global:ToolPreferences = @{
        autoInstall = $false
        enabledCategories = @('FileViewing', 'Markdown', 'Search', 'AI')
        disabledTools = @()
    }
    return $false
}

function Save-ToolPreferences {
    try {
        $global:ToolPreferences | ConvertTo-Json -Depth 3 | Set-Content $global:ToolPreferencesPath
        Write-Host "Preferences saved." -ForegroundColor Green
    } catch {
        Write-Host "Failed to save preferences: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-ToolPreference {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('autoInstall', 'enableCategory', 'disableCategory', 'enableTool', 'disableTool')]
        [string]$Setting,
        
        [string]$Value
    )
    
    Import-ToolPreferences | Out-Null
    
    switch ($Setting) {
        'autoInstall' {
            $global:ToolPreferences.autoInstall = $Value -eq 'true' -or $Value -eq '1'
        }
        'enableCategory' {
            if ($Value -and $Value -notin $global:ToolPreferences.enabledCategories) {
                $global:ToolPreferences.enabledCategories += $Value
            }
        }
        'disableCategory' {
            $global:ToolPreferences.enabledCategories = $global:ToolPreferences.enabledCategories | Where-Object { $_ -ne $Value }
        }
        'enableTool' {
            $global:ToolPreferences.disabledTools = $global:ToolPreferences.disabledTools | Where-Object { $_ -ne $Value }
        }
        'disableTool' {
            if ($Value -and $Value -notin $global:ToolPreferences.disabledTools) {
                $global:ToolPreferences.disabledTools += $Value
            }
        }
    }
    
    Save-ToolPreferences
}

# Load preferences on startup
Import-ToolPreferences | Out-Null

# ===== Health Checks =====
function Test-ToolHealth {
    param([string]$ToolName)
    
    $tool = $global:ToolRegistry[$ToolName]
    if (-not $tool) {
        return @{ Name = $ToolName; Status = 'Unknown'; Message = 'Tool not in registry' }
    }
    
    $cmd = Get-Command $tool.TestCommand -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return @{ Name = $ToolName; Status = 'NotInstalled'; Message = 'Not installed' }
    }
    
    # Tool is available - report as healthy with path
    return @{ Name = $ToolName; Status = 'Healthy'; Message = 'OK'; Path = $cmd.Source }
}

function Get-ToolHealthReport {
    <#
    .SYNOPSIS
    Run health checks on all registered tools
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n===== Tool Health Report =====" -ForegroundColor Cyan
    
    $results = [System.Collections.ArrayList]@()
    foreach ($toolName in $global:ToolRegistry.Keys | Sort-Object) {
        $health = Test-ToolHealth $toolName
        [void]$results.Add($health)
        
        $statusColor = switch ($health.Status) {
            'Healthy' { 'Green' }
            'NotInstalled' { 'Yellow' }
            'Error' { 'Red' }
            default { 'Gray' }
        }
        
        $statusIcon = switch ($health.Status) {
            'Healthy' { '[OK]' }
            'NotInstalled' { '[--]' }
            'Error' { '[!!]' }
            default { '[??]' }
        }
        
        Write-Host "  $statusIcon " -ForegroundColor $statusColor -NoNewline
        Write-Host "$($toolName.PadRight(12))" -NoNewline
        Write-Host " $($health.Message)" -ForegroundColor Gray
    }
    
    $healthy = @($results | Where-Object { $_.Status -eq 'Healthy' }).Count
    $total = $results.Count
    Write-Host "`n  $healthy/$total tools healthy" -ForegroundColor $(if ($healthy -eq $total) { 'Green' } else { 'Yellow' })
    Write-Host "==============================`n" -ForegroundColor Cyan
}

# ===== Installation =====
function Install-MissingTools {
    <#
    .SYNOPSIS
    Install missing tools via winget
    
    .PARAMETER Force
    Install without prompting
    
    .PARAMETER Category
    Only install tools from specific category
    #>
    param(
        [switch]$Force,
        [string]$Category = $null
    )
    
    # Check winget availability
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget not available. Please install App Installer from Microsoft Store." -ForegroundColor Red
        return
    }
    
    Import-ToolPreferences | Out-Null
    
    $toInstall = @()
    foreach ($toolName in $global:ToolRegistry.Keys) {
        $tool = $global:ToolRegistry[$toolName]
        
        # Skip if disabled by user
        if ($toolName -in $global:ToolPreferences.disabledTools) { continue }
        
        # Skip if category not enabled
        if ($tool.Category -notin $global:ToolPreferences.enabledCategories) { continue }
        
        # Skip if filtering by category and doesn't match
        if ($Category -and $tool.Category -ne $Category) { continue }
        
        # Check if already installed
        if (Get-Command $tool.TestCommand -ErrorAction SilentlyContinue) { continue }
        
        $toInstall += $tool
    }
    
    if ($toInstall.Count -eq 0) {
        Write-Host "All enabled tools are already installed." -ForegroundColor Green
        return
    }
    
    Write-Host "`nTools to install:" -ForegroundColor Cyan
    foreach ($tool in $toInstall) {
        Write-Host "  - $($tool.Name): $($tool.Description)" -ForegroundColor Yellow
    }
    
    if (-not $Force) {
        $confirm = Read-Host "`nInstall these tools? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Installation cancelled." -ForegroundColor Gray
            return
        }
    }
    
    foreach ($tool in $toInstall) {
        Write-Host "`nInstalling $($tool.Name)..." -ForegroundColor Cyan
        try {
            winget install $tool.WingetId --accept-package-agreements --accept-source-agreements
            Write-Host "  Installed $($tool.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  Failed to install $($tool.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "`nRun 'refreshenv' to update PATH, then '. `$PROFILE' to reload." -ForegroundColor Yellow
}

function Install-Tool {
    <#
    .SYNOPSIS
    Install a specific tool by name
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    $tool = $global:ToolRegistry[$Name]
    if (-not $tool) {
        Write-Host "Unknown tool: $Name" -ForegroundColor Red
        Write-Host "Available tools: $($global:ToolRegistry.Keys -join ', ')" -ForegroundColor Gray
        return
    }
    
    if (Get-Command $tool.TestCommand -ErrorAction SilentlyContinue) {
        Write-Host "$Name is already installed." -ForegroundColor Green
        return
    }
    
    Write-Host "Installing $Name via winget..." -ForegroundColor Cyan
    winget install $tool.WingetId --accept-package-agreements --accept-source-agreements
}

# ===== Migration Helpers =====
function Import-BashAliases {
    <#
    .SYNOPSIS
    Show equivalent PowerShell commands for common bash aliases
    #>
    $migrations = @(
        @{ Bash = 'll'; PowerShell = 'Get-ChildItem or lsd -l'; Note = 'Use lsd for colored output' }
        @{ Bash = 'la'; PowerShell = 'Get-ChildItem -Force or lsd -la'; Note = 'Shows hidden files' }
        @{ Bash = 'grep'; PowerShell = 'Select-String or rg'; Note = 'ripgrep is faster' }
        @{ Bash = 'find'; PowerShell = 'Get-ChildItem -Recurse or fd'; Note = 'fd is faster' }
        @{ Bash = 'cat'; PowerShell = 'Get-Content or bat'; Note = 'bat has syntax highlighting' }
        @{ Bash = 'less'; PowerShell = 'bat --paging=always'; Note = 'bat includes paging' }
        @{ Bash = 'head'; PowerShell = 'Get-Content -Head N'; Note = 'Or: gc file | Select -First N' }
        @{ Bash = 'tail'; PowerShell = 'Get-Content -Tail N'; Note = 'Or: gc file | Select -Last N' }
        @{ Bash = 'tail -f'; PowerShell = 'Get-Content -Wait'; Note = 'Follow file changes' }
        @{ Bash = 'wc -l'; PowerShell = '(Get-Content file).Count'; Note = 'Or: gc file | Measure-Object -Line' }
        @{ Bash = 'sort'; PowerShell = 'Sort-Object'; Note = 'Pipe to it' }
        @{ Bash = 'uniq'; PowerShell = 'Get-Unique'; Note = 'Or: Select-Object -Unique' }
        @{ Bash = 'awk'; PowerShell = 'ForEach-Object with -split'; Note = 'More verbose but powerful' }
        @{ Bash = 'sed'; PowerShell = '-replace operator'; Note = 'Or: ForEach-Object { $_ -replace }' }
        @{ Bash = 'xargs'; PowerShell = 'ForEach-Object'; Note = 'Pipe and process' }
        @{ Bash = 'cd -'; PowerShell = 'cd -'; Note = 'Implemented in NavigationUtils' }
        @{ Bash = 'pushd/popd'; PowerShell = 'Push-Location/Pop-Location'; Note = 'Built-in' }
        @{ Bash = 'which'; PowerShell = 'Get-Command or which'; Note = 'which defined in NavigationUtils' }
        @{ Bash = 'alias'; PowerShell = 'Get-Alias'; Note = 'Set-Alias to create' }
        @{ Bash = 'export VAR=val'; PowerShell = '$env:VAR = "val"'; Note = 'Or: [Environment]::SetEnvironmentVariable' }
        @{ Bash = 'source file'; PowerShell = '. file'; Note = 'Dot-sourcing' }
        @{ Bash = 'history'; PowerShell = 'Get-History or h'; Note = 'fzf integration: fh' }
        @{ Bash = 'Ctrl+R'; PowerShell = 'fh or Invoke-FzfHistory'; Note = 'Fuzzy history search' }
    )
    
    Write-Host "`n===== Bash to PowerShell Migration Guide =====" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($m in $migrations) {
        Write-Host "  $($m.Bash.PadRight(15))" -ForegroundColor Yellow -NoNewline
        Write-Host " -> " -ForegroundColor Gray -NoNewline
        Write-Host "$($m.PowerShell.PadRight(35))" -ForegroundColor Green -NoNewline
        Write-Host " # $($m.Note)" -ForegroundColor DarkGray
    }
    
    Write-Host "`n=============================================" -ForegroundColor Cyan
    Write-Host "Run 'tips' for more PowerShell shortcuts`n" -ForegroundColor Gray
}

function Import-ZshAliases {
    <#
    .SYNOPSIS
    Show equivalent PowerShell commands for common zsh/oh-my-zsh aliases
    #>
    $migrations = @(
        @{ Zsh = 'g'; PowerShell = 'git'; Note = 'No alias needed, just type git' }
        @{ Zsh = 'ga'; PowerShell = 'ga (git add)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gaa'; PowerShell = 'gaa (git add -A)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gc'; PowerShell = 'gc "msg" (git commit)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gco'; PowerShell = 'gco branch'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gd'; PowerShell = 'gd (git diff)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gl'; PowerShell = 'gl (git log)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gp'; PowerShell = 'gp (git push)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gpl'; PowerShell = 'gpl (git pull)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gs/gst'; PowerShell = 'gs (git status)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'gcl'; PowerShell = 'gcl url (git clone + cd)'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = '..'; PowerShell = '..'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = '...'; PowerShell = '...'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = '~'; PowerShell = '~'; Note = 'Defined in NavigationUtils' }
        @{ Zsh = 'take dir'; PowerShell = 'mkcd dir'; Note = 'mkdir + cd' }
        @{ Zsh = 'x/extract'; PowerShell = 'unzip file'; Note = 'Defined in NavigationUtils' }
    )
    
    Write-Host "`n===== Zsh/Oh-My-Zsh to PowerShell Migration Guide =====" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($m in $migrations) {
        Write-Host "  $($m.Zsh.PadRight(15))" -ForegroundColor Yellow -NoNewline
        Write-Host " -> " -ForegroundColor Gray -NoNewline
        Write-Host "$($m.PowerShell.PadRight(30))" -ForegroundColor Green -NoNewline
        Write-Host " # $($m.Note)" -ForegroundColor DarkGray
    }
    
    Write-Host "`n======================================================" -ForegroundColor Cyan
    Write-Host "Most oh-my-zsh git aliases are already available!`n" -ForegroundColor Gray
}

# ===== Aliases =====
Set-Alias health Get-ToolHealthReport -Force
Set-Alias install-tools Install-MissingTools -Force
Set-Alias bash-help Import-BashAliases -Force
Set-Alias zsh-help Import-ZshAliases -Force
