# ===== PersistentAliases.ps1 =====
# User-defined aliases that persist across PowerShell sessions
# Stored in UserAliases.ps1 file

# ===== Configuration =====
$global:UserAliasesPath = "$global:BildsyPSHome\aliases\UserAliases.ps1"

function Add-PersistentAlias {
    <#
    .SYNOPSIS
    Add a persistent alias that survives session restarts
    
    .PARAMETER Name
    The alias name
    
    .PARAMETER Value
    The command or function the alias points to
    
    .PARAMETER Description
    Optional description comment
    
    .EXAMPLE
    Add-PersistentAlias -Name "g" -Value "git" -Description "Git shortcut"
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
    
    .PARAMETER Name
    The alias name to remove
    
    .EXAMPLE
    Remove-PersistentAlias -Name "g"
    #>
    param([Parameter(Mandatory=$true)][string]$Name)
    
    if (-not (Test-Path $global:UserAliasesPath)) {
        Write-Host "No user aliases file found." -ForegroundColor Yellow
        return
    }
    
    $lines = @(Get-Content $global:UserAliasesPath)
    $newLines = @($lines | Where-Object { $_ -notmatch "Set-Alias\s+-Name\s+$Name\s+" })
    
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
    
    .EXAMPLE
    Get-PersistentAliases
    # Or use alias: list-aliases
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
    <#
    .SYNOPSIS
    Reload user aliases from file
    
    .EXAMPLE
    Update-UserAliases
    # Or use alias: reload-aliases
    #>
    if (Test-Path $global:UserAliasesPath) {
        . $global:UserAliasesPath
        Write-Host "User aliases reloaded." -ForegroundColor Green
    } else {
        Write-Host "No user aliases file found." -ForegroundColor Yellow
    }
}

# ===== Tab Completion =====
Register-ArgumentCompleter -CommandName Remove-PersistentAlias -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if (Test-Path $global:UserAliasesPath) {
        $content = @(Get-Content $global:UserAliasesPath -ErrorAction SilentlyContinue)
        $content | ForEach-Object {
            if ($_ -match '^\s*Set-Alias\s+(\S+)') {
                $Matches[1]
            }
        } | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Alias: $_")
        }
    }
}

# ===== Aliases =====
Set-Alias add-alias Add-PersistentAlias -Force
Set-Alias remove-alias Remove-PersistentAlias -Force
Set-Alias list-aliases Get-PersistentAliases -Force
Set-Alias reload-aliases Update-UserAliases -Force

# ===== Auto-load user aliases on module import =====
if (Test-Path $global:UserAliasesPath) {
    . $global:UserAliasesPath
}

Write-Verbose "PersistentAliases loaded: Add-PersistentAlias, Remove-PersistentAlias, Get-PersistentAliases"
