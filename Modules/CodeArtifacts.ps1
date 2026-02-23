# ============= CodeArtifacts.ps1 — AI Code Generation Artifacts =============
# Detects code blocks in AI responses, saves them to files, and executes them.
# Supports PowerShell, Python, Node.js, batch, bash, and more.
#
# Two modes:
#   1. Intent-driven — AI uses save_code / run_code intents
#   2. Interactive  — user types 'code', 'save 1', 'run 2' in chat
#
# Must be loaded AFTER ResponseParser.ps1 and SafetySystem.ps1

$global:ArtifactsPath = Join-Path (Split-Path $PROFILE -Parent) 'Artifacts'
$global:SessionArtifacts = @()

# Language → file extension + execution command mapping
$global:ArtifactRunners = @{
    'powershell' = @{ Ext = '.ps1';  Cmd = 'pwsh -NoProfile -File "{0}"'; Safe = $true }
    'ps1'        = @{ Ext = '.ps1';  Cmd = 'pwsh -NoProfile -File "{0}"'; Safe = $true }
    'pwsh'       = @{ Ext = '.ps1';  Cmd = 'pwsh -NoProfile -File "{0}"'; Safe = $true }
    'python'     = @{ Ext = '.py';   Cmd = 'python "{0}"';                Safe = $true }
    'py'         = @{ Ext = '.py';   Cmd = 'python "{0}"';                Safe = $true }
    'javascript' = @{ Ext = '.js';   Cmd = 'node "{0}"';                  Safe = $true }
    'js'         = @{ Ext = '.js';   Cmd = 'node "{0}"';                  Safe = $true }
    'typescript' = @{ Ext = '.ts';   Cmd = 'npx tsx "{0}"';               Safe = $true }
    'ts'         = @{ Ext = '.ts';   Cmd = 'npx tsx "{0}"';               Safe = $true }
    'bash'       = @{ Ext = '.sh';   Cmd = 'bash "{0}"';                  Safe = $true }
    'sh'         = @{ Ext = '.sh';   Cmd = 'bash "{0}"';                  Safe = $true }
    'bat'        = @{ Ext = '.bat';  Cmd = 'cmd /c "{0}"';                Safe = $false }
    'cmd'        = @{ Ext = '.bat';  Cmd = 'cmd /c "{0}"';                Safe = $false }
    'ruby'       = @{ Ext = '.rb';   Cmd = 'ruby "{0}"';                  Safe = $true }
    'go'         = @{ Ext = '.go';   Cmd = 'go run "{0}"';                Safe = $true }
    'rust'       = @{ Ext = '.rs';   Cmd = 'rustc "{0}" -o "{0}.exe" && "{0}.exe"'; Safe = $true }
    'sql'        = @{ Ext = '.sql';  Cmd = $null;                         Safe = $true }
    'html'       = @{ Ext = '.html'; Cmd = 'start "{0}"';                 Safe = $true }
    'css'        = @{ Ext = '.css';  Cmd = $null;                         Safe = $true }
    'json'       = @{ Ext = '.json'; Cmd = $null;                         Safe = $true }
    'yaml'       = @{ Ext = '.yaml'; Cmd = $null;                         Safe = $true }
    'yml'        = @{ Ext = '.yml';  Cmd = $null;                         Safe = $true }
    'xml'        = @{ Ext = '.xml';  Cmd = $null;                         Safe = $true }
    'markdown'   = @{ Ext = '.md';   Cmd = $null;                         Safe = $true }
    'md'         = @{ Ext = '.md';   Cmd = $null;                         Safe = $true }
    'csv'        = @{ Ext = '.csv';  Cmd = $null;                         Safe = $true }
    'toml'       = @{ Ext = '.toml'; Cmd = $null;                         Safe = $true }
    'dockerfile' = @{ Ext = '';      Cmd = $null;                         Safe = $true }
    'csharp'     = @{ Ext = '.cs';   Cmd = 'dotnet-script "{0}"';         Safe = $true }
    'c'          = @{ Ext = '.c';    Cmd = $null;                         Safe = $true }
    'cpp'        = @{ Ext = '.cpp';  Cmd = $null;                         Safe = $true }
    'java'       = @{ Ext = '.java'; Cmd = $null;                         Safe = $true }
}

function Initialize-ArtifactsDirectory {
    <#
    .SYNOPSIS
    Ensure the Artifacts directory exists.
    #>
    if (-not (Test-Path $global:ArtifactsPath)) {
        New-Item -ItemType Directory -Path $global:ArtifactsPath -Force | Out-Null
    }
}

