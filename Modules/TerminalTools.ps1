# ===== TerminalTools.ps1 =====
# Integration with modern terminal tools: bat, glow, broot, visidata, fzf

# ===== Tool Availability Detection =====
$global:TerminalTools = @{
    'bat' = $null -ne (Get-Command bat -ErrorAction SilentlyContinue)
    'glow' = $null -ne (Get-Command glow -ErrorAction SilentlyContinue)
    'broot' = $null -ne (Get-Command broot -ErrorAction SilentlyContinue)
    'visidata' = $null -ne (Get-Command vd -ErrorAction SilentlyContinue)
    'fzf' = $null -ne (Get-Command fzf -ErrorAction SilentlyContinue)
    'rg' = $null -ne (Get-Command rg -ErrorAction SilentlyContinue)
    'lsd' = $null -ne (Get-Command lsd -ErrorAction SilentlyContinue)
}

function Get-TerminalTools {
    <#
    .SYNOPSIS
    Show status of terminal tool integrations
    #>
    Write-Host "`n===== Terminal Tools Status =====" -ForegroundColor Cyan
    
    $tools = @(
        @{ Name = 'bat'; Desc = 'Syntax-highlighted cat'; Install = 'winget install sharkdp.bat' }
        @{ Name = 'glow'; Desc = 'Markdown renderer'; Install = 'winget install charmbracelet.glow' }
        @{ Name = 'broot'; Desc = 'File explorer'; Install = 'winget install Canop.broot' }
        @{ Name = 'visidata'; Desc = 'Data viewer (vd)'; Install = 'pip install visidata' }
        @{ Name = 'fzf'; Desc = 'Fuzzy finder'; Install = 'winget install fzf' }
        @{ Name = 'rg'; Desc = 'Ripgrep search'; Install = 'winget install BurntSushi.ripgrep.MSVC' }
        @{ Name = 'lsd'; Desc = 'Modern ls'; Install = 'winget install lsd-rs.lsd' }
    )
    
    foreach ($tool in $tools) {
        $status = if ($global:TerminalTools[$tool.Name]) { "Installed" } else { "Not found" }
        $color = if ($global:TerminalTools[$tool.Name]) { "Green" } else { "DarkGray" }
        
        Write-Host "  $($tool.Name.PadRight(10))" -ForegroundColor $color -NoNewline
        Write-Host " $($tool.Desc.PadRight(25))" -ForegroundColor Gray -NoNewline
        if (-not $global:TerminalTools[$tool.Name]) {
            Write-Host " $($tool.Install)" -ForegroundColor Yellow
        } else {
            Write-Host " $status" -ForegroundColor Green
        }
    }
    Write-Host "=================================`n" -ForegroundColor Cyan
}

# ===== bat Integration (Syntax-Highlighted Cat) =====
function Invoke-Bat {
    <#
    .SYNOPSIS
    View file with syntax highlighting using bat
    
    .PARAMETER Path
    File to display
    
    .PARAMETER Language
    Force specific language for highlighting
    
    .PARAMETER Plain
    Disable decorations (line numbers, etc)
    
    .PARAMETER Paging
    Enable paging (less-style navigation)
    #>
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        [string]$Language = "",
        [switch]$Plain,
        [switch]$Paging
    )
    
    if (-not $global:TerminalTools['bat']) {
        Write-Host "bat not installed. Install with: winget install sharkdp.bat" -ForegroundColor Yellow
        Get-Content $Path
        return
    }
    
    $cmdArgs = @()
    
    if ($Plain) {
        $cmdArgs += "--style=plain"
    } else {
        $cmdArgs += "--style=full"
    }
    
    if (-not $Paging) {
        $cmdArgs += "--paging=never"
    }
    
    if ($Language) {
        $cmdArgs += "--language=$Language"
    }
    
    & bat @cmdArgs $Path
}

function cath {
    <#
    .SYNOPSIS
    Cat with syntax highlighting (alias for bat)
    #>
    param([Parameter(Mandatory=$true, Position=0)][string]$Path)
    Invoke-Bat -Path $Path
}

function catp {
    <#
    .SYNOPSIS
    Cat plain (no decorations, just highlighting)
    #>
    param([Parameter(Mandatory=$true, Position=0)][string]$Path)
    Invoke-Bat -Path $Path -Plain
}

function Show-Code {
    <#
    .SYNOPSIS
    Display code file with full decorations and paging
    #>
    param([Parameter(Mandatory=$true, Position=0)][string]$Path)
    Invoke-Bat -Path $Path -Paging
}

# Diff with bat
function Show-Diff {
    <#
    .SYNOPSIS
    Show git diff with bat syntax highlighting
    #>
    param([string]$Path = "")
    
    if ($global:TerminalTools['bat']) {
        if ($Path) {
            git diff $Path | bat --style=plain --language=diff
        } else {
            git diff | bat --style=plain --language=diff
        }
    } else {
        git diff $Path
    }
}

