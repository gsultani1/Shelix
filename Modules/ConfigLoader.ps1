# ===== ConfigLoader.ps1 =====
# Loads API keys and configuration from Config/.env file
# Like Python's dotenv but for PowerShell

$global:ConfigPath = "$PSScriptRoot\..\Config"
$global:EnvFilePath = "$global:ConfigPath\.env"

function Import-EnvFile {
    <#
    .SYNOPSIS
    Load environment variables from .env file
    #>
    param(
        [string]$Path = $global:EnvFilePath
    )
    
    if (-not (Test-Path $Path)) {
        Write-Verbose "No .env file found at $Path"
        return @{}
    }
    
    $config = @{}
    
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        
        # Skip comments and empty lines
        if ($line -eq '' -or $line.StartsWith('#')) {
            return
        }
        
        # Parse KEY=VALUE
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            
            # Remove quotes if present
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or 
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            
            # Only set if value is not empty
            if ($value -ne '' -and $value -ne 'your-*') {
                $config[$key] = $value
                # Also set as environment variable for compatibility
                [Environment]::SetEnvironmentVariable($key, $value, 'Process')
            }
        }
    }
    
    return $config
}

function Get-ConfigValue {
    <#
    .SYNOPSIS
    Get a config value - checks .env first, then environment variable
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,
        [string]$Default = $null
    )
    
    # Check loaded config first
    if ($global:LoadedConfig -and $global:LoadedConfig.ContainsKey($Key)) {
        return $global:LoadedConfig[$Key]
    }
    
    # Fall back to environment variable
    $envValue = [Environment]::GetEnvironmentVariable($Key)
    if ($envValue) {
        return $envValue
    }
    
    return $Default
}

function Set-ConfigValue {
    <#
    .SYNOPSIS
    Set a config value in the .env file
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,
        [Parameter(Mandatory=$true)]
        [string]$Value
    )
    
    $envPath = $global:EnvFilePath
    
    # Ensure Config directory exists
    $configDir = Split-Path $envPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    # Read existing content
    $lines = @()
    $found = $false
    
    if (Test-Path $envPath) {
        $lines = Get-Content $envPath
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^$Key=") {
                $lines[$i] = "$Key=$Value"
                $found = $true
            }
        }
    }
    
    if (-not $found) {
        $lines += "$Key=$Value"
    }
    
    Set-Content -Path $envPath -Value $lines -Encoding UTF8
    
    # Update in-memory config
    if (-not $global:LoadedConfig) { $global:LoadedConfig = @{} }
    $global:LoadedConfig[$Key] = $Value
    [Environment]::SetEnvironmentVariable($Key, $Value, 'Process')
    
    Write-Host "Set $Key in config" -ForegroundColor Green
}

# Load config on module import
$global:LoadedConfig = Import-EnvFile

Write-Verbose "ConfigLoader loaded from $global:EnvFilePath"
