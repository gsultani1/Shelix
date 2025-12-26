# ===== DevTools.ps1 =====
# Development tools: IDE launchers, dev tool checks, quick diagnostics

function open {
    <#
    .SYNOPSIS
    Open path in Windows Explorer
    #>
    param([string]$path = '.')
    if (Test-Path $path) { 
        Start-Process explorer $path 
    } else { 
        Write-Host "Path not found: $path" -ForegroundColor Red 
    }
}

function code {
    <#
    .SYNOPSIS
    Open path in VS Code
    #>
    param([string]$path = '.')
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

function cursor {
    <#
    .SYNOPSIS
    Open path in Cursor IDE
    #>
    param([string]$path = '.')
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

function windsurf {
    <#
    .SYNOPSIS
    Open path in Windsurf IDE
    #>
    param([string]$path = '.')
    if (Get-Command windsurf -ErrorAction SilentlyContinue) {
        if (Test-Path $path) { 
            & windsurf $path 
        } else { 
            Write-Host "Path not found: $path" -ForegroundColor Red 
        }
    } else {
        Write-Host "Windsurf not found in PATH" -ForegroundColor Red
    }
}

function Test-DevTools {
    <#
    .SYNOPSIS
    Check which development tools are installed
    #>
    $tools = @('git','node','npm','python','pip','dotnet','ffmpeg','code','cursor','windsurf','docker','kubectl','terraform')
    Write-Host "`n===== Development Tools Check =====" -ForegroundColor Cyan
    foreach ($tool in $tools) {
        $found = Get-Command $tool -ErrorAction SilentlyContinue
        if ($found) {
            $version = ""
            try {
                switch ($tool) {
                    'git' { $version = (git --version 2>$null) -replace 'git version ', '' }
                    'node' { $version = (node --version 2>$null) }
                    'python' { $version = (python --version 2>$null) -replace 'Python ', '' }
                    'dotnet' { $version = (dotnet --version 2>$null) }
                    'docker' { $version = (docker --version 2>$null) -replace 'Docker version ', '' -replace ',.*', '' }
                    default { $version = "" }
                }
            } catch { }
            
            if ($version) {
                Write-Host "[OK] $tool" -ForegroundColor Green -NoNewline
                Write-Host " ($version)" -ForegroundColor DarkGray
            } else {
                Write-Host "[OK] $tool" -ForegroundColor Green
            }
        } else {
            Write-Host "[MISSING] $tool" -ForegroundColor Red
        }
    }
    Write-Host "===================================`n" -ForegroundColor Cyan
}

function New-Project {
    <#
    .SYNOPSIS
    Create a new project directory with common structure
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [ValidateSet('basic', 'node', 'python', 'dotnet')]
        [string]$Type = 'basic'
    )
    
    $projectPath = Join-Path (Get-Location) $Name
    
    if (Test-Path $projectPath) {
        Write-Host "Directory already exists: $projectPath" -ForegroundColor Yellow
        return
    }
    
    New-Item -ItemType Directory -Path $projectPath | Out-Null
    Set-Location $projectPath
    
    switch ($Type) {
        'basic' {
            New-Item -ItemType File -Name "README.md" -Value "# $Name`n`nProject description here." | Out-Null
            New-Item -ItemType File -Name ".gitignore" -Value "# Add files to ignore" | Out-Null
        }
        'node' {
            npm init -y 2>$null
            New-Item -ItemType File -Name ".gitignore" -Value "node_modules/`n.env`n*.log" | Out-Null
        }
        'python' {
            New-Item -ItemType File -Name "requirements.txt" | Out-Null
            New-Item -ItemType File -Name "main.py" -Value "# $Name`n`ndef main():`n    pass`n`nif __name__ == '__main__':`n    main()" | Out-Null
            New-Item -ItemType File -Name ".gitignore" -Value "__pycache__/`n*.pyc`n.env`nvenv/`n.venv/" | Out-Null
        }
        'dotnet' {
            dotnet new console -n $Name 2>$null
        }
    }
    
    git init 2>$null | Out-Null
    Write-Host "Created $Type project: $projectPath" -ForegroundColor Green
}

function Get-RepoStatus {
    <#
    .SYNOPSIS
    Show git status for all repos in current directory
    #>
    Get-ChildItem -Directory | ForEach-Object {
        $gitPath = Join-Path $_.FullName ".git"
        if (Test-Path $gitPath) {
            Push-Location $_.FullName
            $status = git status --porcelain 2>$null
            $branch = git branch --show-current 2>$null
            
            if ($status) {
                $changes = ($status | Measure-Object).Count
                Write-Host "$($_.Name)" -ForegroundColor Yellow -NoNewline
                Write-Host " [$branch] " -ForegroundColor Cyan -NoNewline
                Write-Host "($changes changes)" -ForegroundColor Red
            } else {
                Write-Host "$($_.Name)" -ForegroundColor Green -NoNewline
                Write-Host " [$branch] " -ForegroundColor Cyan -NoNewline
                Write-Host "(clean)" -ForegroundColor DarkGray
            }
            Pop-Location
        }
    }
}

# ===== Aliases =====
Set-Alias devcheck Test-DevTools -Force
Set-Alias repos Get-RepoStatus -Force
Set-Alias np notepad -Force
Set-Alias ex explorer -Force

Write-Verbose "DevTools loaded: open, code, cursor, windsurf, Test-DevTools, New-Project, Get-RepoStatus"