# ===== glow Integration (Markdown Rendering) =====
function Invoke-Glow {
    <#
    .SYNOPSIS
    Render markdown beautifully in terminal
    
    .PARAMETER Path
    Markdown file to render (or - for stdin)
    
    .PARAMETER Pager
    Use pager for long content
    
    .PARAMETER Width
    Width of output (default: terminal width)
    #>
    param(
        [Parameter(Position=0)]
        [string]$Path = "",
        [switch]$Pager,
        [int]$Width = 0
    )
    
    if (-not $global:TerminalTools['glow']) {
        Write-Host "glow not installed. Install with: winget install charmbracelet.glow" -ForegroundColor Yellow
        if ($Path -and (Test-Path $Path)) {
            Get-Content $Path
        }
        return
    }
    
    $cmdArgs = @()
    
    if ($Pager) {
        $cmdArgs += "--pager"
    }
    
    if ($Width -gt 0) {
        $cmdArgs += "--width=$Width"
    }
    
    if ($Path) {
        & glow @cmdArgs $Path
    } else {
        $input | & glow @cmdArgs -
    }
}

function Show-Markdown {
    <#
    .SYNOPSIS
    Render markdown file or string
    #>
    param(
        [Parameter(Position=0)]
        [string]$PathOrContent
    )
    
    if (Test-Path $PathOrContent -ErrorAction SilentlyContinue) {
        Invoke-Glow -Path $PathOrContent
    } else {
        $PathOrContent | Invoke-Glow
    }
}

function Format-MarkdownOutput {
    <#
    .SYNOPSIS
    Format text as markdown and render with glow
    Used for LLM output rendering
    #>
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Text
    )
    
    if ($global:TerminalTools['glow']) {
        $Text | glow -
    } else {
        # Fallback: basic markdown formatting
        $Text -replace '```(\w+)?', '' -replace '\*\*(.+?)\*\*', '$1' -replace '`(.+?)`', '$1'
    }
}

# ===== broot Integration (File Explorer) =====
function Invoke-Broot {
    <#
    .SYNOPSIS
    Launch broot file explorer
    
    .PARAMETER Path
    Starting directory
    
    .PARAMETER Hidden
    Show hidden files
    
    .PARAMETER Sizes
    Show file sizes
    #>
    param(
        [string]$Path = ".",
        [switch]$Hidden,
        [switch]$Sizes
    )
    
    if (-not $global:TerminalTools['broot']) {
        Write-Host "broot not installed. Install with: winget install Canop.broot" -ForegroundColor Yellow
        Get-ChildItem $Path
        return
    }
    
    $brootOut = [System.IO.Path]::GetTempFileName()
    $cmdArgs = @("--outcmd", $brootOut)
    
    if ($Hidden) { $cmdArgs += "--hidden" }
    if ($Sizes) { $cmdArgs += "--sizes" }
    
    & broot @cmdArgs $Path
    
    if (Test-Path $brootOut) {
        $cmd = Get-Content $brootOut -Raw
        Remove-Item $brootOut -Force
        
        if ($cmd -match '^cd\s+"?(.+?)"?\s*$') {
            Set-Location $Matches[1]
        } elseif ($cmd) {
            Invoke-Expression $cmd
        }
    }
}

function br {
    <#
    .SYNOPSIS
    Quick broot launcher with cd integration
    #>
    param([string]$Path = ".")
    Invoke-Broot -Path $Path
}

function brs {
    <#
    .SYNOPSIS
    Broot with sizes displayed
    #>
    param([string]$Path = ".")
    Invoke-Broot -Path $Path -Sizes
}

function brh {
    <#
    .SYNOPSIS
    Broot showing hidden files
    #>
    param([string]$Path = ".")
    Invoke-Broot -Path $Path -Hidden
}

# ===== visidata Integration (Data Viewer) =====
function Invoke-Visidata {
    <#
    .SYNOPSIS
    Open data file in visidata
    
    .PARAMETER Path
    Data file (CSV, JSON, Excel, etc.)
    #>
    param(
        [Parameter(Position=0)]
        [string]$Path = ""
    )
    
    if (-not $global:TerminalTools['visidata']) {
        Write-Host "visidata not installed. Install with: pip install visidata" -ForegroundColor Yellow
        return
    }
    
    if ($Path) {
        & vd $Path
    } else {
        $input | & vd -
    }
}

function Show-Data {
    <#
    .SYNOPSIS
    View PowerShell objects in visidata
    #>
    param(
        [Parameter(ValueFromPipeline=$true)]
        $InputObject
    )
    
    begin { $objects = @() }
    process { $objects += $InputObject }
    end {
        if ($global:TerminalTools['visidata']) {
            $objects | ConvertTo-Csv -NoTypeInformation | & vd --filetype=csv -
        } else {
            $objects | Format-Table -AutoSize
        }
    }
}

function Show-Json {
    <#
    .SYNOPSIS
    View JSON file in visidata
    #>
    param([Parameter(Mandatory=$true)][string]$Path)
    
    if ($global:TerminalTools['visidata']) {
        & vd $Path
    } else {
        Get-Content $Path | ConvertFrom-Json | Format-List
    }
}

