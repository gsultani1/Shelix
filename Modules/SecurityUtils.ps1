# ===== SecurityUtils.ps1 =====
# Path and URL security validation for the intent system
# Provides cross-platform path validation and URL security checks

# ===== Cross-Platform Path Security =====

$global:AllowedRoots = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    @(
        "$env:USERPROFILE\Documents"
        "$env:USERPROFILE\Desktop"
        "$env:USERPROFILE\Downloads"
        "$env:USERPROFILE\Projects"
        "C:\Projects"
        "C:\Dev"
    )
} else {
    @(
        "$HOME/Documents"
        "$HOME/Desktop"
        "$HOME/Downloads"
        "$HOME/Projects"
        "$HOME/dev"
    )
}

$global:PathSecurityEnabled = $true

function Test-PathAllowed {
    <#
    .SYNOPSIS
    Validates that a path is within allowed roots and safe to access
    
    .PARAMETER Path
    The path to validate
    
    .PARAMETER AllowCreation
    If set, allows paths that don't exist yet (validates ancestor)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AllowCreation
    )
    
    if (-not $global:PathSecurityEnabled) {
        return @{ Success = $true; Path = $Path; Message = "Security bypassed"; Bypassed = $true }
    }
    
    $onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
    $sep = [IO.Path]::DirectorySeparatorChar
    
    # Block null bytes
    if ($Path -match '\x00') {
        return @{ Success = $false; Path = $null; Message = "Path contains null bytes"; Reason = "SecurityBlock" }
    }
    
    # Normalize path separators
    $normalizedInput = if ($sep -eq '\') { $Path.Replace('/', '\') } else { $Path.Replace('\', '/') }
    
    try {
        if ($AllowCreation) {
            $testPath = $normalizedInput
            $pendingSegments = @()
            
            # Walk up to find existing ancestor
            while ($testPath -and -not (Test-Path $testPath)) {
                $pendingSegments = @(Split-Path $testPath -Leaf) + $pendingSegments
                $testPath = Split-Path $testPath -Parent
                
                if (-not $testPath) {
                    return @{
                        Success = $false
                        Path = $null
                        Message = "No existing ancestor found for: $normalizedInput"
                        Reason = "NoAncestor"
                    }
                }
            }
            
            $resolvedAncestor = (Resolve-Path $testPath -ErrorAction Stop).Path
            $resolvedPath = $resolvedAncestor
            
            foreach ($segment in $pendingSegments) {
                $resolvedPath = Join-Path $resolvedPath $segment
            }
        }
        else {
            if (-not (Test-Path $normalizedInput)) {
                return @{
                    Success = $false
                    Path = $null
                    Message = "Path does not exist: $normalizedInput"
                    Reason = "NotFound"
                }
            }
            $resolvedPath = (Resolve-Path $normalizedInput -ErrorAction Stop).Path
        }
        
        # Windows-specific security checks
        if ($onWindows) {
            if ($resolvedPath.StartsWith('\\')) {
                return @{ Success = $false; Path = $null; Message = "UNC paths not allowed"; Reason = "SecurityBlock" }
            }
            if ($resolvedPath.StartsWith('\\?\') -or $resolvedPath.StartsWith('\\.\')) {
                return @{ Success = $false; Path = $null; Message = "Device paths not allowed"; Reason = "SecurityBlock" }
            }
            # Check for alternate data streams
            $pathAfterDrive = if ($resolvedPath.Length -gt 2 -and $resolvedPath[1] -eq ':') {
                $resolvedPath.Substring(2)
            } else {
                $resolvedPath
            }
            if ($pathAfterDrive -match ':') {
                return @{ Success = $false; Path = $null; Message = "Alternate data streams not allowed"; Reason = "SecurityBlock" }
            }
        }
        
        # Normalize for comparison
        $normalizedResolved = $(if ($sep -eq '\') { $resolvedPath.Replace('/', '\') } else { $resolvedPath.Replace('\', '/') })
        $normalizedResolved = $normalizedResolved.TrimEnd($sep).ToLower()
        
        $allowed = $false
        $matchedRoot = $null
        
        foreach ($root in $global:AllowedRoots) {
            $expandedRoot = [Environment]::ExpandEnvironmentVariables($root)
            
            if (-not (Test-Path $expandedRoot -ErrorAction SilentlyContinue)) {
                continue
            }
            
            $resolvedRoot = (Resolve-Path $expandedRoot -ErrorAction SilentlyContinue).Path
            if (-not $resolvedRoot) { continue }
            
            $normalizedRoot = $(if ($sep -eq '\') { $resolvedRoot.Replace('/', '\') } else { $resolvedRoot.Replace('\', '/') })
            $normalizedRoot = $normalizedRoot.TrimEnd($sep).ToLower()
            
            if ($normalizedResolved -eq $normalizedRoot -or $normalizedResolved.StartsWith("$normalizedRoot$sep")) {
                $allowed = $true
                $matchedRoot = $resolvedRoot
                break
            }
        }
        
        if ($allowed) {
            return @{ Success = $true; Path = $resolvedPath; Message = "Path allowed"; Root = $matchedRoot }
        }
        else {
            return @{
                Success = $false
                Path = $resolvedPath
                Message = "Path not within allowed roots: $resolvedPath"
                Reason = "OutsideAllowedRoots"
            }
        }
    }
    catch {
        return @{
            Success = $false
            Path = $null
            Message = "Path validation error: $($_.Exception.Message)"
            Reason = "ValidationError"
        }
    }
}

# ===== URL Security Configuration =====

$global:URLSecurityEnabled = $true
$global:AllowedSchemes = @('https')
$global:AllowedDomains = @()  # Empty = allow all non-blocked
$global:BlockedDomains = @(
    'localhost'
    '127.0.0.1'
    '0.0.0.0'
    '169.254.*'
    '10.*'
    '172.16.*'
    '192.168.*'
)

function Test-UrlAllowed {
    <#
    .SYNOPSIS
    Validates that a URL is safe to access
    
    .PARAMETER Url
    The URL to validate
    
    .PARAMETER AllowHttp
    If set, allows http:// in addition to https://
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [switch]$AllowHttp
    )
    
    if (-not $global:URLSecurityEnabled) {
        return @{ Success = $true; Url = $Url; Message = "Security bypassed"; Bypassed = $true }
    }
    
    # Auto-add https if no scheme
    if ($Url -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $Url = "https://$Url"
    }
    
    try {
        $uri = [System.Uri]::new($Url)
    }
    catch {
        return @{
            Success = $false
            Url = $null
            Message = "Invalid URL format: $($_.Exception.Message)"
            Reason = "InvalidFormat"
        }
    }
    
    # Check scheme
    $allowedSchemes = $global:AllowedSchemes
    if ($AllowHttp -and 'http' -notin $allowedSchemes) {
        $allowedSchemes = $allowedSchemes + 'http'
    }
    
    if ($uri.Scheme -notin $allowedSchemes) {
        return @{
            Success = $false
            Url = $Url
            Message = "Scheme '$($uri.Scheme)' not allowed. Allowed: $($allowedSchemes -join ', ')"
            Reason = "BlockedScheme"
        }
    }
    
    $urlHost = $uri.Host.ToLower()
    
    # Check blocked domains
    foreach ($blocked in $global:BlockedDomains) {
        $pattern = '^' + ($blocked -replace '\*', '.*') + '$'
        if ($urlHost -match $pattern) {
            return @{
                Success = $false
                Url = $Url
                Message = "Domain '$urlHost' is blocked"
                Reason = "BlockedDomain"
            }
        }
    }
    
    # Check allowed domains (if configured)
    if ($global:AllowedDomains.Count -gt 0) {
        $domainAllowed = $false
        foreach ($allowed in $global:AllowedDomains) {
            $pattern = '^' + ($allowed -replace '\*', '.*') + '$'
            if ($urlHost -match $pattern) {
                $domainAllowed = $true
                break
            }
        }
        
        if (-not $domainAllowed) {
            return @{
                Success = $false
                Url = $Url
                Message = "Domain '$urlHost' not in allowlist"
                Reason = "DomainNotAllowed"
                AllowedDomains = $global:AllowedDomains
            }
        }
    }
    
    # Block embedded credentials
    if ($uri.UserInfo) {
        return @{
            Success = $false
            Url = $Url
            Message = "URLs with embedded credentials not allowed"
            Reason = "EmbeddedCredentials"
        }
    }
    
    return @{
        Success = $true
        Url = $uri.AbsoluteUri
        Host = $urlHost
        Scheme = $uri.Scheme
        Message = "URL allowed"
    }
}

# ===== Utility Functions =====

function Add-AllowedRoot {
    <#
    .SYNOPSIS
    Add a path to the allowed roots list
    #>
    param([Parameter(Mandatory)][string]$Path)
    
    if ($Path -notin $global:AllowedRoots) {
        $global:AllowedRoots += $Path
        Write-Host "Added to allowed roots: $Path" -ForegroundColor Green
    }
}

function Remove-AllowedRoot {
    <#
    .SYNOPSIS
    Remove a path from the allowed roots list
    #>
    param([Parameter(Mandatory)][string]$Path)
    
    $global:AllowedRoots = @($global:AllowedRoots | Where-Object { $_ -ne $Path })
    Write-Host "Removed from allowed roots: $Path" -ForegroundColor Yellow
}

function Get-AllowedRoots {
    <#
    .SYNOPSIS
    List all allowed root paths
    #>
    Write-Host "`n===== Allowed Roots =====" -ForegroundColor Cyan
    foreach ($root in $global:AllowedRoots) {
        $exists = Test-Path $root -ErrorAction SilentlyContinue
        $status = if ($exists) { "[OK]" } else { "[MISSING]" }
        $color = if ($exists) { "Green" } else { "Yellow" }
        Write-Host "  $status $root" -ForegroundColor $color
    }
    Write-Host ""
}

Write-Verbose "SecurityUtils loaded: Test-PathAllowed, Test-UrlAllowed"
