# ===== SystemUtilities.ps1 =====
# System utilities: uptime, hardware info, ports, processes, network, PATH management

# ===== Admin Elevation =====
function sudo {
    <#
    .SYNOPSIS
    Elevate to admin with proper directory preservation
    #>
    Start-Process powershell -Verb runAs -ArgumentList "-NoExit","-WorkingDirectory '$PWD'"
}

# ===== Port and Process Utilities =====
function ports { 
    <#
    .SYNOPSIS
    Check port usage
    #>
    netstat -ano | findstr :$args 
}

function procs {
    <#
    .SYNOPSIS
    List processes with CPU and memory info
    #>
    param([string]$name='')
    Get-Process | Where-Object { $_.ProcessName -like "*$name*" } | 
    Sort-Object CPU -Descending | 
    Select-Object Id, ProcessName, CPU, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet / 1MB, 2)}} | 
    Format-Table -AutoSize 
}

# ===== Network Utilities =====
function Test-Port {
    <#
    .SYNOPSIS
    Test network connectivity to a specific port
    #>
    param(
        [Parameter(Mandatory=$true)][string]$hostname, 
        [Parameter(Mandatory=$true)][int]$port
    )
    Test-NetConnection -ComputerName $hostname -Port $port -InformationLevel Quiet
}

function Get-PublicIP {
    <#
    .SYNOPSIS
    Get public IP address
    #>
    try {
        $ip = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip
        Write-Host "Public IP: $ip" -ForegroundColor Green
        return $ip
    } catch {
        Write-Host "Failed to retrieve public IP" -ForegroundColor Red
    }
}

# ===== System Information =====
function uptime { 
    <#
    .SYNOPSIS
    Show system uptime
    #>
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $span = (Get-Date) - $boot
    Write-Host "System uptime: $($span.Days) days, $($span.Hours) hours, $($span.Minutes) minutes" -ForegroundColor Green
}

function hwinfo {
    <#
    .SYNOPSIS
    Get hardware information
    #>
    Write-Host "`n===== Hardware Info =====" -ForegroundColor Cyan
    Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory |
        Format-List
    Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors |
        Format-List
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
    Display comprehensive system information
    #>
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

# ===== Environment Management =====
function Update-Environment {
    <#
    .SYNOPSIS
    Refresh environment variables from registry
    #>
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

function Export-Env {
    <#
    .SYNOPSIS
    Export environment variables to a backup file
    #>
    $out = "$env:USERPROFILE\Documents\EnvBackup_$(Get-Date -Format yyyyMMdd_HHmmss).txt"
    $envContent = Get-ChildItem Env: | Sort-Object Name | Out-String
    [System.IO.File]::WriteAllText($out, $envContent, [System.Text.Encoding]::UTF8)
    Write-Host "Environment exported to $out" -ForegroundColor Green
}

# ===== PATH Management =====
function Show-Path { 
    <#
    .SYNOPSIS
    Display PATH entries with validation
    #>
    $env:PATH -split ';' | Where-Object {$_} | Sort-Object | ForEach-Object { 
        $cleanPath = $_.TrimEnd('\')
        $color = if (Test-Path $cleanPath) { 'Green' } else { 'Red' }
        Write-Host $cleanPath -ForegroundColor $color
    }
}

function Add-PathUser {
    <#
    .SYNOPSIS
    Add directory to user PATH
    #>
    param([Parameter(Mandatory=$true)][string]$dir)
    
    if (Test-Path $dir) {
        $cleanDir = $dir.TrimEnd('\')
        $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $paths = $current -split ';' | ForEach-Object { $_.TrimEnd('\') }
        
        if ($paths -notcontains $cleanDir) {
            [Environment]::SetEnvironmentVariable('PATH', "$current;$cleanDir", 'User')
            Update-Environment
            Write-Host "Added to user PATH: $cleanDir" -ForegroundColor Green
        } else {
            Write-Host "Already in PATH: $cleanDir" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Directory not found: $dir" -ForegroundColor Red
    }
}

function Add-PathSystem {
    <#
    .SYNOPSIS
    Add directory to system PATH (requires admin)
    #>
    param([Parameter(Mandatory=$true)][string]$dir)
    
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
            Update-Environment
            Write-Host "Added to system PATH: $cleanDir" -ForegroundColor Green
        } else {
            Write-Host "Already in PATH: $cleanDir" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Directory not found: $dir" -ForegroundColor Red
    }
}

# ===== File Listing Shortcuts =====
function ll { Get-ChildItem -Force | Format-Table -AutoSize }
function la { Get-ChildItem -Force -Hidden | Format-Table -AutoSize }
function lsd { Get-ChildItem -Directory | Format-Table -AutoSize }
function lsf { Get-ChildItem -File | Format-Table -AutoSize }

function grep {
    <#
    .SYNOPSIS
    Search for pattern in files
    #>
    param(
        [Parameter(Mandatory=$true)][string]$pattern, 
        [string]$path = '*'
    )
    Select-String -Pattern $pattern -Path $path -ErrorAction SilentlyContinue
}

# ===== Quick Restart =====
function restart-ps { Start-Process powershell -ArgumentList '-NoExit' ; exit }

# ===== Aliases =====
Set-Alias refreshenv Update-Environment -Force
Set-Alias sysinfo Get-SystemInfo -Force

Write-Verbose "SystemUtilities loaded: sudo, ports, procs, uptime, hwinfo, Get-SystemInfo, Show-Path"