function Show-Csv {
    <#
    .SYNOPSIS
    View CSV file in visidata
    #>
    param([Parameter(Mandatory=$true)][string]$Path)
    
    if ($global:TerminalTools['visidata']) {
        & vd $Path
    } else {
        Import-Csv $Path | Format-Table -AutoSize
    }
}

# ===== fzf Integration (Fuzzy Finder) =====
function Invoke-FzfHistory {
    <#
    .SYNOPSIS
    Search command history with fzf
    #>
    if (-not $global:TerminalTools['fzf']) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        Get-History | Select-Object -Last 50 | Format-Table -AutoSize
        return
    }
    
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $historyPath) {
        $selected = Get-Content $historyPath | Where-Object { $_ } | Select-Object -Unique | & fzf --tac --no-sort --height 40%
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }
}

function Invoke-FzfFile {
    <#
    .SYNOPSIS
    Fuzzy find files
    #>
    param([string]$Path = ".")
    
    if (-not $global:TerminalTools['fzf']) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        return
    }
    
    $selected = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | 
        Select-Object -ExpandProperty FullName | 
        & fzf --height 40%
    
    if ($selected) { return $selected }
}

function Invoke-FzfDirectory {
    <#
    .SYNOPSIS
    Fuzzy find and cd to directory
    #>
    param([string]$Path = ".")
    
    if (-not $global:TerminalTools['fzf']) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        return
    }
    
    $selected = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue | 
        Select-Object -ExpandProperty FullName | 
        & fzf --height 40%
    
    if ($selected) { Set-Location $selected }
}

function Invoke-FzfEdit {
    <#
    .SYNOPSIS
    Fuzzy find file and open in editor
    #>
    param(
        [string]$Path = ".",
        [string]$Editor = "code"
    )
    
    $file = Invoke-FzfFile -Path $Path
    if ($file) {
        & $Editor $file
    }
}

# Keyboard shortcut for fzf history
if ($global:TerminalTools['fzf']) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
        Invoke-FzfHistory
    }
}

# ===== ripgrep Integration =====
function Invoke-Ripgrep {
    <#
    .SYNOPSIS
    Fast recursive search with ripgrep
    #>
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Pattern,
        [string]$Path = ".",
        [string]$Type = "",
        [switch]$CaseSensitive,
        [switch]$Hidden
    )
    
    if (-not $global:TerminalTools['rg']) {
        Write-Host "ripgrep not installed. Install with: winget install BurntSushi.ripgrep.MSVC" -ForegroundColor Yellow
        Select-String -Pattern $Pattern -Path "$Path\*" -Recurse
        return
    }
    
    $cmdArgs = @()
    
    if (-not $CaseSensitive) { $cmdArgs += "-i" }
    if ($Hidden) { $cmdArgs += "--hidden" }
    if ($Type) { $cmdArgs += "-t", $Type }
    
    & rg @cmdArgs $Pattern $Path
}

function rgs {
    <#
    .SYNOPSIS
    Quick ripgrep search
    #>
    param(
        [Parameter(Mandatory=$true, Position=0)][string]$Pattern,
        [Parameter(Position=1)][string]$Path = "."
    )
    Invoke-Ripgrep -Pattern $Pattern -Path $Path
}

# ===== lsd Integration (Modern ls) =====
function Invoke-Lsd {
    <#
    .SYNOPSIS
    Modern ls with icons and colors
    #>
    param(
        [string]$Path = ".",
        [switch]$Long,
        [switch]$All,
        [switch]$Tree
    )
    
    if (-not $global:TerminalTools['lsd']) {
        if ($Long) { Get-ChildItem $Path | Format-Table -AutoSize }
        else { Get-ChildItem $Path -Name }
        return
    }
    
    $cmdArgs = @()
    if ($Long) { $cmdArgs += "-l" }
    if ($All) { $cmdArgs += "-a" }
    if ($Tree) { $cmdArgs += "--tree" }
    
    & lsd @cmdArgs $Path
}

# ===== Aliases =====
Set-Alias tools Get-TerminalTools -Force
# Note: 'cat' shadows Get-Content - intentional for bat integration
# Scripts expecting cat=Get-Content will break. Use Get-Content explicitly.
try { Set-Alias cat cath -Force -Option AllScope } catch { }
# Note: 'md' is a built-in alias for mkdir with AllScope - cannot override
# Use 'glow' or 'markdown' instead
Set-Alias glow Show-Markdown -Force
Set-Alias markdown Show-Markdown -Force
Set-Alias vd Invoke-Visidata -Force
Set-Alias fh Invoke-FzfHistory -Force
Set-Alias ff Invoke-FzfFile -Force
Set-Alias fd Invoke-FzfDirectory -Force
Set-Alias fe Invoke-FzfEdit -Force
Set-Alias rg Invoke-Ripgrep -Force
Set-Alias gdiff Show-Diff -Force

# Export for use in chat formatting
$global:UseGlowForMarkdown = $global:TerminalTools['glow']
