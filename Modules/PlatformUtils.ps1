# ===== PlatformUtils.ps1 =====
# Cross-platform utility functions for file and path operations

function Get-PlatformSeparator {
    <#
    .SYNOPSIS
    Returns the directory separator for the current platform
    #>
    [IO.Path]::DirectorySeparatorChar
}

function Get-NormalizedPath {
    <#
    .SYNOPSIS
    Normalizes path separators for the current platform
    #>
    param([string]$Path)
    $sep = Get-PlatformSeparator
    if ($sep -eq '\') {
        return $Path.Replace('/', '\')
    } else {
        return $Path.Replace('\', '/')
    }
}

function Open-PlatformPath {
    <#
    .SYNOPSIS
    Opens a file or folder using the platform's default handler
    
    .PARAMETER Path
    Path to file/folder or URL to open
    
    .PARAMETER Folder
    If set, opens as folder in file explorer
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Folder
    )
    
    $onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
    
    if ($onWindows) {
        if ($Folder) {
            Start-Process explorer $Path
        } else {
            Start-Process $Path
        }
    }
    elseif ($IsMacOS) {
        & open $Path
    }
    elseif ($IsLinux) {
        & xdg-open $Path
    }
    else {
        throw "Unsupported platform"
    }
}

function Get-PlatformDocumentsPath {
    <#
    .SYNOPSIS
    Returns the Documents folder path for the current platform
    #>
    $onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
    if ($onWindows) {
        return "$env:USERPROFILE\Documents"
    } else {
        return "$HOME/Documents"
    }
}

function Get-PlatformDesktopPath {
    <#
    .SYNOPSIS
    Returns the Desktop folder path for the current platform
    #>
    $onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
    if ($onWindows) {
        return "$env:USERPROFILE\Desktop"
    } else {
        return "$HOME/Desktop"
    }
}

function Get-PlatformDownloadsPath {
    <#
    .SYNOPSIS
    Returns the Downloads folder path for the current platform
    #>
    $onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
    if ($onWindows) {
        return "$env:USERPROFILE\Downloads"
    } else {
        return "$HOME/Downloads"
    }
}

function Get-PlatformTempPath {
    <#
    .SYNOPSIS
    Returns the temp folder path for the current platform
    #>
    [IO.Path]::GetTempPath()
}

function Test-IsWindows {
    <#
    .SYNOPSIS
    Returns true if running on Windows (works on PS 5.1 and 7+)
    #>
    return $IsWindows -or $env:OS -eq 'Windows_NT'
}

function Test-IsMacOS {
    <#
    .SYNOPSIS
    Returns true if running on macOS
    #>
    return $IsMacOS -eq $true
}

function Test-IsLinux {
    <#
    .SYNOPSIS
    Returns true if running on Linux
    #>
    return $IsLinux -eq $true
}

Write-Verbose "PlatformUtils loaded: Open-PlatformPath, Get-PlatformSeparator, Get-NormalizedPath"
