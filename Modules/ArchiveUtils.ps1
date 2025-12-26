# ===== ArchiveUtils.ps1 =====
# Archive utilities: zip, unzip, compression helpers

function Compress-ToZip {
    <#
    .SYNOPSIS
    Compress files or folders to a ZIP archive
    
    .PARAMETER source
    Path to file or folder to compress
    
    .PARAMETER destination
    Output ZIP file path (optional, defaults to source.zip)
    
    .EXAMPLE
    Compress-ToZip -source "C:\MyFolder" -destination "C:\backup.zip"
    zip "C:\MyFolder"
    #>
    param(
        [Parameter(Mandatory=$true)][string]$source,
        [string]$destination
    )
    
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

function Expand-FromZip {
    <#
    .SYNOPSIS
    Extract files from a ZIP archive
    
    .PARAMETER source
    Path to ZIP file
    
    .PARAMETER destination
    Output folder (optional, defaults to same directory as ZIP)
    
    .EXAMPLE
    Expand-FromZip -source "C:\backup.zip" -destination "C:\Restored"
    unzip "C:\backup.zip"
    #>
    param(
        [Parameter(Mandatory=$true)][string]$source,
        [string]$destination
    )
    
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

function Get-ArchiveContents {
    <#
    .SYNOPSIS
    List contents of a ZIP archive without extracting
    
    .EXAMPLE
    Get-ArchiveContents "C:\backup.zip"
    #>
    param([Parameter(Mandatory=$true)][string]$Path)
    
    if (!(Test-Path $Path)) {
        Write-Host "Archive not found: $Path" -ForegroundColor Red
        return
    }
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        
        Write-Host "`n===== Archive Contents: $Path =====" -ForegroundColor Cyan
        $zip.Entries | ForEach-Object {
            $size = if ($_.Length -gt 1MB) { "$([math]::Round($_.Length / 1MB, 2)) MB" }
                    elseif ($_.Length -gt 1KB) { "$([math]::Round($_.Length / 1KB, 2)) KB" }
                    else { "$($_.Length) B" }
            Write-Host "  $($_.FullName)" -ForegroundColor White -NoNewline
            Write-Host " ($size)" -ForegroundColor Gray
        }
        Write-Host "====================================`n" -ForegroundColor Cyan
        
        $zip.Dispose()
    } catch {
        Write-Host "Failed to read archive: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ===== Aliases =====
Set-Alias zip Compress-ToZip -Force
Set-Alias unzip Expand-FromZip -Force
Set-Alias ziplist Get-ArchiveContents -Force

Write-Verbose "ArchiveUtils loaded: Compress-ToZip (zip), Expand-FromZip (unzip), Get-ArchiveContents"
