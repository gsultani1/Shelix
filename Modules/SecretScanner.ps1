# ===== SecretScanner.ps1 =====
# Scans known files for accidentally exposed API keys, tokens, and secrets.
# Non-blocking on startup: warns loudly but does not prevent shell from loading.

$global:SecretPatterns = @(
    @{ Name = 'Anthropic API Key';  Pattern = 'sk-ant-api\d{2}-[A-Za-z0-9_-]{20,}' }
    @{ Name = 'OpenAI API Key';     Pattern = 'sk-[A-Za-z0-9]{20,}' }
    @{ Name = 'AWS Access Key';     Pattern = 'AKIA[0-9A-Z]{16}' }
    @{ Name = 'GitHub Token';       Pattern = 'gh[ps]_[A-Za-z0-9]{36,}' }
    @{ Name = 'GitHub Fine-Grained'; Pattern = 'github_pat_[A-Za-z0-9_]{22,}' }
    @{ Name = 'Generic Bearer';     Pattern = 'Bearer\s+[A-Za-z0-9._\-]{20,}' }
    @{ Name = 'Private Key Block';  Pattern = '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' }
    @{ Name = 'Slack Token';        Pattern = 'xox[bpors]-[A-Za-z0-9\-]{10,}' }
    @{ Name = 'Discord Token';      Pattern = '[MN][A-Za-z\d]{23,}\.[\w-]{6}\.[\w-]{27,}' }
    @{ Name = 'Generic Secret Assign'; Pattern = '(?i)(?<![A-Za-z])(password|secret|token|api_?key)\s*[:=]\s*["\x27]?(?!document\.|window\.|console\.|function\b|return\b|new\s|null\b|true\b|false\b|undefined\b|getElementById|querySelector|getAttribute|localStorage|sessionStorage)[A-Za-z0-9/_\+\.\-]{12,}' }
)

function Invoke-SecretScan {
    <#
    .SYNOPSIS
    Scan a list of file paths against all secret patterns. Returns array of findings.
    .PARAMETER Paths
    File paths to scan.
    .PARAMETER ExcludePatterns
    Array of pattern names to skip (e.g. 'Generic Secret Assign').
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [string[]]$ExcludePatterns = @()
    )

    $findings = @()
    foreach ($filePath in $Paths) {
        if (-not (Test-Path $filePath)) { continue }
        try {
            $lines = @(Get-Content $filePath -ErrorAction Stop)
        }
        catch { continue }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            # Skip comment-only lines
            if ("$line".Trim() -match '^(#|//|;)') { continue }
            foreach ($pat in $global:SecretPatterns) {
                if ($ExcludePatterns -contains $pat.Name) { continue }
                if ($line -match $pat.Pattern) {
                    $matched = $Matches[0]
                    # Mask the middle of the secret for display
                    $masked = if ($matched.Length -gt 12) {
                        $matched.Substring(0, 6) + ('*' * [math]::Min(20, $matched.Length - 10)) + $matched.Substring($matched.Length - 4)
                    } else { '*' * $matched.Length }

                    $findings += @{
                        File       = $filePath
                        FileName   = Split-Path $filePath -Leaf
                        Line       = $i + 1
                        Pattern    = $pat.Name
                        Masked     = $masked
                    }
                    break  # One finding per line is enough
                }
            }
        }
    }
    return @(,$findings)
}

function Test-GitStagedSecrets {
    <#
    .SYNOPSIS
    Scan git staged (cached) diff for secrets. Returns findings array.
    #>
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return @() }

    try {
        $diff = git diff --cached --no-color 2>$null
    }
    catch { return @() }
    if (-not $diff) { return @() }

    $findings = @()
    $currentFile = ''
    $lineNum = 0

    foreach ($line in $diff) {
        if ($line -match '^\+\+\+ b/(.+)$') {
            $currentFile = $Matches[1]
            $lineNum = 0
            continue
        }
        if ($line -match '^@@.*\+(\d+)') {
            $lineNum = [int]$Matches[1]
            continue
        }
        if ($line.StartsWith('+') -and -not $line.StartsWith('+++')) {
            $content = $line.Substring(1)
            foreach ($pat in $global:SecretPatterns) {
                if ($content -match $pat.Pattern) {
                    $matched = $Matches[0]
                    $masked = if ($matched.Length -gt 12) {
                        $matched.Substring(0, 6) + ('*' * [math]::Min(20, $matched.Length - 10)) + $matched.Substring($matched.Length - 4)
                    } else { '*' * $matched.Length }

                    $findings += @{
                        File       = $currentFile
                        FileName   = Split-Path $currentFile -Leaf
                        Line       = $lineNum
                        Pattern    = $pat.Name
                        Masked     = $masked
                        Source     = 'git-staged'
                    }
                    break
                }
            }
            $lineNum++
        }
        elseif (-not $line.StartsWith('-')) {
            $lineNum++
        }
    }
    return $findings
}