function Get-CodeBlocks {
    <#
    .SYNOPSIS
    Parse a text string (AI response) and extract all fenced code blocks.

    .DESCRIPTION
    Returns an array of objects with Language, Code, LineStart, and an auto-assigned Index.
    Stores them in $global:SessionArtifacts for interactive save/run.

    .PARAMETER Text
    The AI response text to parse.

    .PARAMETER Track
    If set, stores extracted blocks in $global:SessionArtifacts.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$Track
    )

    $blocks = @()
    $lines = $Text -split "`n"
    $inBlock = $false
    $currentLang = ''
    $currentCode = @()
    $idx = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^```(\w*)\s*(.*)' -and -not $inBlock) {
            $inBlock = $true
            $currentLang = $Matches[1].ToLower()
            $currentFileName = if ($Matches[2].Trim()) { $Matches[2].Trim() } else { $null }
            $currentCode = @()
        }
        elseif ($line -match '^```' -and $inBlock) {
            $inBlock = $false
            $idx++
            $code = $currentCode -join "`n"
            if ($code.Trim().Length -gt 0) {
                $blocks += [PSCustomObject]@{
                    Index     = $idx
                    Language  = if ($currentLang) { $currentLang } else { 'text' }
                    FileName  = $currentFileName
                    Code      = $code
                    LineCount = $currentCode.Count
                    Saved     = $false
                    SavedPath = $null
                    Executed  = $false
                }
            }
        }
        elseif ($inBlock) {
            $currentCode += $line
        }
    }

    # Handle truncated response: if still inside a code block at end of input, save it
    if ($inBlock -and $currentCode.Count -gt 0) {
        $idx++
        $code = $currentCode -join "`n"
        if ($code.Trim().Length -gt 0) {
            $blocks += [PSCustomObject]@{
                Index     = $idx
                Language  = if ($currentLang) { $currentLang } else { 'text' }
                FileName  = $currentFileName
                Code      = $code
                LineCount = $currentCode.Count
                Saved     = $false
                SavedPath = $null
                Executed  = $false
            }
        }
    }

    if ($Track -and $blocks.Count -gt 0) {
        $global:SessionArtifacts = $blocks
    }

    return $blocks
}

function Show-SessionArtifacts {
    <#
    .SYNOPSIS
    Display the code blocks extracted from the last AI response.
    #>
    if ($global:SessionArtifacts.Count -eq 0) {
        Write-Host "No code artifacts in current session." -ForegroundColor DarkGray
        Write-Host "Code blocks from AI responses are tracked automatically." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n===== Code Artifacts =====" -ForegroundColor Cyan
    foreach ($block in $global:SessionArtifacts) {
        $langLabel = if ($block.Language -ne 'text') { $block.Language } else { 'unknown' }
        $runner = $global:ArtifactRunners[$block.Language]
        $canRun = if ($runner -and $runner.Cmd) { ' [runnable]' } else { '' }
        $savedLabel = if ($block.Saved) { " -> $($block.SavedPath)" } else { '' }
        $execLabel = if ($block.Executed) { ' [ran]' } else { '' }

        Write-Host "`n  [$($block.Index)] " -ForegroundColor Yellow -NoNewline
        Write-Host "$langLabel ($($block.LineCount) lines)$canRun$execLabel$savedLabel" -ForegroundColor White

        # Show preview (first 4 lines)
        $preview = ($block.Code -split "`n" | Select-Object -First 4) -join "`n"
        if ($block.LineCount -gt 4) { $preview += "`n    ..." }
        foreach ($pLine in ($preview -split "`n")) {
            Write-Host "    $pLine" -ForegroundColor Gray
        }
    }

    Write-Host "`n  Commands: " -NoNewline -ForegroundColor DarkGray
    Write-Host "save <#> [path]" -NoNewline -ForegroundColor DarkCyan
    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host "run <#>" -NoNewline -ForegroundColor DarkCyan
    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host "save-all [dir]" -ForegroundColor DarkCyan
    Write-Host ""
}

function Save-Artifact {
    <#
    .SYNOPSIS
    Save a code artifact to a file.

    .PARAMETER Index
    The artifact index from Show-SessionArtifacts.

    .PARAMETER Path
    Optional file path. If omitted, generates a name in the Artifacts directory.

    .PARAMETER Code
    Direct code string to save (bypasses index lookup).

    .PARAMETER Language
    Language hint when using -Code directly.

    .PARAMETER Force
    Overwrite existing files without prompting.
    #>
    param(
        [int]$Index,
        [string]$Path,
        [string]$Code,
        [string]$Language,
        [switch]$Force
    )

    Initialize-ArtifactsDirectory

    # Resolve the code block
    $block = $null
    if ($Code) {
        $lang = if ($Language) { $Language.ToLower() } else { 'text' }
        $block = [PSCustomObject]@{
            Index    = 0
            Language = $lang
            Code     = $Code
            LineCount = ($Code -split "`n").Count
            Saved    = $false
            SavedPath = $null
            Executed = $false
        }
    }
    elseif ($Index -gt 0 -and $Index -le $global:SessionArtifacts.Count) {
        $block = $global:SessionArtifacts[$Index - 1]
    }
    else {
        return @{
            Success = $false
            Output  = "Invalid artifact index '$Index'. Use 'code' to list artifacts."
            Error   = $true
        }
    }

    # Determine file path
    if (-not $Path) {
        $runner = $global:ArtifactRunners[$block.Language]
        $ext = if ($runner) { $runner.Ext } else { '.txt' }
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Path = Join-Path $global:ArtifactsPath "artifact_${timestamp}_$($block.Index)$ext"
    }
    else {
        # Resolve relative paths against current directory
        if (-not [System.IO.Path]::IsPathRooted($Path)) {
            $Path = Join-Path (Get-Location).Path $Path
        }
    }

    # Check for existing file
    if ((Test-Path $Path) -and -not $Force) {
        Write-Host "File exists: $Path" -ForegroundColor Yellow
        Write-Host "Overwrite? (y/N): " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -ne 'y') {
            return @{ Success = $false; Output = "Save cancelled."; Error = $false }
        }
    }

    # Ensure parent directory exists
    $parentDir = Split-Path $Path -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    try {
        $block.Code | Set-Content -Path $Path -Encoding UTF8 -NoNewline
        $block.Saved = $true
        $block.SavedPath = $Path

        $relPath = try { [System.IO.Path]::GetRelativePath((Get-Location).Path, $Path) } catch { $Path }
        Write-Host "Artifact saved: $relPath ($($block.LineCount) lines, $($block.Language))" -ForegroundColor Green
        return @{
            Success  = $true
            Output   = "Saved $($block.Language) artifact to $Path ($($block.LineCount) lines)"
            Path     = $Path
            Language = $block.Language
        }
    }
    catch {
        return @{
            Success = $false
            Output  = "Failed to save artifact: $($_.Exception.Message)"
            Error   = $true
        }
    }
}

