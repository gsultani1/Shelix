# ===== FzfIntegration.ps1 =====
# Fuzzy finder (fzf) integration for PowerShell
# Provides fuzzy search for history, files, and directories

# ===== fzf Availability Check =====
$global:FzfAvailable = $null -ne (Get-Command fzf -ErrorAction SilentlyContinue)

function Invoke-FzfHistory {
    <#
    .SYNOPSIS
    Search command history with fzf fuzzy finder
    
    .DESCRIPTION
    Uses fzf to fuzzy search through PowerShell command history.
    Falls back to standard history display if fzf is not installed.
    
    .EXAMPLE
    Invoke-FzfHistory
    # Or use alias: fh
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
    
    .DESCRIPTION
    Recursively searches for files in the current directory and allows
    fuzzy selection with fzf. Returns the selected file path.
    
    .EXAMPLE
    $file = Invoke-FzfFile
    # Or use alias: ff
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
    
    .DESCRIPTION
    Recursively searches for directories and allows fuzzy selection.
    Changes to the selected directory.
    
    .EXAMPLE
    Invoke-FzfDirectory
    # Or use alias: fd
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

function Invoke-FzfProcess {
    <#
    .SYNOPSIS
    Fuzzy find and select a running process
    
    .EXAMPLE
    $proc = Invoke-FzfProcess
    #>
    if (-not $global:FzfAvailable) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        return
    }
    
    $selected = Get-Process | ForEach-Object { "$($_.Id)`t$($_.ProcessName)`t$($_.MainWindowTitle)" } | 
        fzf --height 40% --header "PID`tName`tWindow"
    
    if ($selected) {
        $processId = ($selected -split "`t")[0]
        return Get-Process -Id $processId
    }
}

function Invoke-FzfGitBranch {
    <#
    .SYNOPSIS
    Fuzzy find and checkout git branch
    
    .EXAMPLE
    Invoke-FzfGitBranch
    #>
    if (-not $global:FzfAvailable) {
        Write-Host "fzf not found. Install with: winget install fzf" -ForegroundColor Yellow
        return
    }
    
    if (-not (Test-Path .git)) {
        Write-Host "Not a git repository" -ForegroundColor Yellow
        return
    }
    
    $selected = git branch -a 2>$null | ForEach-Object { $_.Trim() -replace '^\* ', '' } | 
        fzf --height 40%
    
    if ($selected) {
        git checkout $selected
    }
}

# ===== Keyboard Shortcut Setup =====
function Enable-FzfKeyBindings {
    <#
    .SYNOPSIS
    Enable fzf keyboard shortcuts (Ctrl+R for history)
    #>
    if ($global:FzfAvailable) {
        Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
            Invoke-FzfHistory
        }
        Write-Host "fzf keybindings enabled: Ctrl+R for history search" -ForegroundColor Green
    } else {
        Write-Host "fzf not available - keybindings not set" -ForegroundColor Yellow
    }
}

# Auto-enable keybindings if fzf is available
if ($global:FzfAvailable) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
        Invoke-FzfHistory
    }
}

# ===== Aliases =====
Set-Alias fh Invoke-FzfHistory -Force
Set-Alias ff Invoke-FzfFile -Force
Set-Alias fd Invoke-FzfDirectory -Force
Set-Alias fp Invoke-FzfProcess -Force
Set-Alias fgb Invoke-FzfGitBranch -Force

Write-Verbose "FzfIntegration loaded: Invoke-FzfHistory (fh), Invoke-FzfFile (ff), Invoke-FzfDirectory (fd)"