function Test-StartupSecrets {
    <#
    .SYNOPSIS
    Scan known secret-containing files at startup. Returns findings array.
    Checks: ChatConfig.json, .env, UserSkills.json, and validates .gitignore coverage.
    #>
    $filesToScan = @()

    # BildsyPS config directory
    $configDir = "$global:BildsyPSHome\config"
    if (Test-Path $configDir) {
        Get-ChildItem $configDir -File -ErrorAction SilentlyContinue | ForEach-Object {
            $filesToScan += $_.FullName
        }
    }

    # Project root sensitive files (in case old copies still exist)
    $projectRoot = if ($global:BildsyPSModulePath) { $global:BildsyPSModulePath } else { Split-Path $PROFILE -Parent }
    $rootFiles = @('ChatConfig.json', 'Config\.env', 'UserSkills.json')
    foreach ($f in $rootFiles) {
        $path = Join-Path $projectRoot $f
        if (Test-Path $path) { $filesToScan += $path }
    }

    $findings = Invoke-SecretScan -Paths $filesToScan
    return $findings
}

function Test-GitignoreCovers {
    <#
    .SYNOPSIS
    Validate that .gitignore covers known sensitive files. Returns array of unprotected file names.
    #>
    $projectRoot = if ($global:BildsyPSModulePath) { $global:BildsyPSModulePath } else { Split-Path $PROFILE -Parent }
    $gitignorePath = Join-Path $projectRoot '.gitignore'
    if (-not (Test-Path $gitignorePath)) { return @('(.gitignore missing)') }

    $gitignore = Get-Content $gitignorePath -Raw
    $shouldBeIgnored = @('ChatConfig.json', 'Config/.env', '*.secret', '*.key')
    $unprotected = @()
    foreach ($pattern in $shouldBeIgnored) {
        if ($gitignore -notmatch [regex]::Escape($pattern)) {
            $unprotected += $pattern
        }
    }
    return $unprotected
}

function Show-SecretScanReport {
    <#
    .SYNOPSIS
    Display a formatted report of secret scan findings.
    #>
    param(
        [array]$Findings,
        [array]$GitignoreWarnings,
        [switch]$Quiet
    )

    if ($Findings.Count -eq 0 -and $GitignoreWarnings.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "[SecretScanner] No exposed secrets detected." -ForegroundColor Green
        }
        return
    }

    if ($Findings.Count -gt 0) {
        Write-Host "" -ForegroundColor Red
        Write-Host "  !! SECRET SCANNER WARNING !!" -ForegroundColor Red
        Write-Host "  Found $($Findings.Count) potential secret(s) in scanned files:" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red

        $groupedByFile = $Findings | Group-Object -Property FileName
        foreach ($group in $groupedByFile) {
            Write-Host "  $($group.Name):" -ForegroundColor Yellow
            foreach ($f in $group.Group) {
                Write-Host "    Line $($f.Line): $($f.Pattern) -- $($f.Masked)" -ForegroundColor DarkYellow
            }
        }
        Write-Host ""
        Write-Host "  Ensure these files are in .gitignore and never committed." -ForegroundColor DarkGray
        Write-Host ""
    }

    if ($GitignoreWarnings.Count -gt 0) {
        Write-Host "  [SecretScanner] .gitignore missing coverage for: $($GitignoreWarnings -join ', ')" -ForegroundColor Yellow
    }
}

function Invoke-StartupSecretScan {
    <#
    .SYNOPSIS
    Run the full startup scan and display results. Called from profile on load.
    #>
    $findings = Test-StartupSecrets
    $gitWarnings = Test-GitignoreCovers
    Show-SecretScanReport -Findings $findings -GitignoreWarnings $gitWarnings -Quiet:($findings.Count -eq 0 -and $gitWarnings.Count -eq 0)
}

# ===== Aliases =====
Set-Alias secrets Invoke-StartupSecretScan -Force
Set-Alias scan-secrets Invoke-StartupSecretScan -Force

Write-Verbose "SecretScanner loaded: Invoke-SecretScan, Test-StartupSecrets, Test-GitStagedSecrets"