function Save-AllArtifacts {
    <#
    .SYNOPSIS
    Save all session artifacts to a directory.

    .PARAMETER Directory
    Target directory. Defaults to Artifacts/.
    #>
    param([string]$Directory)

    if ($global:SessionArtifacts.Count -eq 0) {
        Write-Host "No artifacts to save." -ForegroundColor DarkGray
        return
    }

    if (-not $Directory) { $Directory = $global:ArtifactsPath }
    Initialize-ArtifactsDirectory

    $saved = 0
    foreach ($block in $global:SessionArtifacts) {
        $runner = $global:ArtifactRunners[$block.Language]
        $ext = if ($runner) { $runner.Ext } else { '.txt' }
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $filePath = Join-Path $Directory "artifact_${timestamp}_$($block.Index)$ext"

        try {
            $block.Code | Set-Content -Path $filePath -Encoding UTF8 -NoNewline
            $block.Saved = $true
            $block.SavedPath = $filePath
            $saved++
            Write-Host "  [$($block.Index)] $($block.Language) -> $filePath" -ForegroundColor Green
        }
        catch {
            Write-Host "  [$($block.Index)] Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "$saved artifact(s) saved to $Directory" -ForegroundColor Cyan
}

function Invoke-Artifact {
    <#
    .SYNOPSIS
    Execute a code artifact. Saves to a temp file if not already saved, then runs it.

    .PARAMETER Index
    The artifact index from Show-SessionArtifacts.

    .PARAMETER Code
    Direct code string to execute (bypasses index lookup).

    .PARAMETER Language
    Language hint when using -Code directly.

    .PARAMETER NoConfirm
    Skip the execution confirmation prompt.

    .PARAMETER Arguments
    Additional arguments to pass to the script.
    #>
    param(
        [int]$Index,
        [string]$Code,
        [string]$Language,
        [switch]$NoConfirm,
        [string]$Arguments
    )

    # Resolve the code block
    $block = $null
    if ($Code) {
        $lang = if ($Language) { $Language.ToLower() } else { 'powershell' }
        $block = [PSCustomObject]@{
            Index    = 0
            Language = $lang
            Code     = $Code
            LineCount = ($Code -split "`n").Count
            Saved    = $false
            SavedPath = $null
            Executed = $false
        }
    }
    elseif ($Index -gt 0 -and $Index -le $global:SessionArtifacts.Count) {
        $block = $global:SessionArtifacts[$Index - 1]
    }
    else {
        return @{
            Success = $false
            Output  = "Invalid artifact index '$Index'. Use 'code' to list artifacts."
            Error   = $true
        }
    }

    # Check if this language is executable
    $runner = $global:ArtifactRunners[$block.Language]
    if (-not $runner -or -not $runner.Cmd) {
        return @{
            Success = $false
            Output  = "Language '$($block.Language)' is not executable. Supported: $((($global:ArtifactRunners.Keys | Where-Object { $global:ArtifactRunners[$_].Cmd }) | Sort-Object -Unique) -join ', ')"
            Error   = $true
        }
    }

    # Safety confirmation
    if (-not $NoConfirm) {
        Write-Host "`n--- Code to execute ($($block.Language), $($block.LineCount) lines) ---" -ForegroundColor Yellow
        $preview = ($block.Code -split "`n" | Select-Object -First 15) -join "`n"
        Write-Host $preview -ForegroundColor Gray
        if ($block.LineCount -gt 15) {
            Write-Host "  ... ($($block.LineCount - 15) more lines)" -ForegroundColor DarkGray
        }
        Write-Host "---" -ForegroundColor Yellow

        # Extra warning for unsafe languages
        if (-not $runner.Safe) {
            Write-Host "WARNING: $($block.Language) scripts can modify system state." -ForegroundColor Red
        }

        Write-Host "Execute? (y/N): " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -ne 'y') {
            return @{ Success = $false; Output = "Execution cancelled by user."; Error = $false }
        }
    }

    # Determine the file to execute
    $execPath = $block.SavedPath
    if (-not $execPath -or -not (Test-Path $execPath)) {
        # Save to temp file
        $ext = $runner.Ext
        $tempFile = Join-Path $env:TEMP "bildsyps_artifact_$(Get-Date -Format 'HHmmss')$ext"
        try {
            $block.Code | Set-Content -Path $tempFile -Encoding UTF8 -NoNewline
            $execPath = $tempFile
        }
        catch {
            return @{
                Success = $false
                Output  = "Failed to write temp file: $($_.Exception.Message)"
                Error   = $true
            }
        }
    }

    # Build the execution command
    $execCmd = $runner.Cmd -f $execPath
    if ($Arguments) { $execCmd += " $Arguments" }

    # Execute
    $startTime = Get-Date
    try {
        Write-Host "Executing $($block.Language) artifact..." -ForegroundColor Cyan
        $output = Invoke-Expression $execCmd 2>&1
        $outputStr = if ($output) { ($output | Out-String).Trim() } else { '' }
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

        $block.Executed = $true

        if ($outputStr) {
            Write-Host "`n--- Output ---" -ForegroundColor Green
            Write-Host $outputStr
            Write-Host "--- End ($($elapsed)s) ---`n" -ForegroundColor Green
        }
        else {
            Write-Host "Completed (no output, $($elapsed)s)" -ForegroundColor Green
        }

        # Clean up temp file if we created one
        if ($execPath -ne $block.SavedPath -and (Test-Path $execPath)) {
            Remove-Item $execPath -Force -ErrorAction SilentlyContinue
        }

        return @{
            Success       = $true
            Output        = if ($outputStr) { $outputStr } else { "Executed $($block.Language) artifact ($($block.LineCount) lines, $($elapsed)s)" }
            ExecutionTime = $elapsed
            Language      = $block.Language
        }
    }
    catch {
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

        # Clean up temp file
        if ($execPath -ne $block.SavedPath -and (Test-Path $execPath)) {
            Remove-Item $execPath -Force -ErrorAction SilentlyContinue
        }

        $errMsg = $_.Exception.Message
        Write-Host "Execution failed ($($elapsed)s): $errMsg" -ForegroundColor Red

        return @{
            Success = $false
            Output  = "Execution failed: $errMsg"
            Error   = $true
        }
    }
}

function Get-Artifacts {
    <#
    .SYNOPSIS
    List saved artifacts in the Artifacts directory.
    #>
    Initialize-ArtifactsDirectory

    $files = Get-ChildItem $global:ArtifactsPath -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    if ($files.Count -eq 0) {
        Write-Host "No saved artifacts in $global:ArtifactsPath" -ForegroundColor DarkGray
        return
    }

    Write-Host "`n===== Saved Artifacts =====" -ForegroundColor Cyan
    $idx = 0
    foreach ($f in $files | Select-Object -First 20) {
        $idx++
        $size = if ($f.Length -lt 1024) { "$($f.Length)B" }
               elseif ($f.Length -lt 1048576) { "$([math]::Round($f.Length/1024,1))KB" }
               else { "$([math]::Round($f.Length/1048576,1))MB" }
        $age = (Get-Date) - $f.LastWriteTime
        $ageStr = if ($age.TotalMinutes -lt 60) { "$([math]::Round($age.TotalMinutes))m ago" }
                  elseif ($age.TotalHours -lt 24) { "$([math]::Round($age.TotalHours,1))h ago" }
                  else { "$([math]::Round($age.TotalDays))d ago" }

        Write-Host "  $($f.Name)" -ForegroundColor Yellow -NoNewline
        Write-Host " ($size, $ageStr)" -ForegroundColor DarkGray
    }

    if ($files.Count -gt 20) {
        Write-Host "  ... and $($files.Count - 20) more" -ForegroundColor DarkGray
    }
    Write-Host "  Path: $global:ArtifactsPath" -ForegroundColor DarkGray
    Write-Host ""
}

function Remove-Artifact {
    <#
    .SYNOPSIS
    Delete a saved artifact file.

    .PARAMETER Name
    File name or pattern to delete from the Artifacts directory.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $target = Join-Path $global:ArtifactsPath $Name
    if (-not (Test-Path $target)) {
        # Try as a glob
        $found = Get-ChildItem $global:ArtifactsPath -Filter $Name -ErrorAction SilentlyContinue
        if ($found.Count -eq 0) {
            Write-Host "Artifact '$Name' not found." -ForegroundColor Yellow
            return
        }
        foreach ($m in $found) {
            Remove-Item $m.FullName -Force
            Write-Host "Removed: $($m.Name)" -ForegroundColor Green
        }
    }
    else {
        Remove-Item $target -Force
        Write-Host "Removed: $Name" -ForegroundColor Green
    }
}

function Invoke-ArtifactFromChat {
    <#
    .SYNOPSIS
    Process artifact-related commands from the chat loop.
    Returns $true if the input was an artifact command (handled), $false otherwise.

    .PARAMETER InputText
    The user's chat input.
    #>
    param([string]$InputText)

    switch -Regex ($InputText) {
        '^code$' {
            Show-SessionArtifacts
            return $true
        }
        '^(artifacts?|saved)$' {
            Get-Artifacts
            return $true
        }
        '^save\s+(\d+)$' {
            Save-Artifact -Index ([int]$Matches[1])
            return $true
        }
        '^save\s+(\d+)\s+(.+)$' {
            Save-Artifact -Index ([int]$Matches[1]) -Path $Matches[2]
            return $true
        }
        '^save-all$' {
            Save-AllArtifacts
            return $true
        }
        '^save-all\s+(.+)$' {
            Save-AllArtifacts -Directory $Matches[1]
            return $true
        }
        '^run\s+(\d+)$' {
            Invoke-Artifact -Index ([int]$Matches[1])
            return $true
        }
        '^run\s+(\d+)\s+(.+)$' {
            Invoke-Artifact -Index ([int]$Matches[1]) -Arguments $Matches[2]
            return $true
        }
    }

    return $false
}

function Register-ArtifactsFromResponse {
    <#
    .SYNOPSIS
    Called after each AI response to extract and track code blocks.
    Shows a summary if code blocks were found.

    .PARAMETER ResponseText
    The raw AI response text.
    #>
    param([string]$ResponseText)

    $blocks = Get-CodeBlocks -Text $ResponseText -Track
    if ($blocks.Count -gt 0) {
        $runnable = @($blocks | Where-Object {
            $r = $global:ArtifactRunners[$_.Language]
            $r -and $r.Cmd
        })

        $summary = "$($blocks.Count) code block(s) detected"
        if ($runnable.Count -gt 0) {
            $summary += " ($($runnable.Count) runnable)"
        }
        Write-Host "  [$summary — type 'code' to view, 'save <#>' or 'run <#>']" -ForegroundColor DarkCyan
    }
}

# ===== Tab Completion =====
Register-ArgumentCompleter -CommandName Remove-Artifact -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if (Test-Path $global:ArtifactsPath) {
        Get-ChildItem $global:ArtifactsPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$wordToComplete*" } | Sort-Object Name | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', "Artifact: $($_.Name)")
        }
    }
}

# ===== Aliases =====
Set-Alias artifacts Get-Artifacts -Force

Write-Verbose "CodeArtifacts loaded: Save-Artifact, Invoke-Artifact, Show-SessionArtifacts, Get-Artifacts"
