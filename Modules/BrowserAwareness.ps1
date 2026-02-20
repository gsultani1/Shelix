# ============= BrowserAwareness.ps1 — Browser Tab Awareness =============
# Read the active browser tab URL and optionally fetch its content.
# Uses multiple strategies: UI Automation (address bar), window title,
# and browser history SQLite as fallback.
#
# Depends on: WebTools.ps1 (Get-WebPageContent)

# ===== Supported Browsers =====
$global:BrowserProcessNames = @{
    'msedge'  = @{ Name = 'Microsoft Edge';  HistoryPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History" }
    'chrome'  = @{ Name = 'Google Chrome';   HistoryPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History" }
    'firefox' = @{ Name = 'Mozilla Firefox'; HistoryPath = "$env:APPDATA\Mozilla\Firefox\Profiles" }
    'brave'   = @{ Name = 'Brave';           HistoryPath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\History" }
}

function Get-ActiveBrowserTab {
    <#
    .SYNOPSIS
    Get the URL and title of the currently active browser tab.

    .DESCRIPTION
    Tries multiple strategies in order:
    1. UI Automation — reads the address bar from the focused browser window
    2. Window title — extracts the page title from the browser process
    3. Browser history — reads the last visited URL from the SQLite history DB

    .PARAMETER Browser
    Optional browser to target. If omitted, checks the foreground window first,
    then tries all known browsers.
    #>
    param([string]$Browser)

    # Strategy 1: Try UI Automation on the foreground window
    $uiResult = Get-BrowserUrlViaUIAutomation -Browser $Browser
    if ($uiResult.Success) {
        return $uiResult
    }

    # Strategy 2: Window title from process
    $titleResult = Get-BrowserUrlFromWindowTitle -Browser $Browser
    if ($titleResult.Success) {
        return $titleResult
    }

    # Strategy 3: Browser history DB
    $historyResult = Get-BrowserUrlFromHistory -Browser $Browser
    if ($historyResult.Success) {
        return $historyResult
    }

    return @{
        Success = $false
        Output  = "Could not detect active browser tab. Is a browser running?"
        Error   = $true
    }
}

function Get-BrowserUrlViaUIAutomation {
    <#
    .SYNOPSIS
    Read the URL from a browser's address bar using the UI Automation COM API.
    Works for Chromium-based browsers (Chrome, Edge, Brave) and Firefox.
    #>
    param([string]$Browser)

    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
    }
    catch {
        return @{ Success = $false; Method = 'UIAutomation'; Error = 'UI Automation assemblies not available' }
    }

    try {
        # Find the browser process
        $proc = $null
        if ($Browser) {
            $proc = Get-Process -Name $Browser -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 } |
                Select-Object -First 1
        }
        else {
            # Try each known browser
            foreach ($name in $global:BrowserProcessNames.Keys) {
                $proc = Get-Process -Name $name -ErrorAction SilentlyContinue |
                    Where-Object { $_.MainWindowHandle -ne 0 } |
                    Select-Object -First 1
                if ($proc) { break }
            }
        }

        if (-not $proc) {
            return @{ Success = $false; Method = 'UIAutomation'; Error = 'No browser window found' }
        }

        $browserName = if ($global:BrowserProcessNames.ContainsKey($proc.ProcessName)) {
            $global:BrowserProcessNames[$proc.ProcessName].Name
        } else { $proc.ProcessName }

        # Get the automation element for the browser window
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)

        # Find the address bar — Chromium browsers use Edit control with specific automation IDs
        $editCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit
        )

        $editElements = $root.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            $editCondition
        )

        $url = $null
        foreach ($el in $editElements) {
            try {
                $name = $el.Current.Name
                $automationId = $el.Current.AutomationId

                # Chromium address bar has specific patterns
                if ($automationId -eq 'addressEditBox' -or
                    $automationId -eq 'view_id_omnibox' -or
                    $name -like '*Address*' -or
                    $name -like '*URL*' -or
                    $name -like '*address*') {

                    $valuePattern = $null
                    if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
                        $candidateUrl = $valuePattern.Current.Value
                        if ($candidateUrl -and $candidateUrl.Length -gt 3) {
                            $url = $candidateUrl
                            break
                        }
                    }
                }
            }
            catch { continue }
        }

        # Firefox uses a different structure — try ToolBar > Edit
        if (-not $url -and $proc.ProcessName -eq 'firefox') {
            $toolbarCondition = [System.Windows.Automation.PropertyCondition]::new(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::ToolBar
            )
            $toolbars = $root.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                $toolbarCondition
            )
            foreach ($tb in $toolbars) {
                $edits = $tb.FindAll(
                    [System.Windows.Automation.TreeScope]::Descendants,
                    $editCondition
                )
                foreach ($el in $edits) {
                    try {
                        $valuePattern = $null
                        if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
                            $candidateUrl = $valuePattern.Current.Value
                            if ($candidateUrl -and $candidateUrl -match '^\S+\.\S+') {
                                $url = $candidateUrl
                                break
                            }
                        }
                    }
                    catch { continue }
                }
                if ($url) { break }
            }
        }

        if (-not $url) {
            return @{ Success = $false; Method = 'UIAutomation'; Error = 'Could not read address bar' }
        }

        # Normalize URL — browsers sometimes show without scheme
        if ($url -notmatch '^https?://') {
            $url = "https://$url"
        }

        $title = $proc.MainWindowTitle -replace "\s*[-–—]\s*$browserName\s*$", ''

        return @{
            Success = $true
            Url     = $url
            Title   = $title.Trim()
            Browser = $browserName
            Method  = 'UIAutomation'
            Output  = "$browserName tab: $url"
        }
    }
    catch {
        return @{ Success = $false; Method = 'UIAutomation'; Error = $_.Exception.Message }
    }
}

function Get-BrowserUrlFromWindowTitle {
    <#
    .SYNOPSIS
    Extract browser info from the window title. Returns the title and browser name
    but not the URL (browsers don't show URLs in titles). Useful as context.
    #>
    param([string]$Browser)

    $proc = $null
    if ($Browser) {
        $proc = Get-Process -Name $Browser -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
            Select-Object -First 1
    }
    else {
        foreach ($name in $global:BrowserProcessNames.Keys) {
            $proc = Get-Process -Name $name -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
                Select-Object -First 1
            if ($proc) { break }
        }
    }

    if (-not $proc -or -not $proc.MainWindowTitle) {
        return @{ Success = $false; Method = 'WindowTitle'; Error = 'No browser window with title found' }
    }

    $browserName = if ($global:BrowserProcessNames.ContainsKey($proc.ProcessName)) {
        $global:BrowserProcessNames[$proc.ProcessName].Name
    } else { $proc.ProcessName }

    $rawTitle = $proc.MainWindowTitle
    # Strip the browser name suffix (e.g. "Page Title - Google Chrome")
    $title = $rawTitle -replace "\s*[-–—]\s*($($global:BrowserProcessNames.Values.Name -join '|'))\s*$", ''

    # Check if the title itself looks like a URL
    $url = $null
    if ($title -match '^https?://') {
        $url = $title
    }

    return @{
        Success = $true
        Url     = $url
        Title   = $title.Trim()
        Browser = $browserName
        Method  = 'WindowTitle'
        Output  = if ($url) { "$browserName tab: $url" } else { "$browserName tab: '$($title.Trim())'" }
    }
}

function Get-BrowserUrlFromHistory {
    <#
    .SYNOPSIS
    Read the most recently visited URL from the browser's SQLite history database.
    Works for Chromium-based browsers (Chrome, Edge, Brave). Copies the DB first
    since the browser holds a lock on it.
    #>
    param([string]$Browser)

    $browsersToTry = @()
    if ($Browser -and $global:BrowserProcessNames.ContainsKey($Browser)) {
        $browsersToTry += $Browser
    }
    else {
        # Prioritize by what's running
        foreach ($name in $global:BrowserProcessNames.Keys) {
            if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
                $browsersToTry += $name
            }
        }
    }

    foreach ($bName in $browsersToTry) {
        $info = $global:BrowserProcessNames[$bName]

        # Firefox uses a different DB format and profile structure
        if ($bName -eq 'firefox') {
            $profileDir = $info.HistoryPath
            if (-not (Test-Path $profileDir)) { continue }
            $defaultProfile = Get-ChildItem $profileDir -Directory | Where-Object { $_.Name -like '*.default-release' -or $_.Name -like '*.default' } | Select-Object -First 1
            if (-not $defaultProfile) { continue }
            $historyDb = Join-Path $defaultProfile.FullName 'places.sqlite'
        }
        else {
            $historyDb = $info.HistoryPath
        }

        if (-not (Test-Path $historyDb)) { continue }

        # Copy the DB to a temp file (browser holds a lock)
        $tempDb = Join-Path $env:TEMP "bildsyps_browser_history_$bName.sqlite"
        try {
            Copy-Item $historyDb $tempDb -Force -ErrorAction Stop
        }
        catch {
            continue
        }

        # Query the most recent URL
        try {
            $query = if ($bName -eq 'firefox') {
                "SELECT url, title FROM moz_places ORDER BY last_visit_date DESC LIMIT 1"
            }
            else {
                "SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 1"
            }

            # Use System.Data.SQLite if available, otherwise try sqlite3 CLI
            $url = $null
            $title = $null

            if (Get-Command sqlite3 -ErrorAction SilentlyContinue) {
                $output = & sqlite3 $tempDb $query 2>$null
                if ($output) {
                    $parts = $output -split '\|', 2
                    $url = $parts[0]
                    $title = if ($parts.Count -gt 1) { $parts[1] } else { '' }
                }
            }
            else {
                # Try .NET SQLite
                try {
                    Add-Type -Path "$env:ProgramFiles\System.Data.SQLite\bin\System.Data.SQLite.dll" -ErrorAction Stop
                    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tempDb;Read Only=True")
                    $conn.Open()
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = $query
                    $reader = $cmd.ExecuteReader()
                    if ($reader.Read()) {
                        $url = $reader.GetString(0)
                        $title = if (-not $reader.IsDBNull(1)) { $reader.GetString(1) } else { '' }
                    }
                    $reader.Close()
                    $conn.Close()
                }
                catch {
                    # No SQLite available
                    continue
                }
            }

            # Clean up temp file
            Remove-Item $tempDb -Force -ErrorAction SilentlyContinue

            if ($url) {
                return @{
                    Success = $true
                    Url     = $url
                    Title   = $title
                    Browser = $info.Name
                    Method  = 'History'
                    Output  = "$($info.Name) recent: $url"
                }
            }
        }
        catch {
            Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
            continue
        }
    }

    return @{ Success = $false; Method = 'History'; Error = 'Could not read browser history' }
}

function Get-BrowserPageContent {
    <#
    .SYNOPSIS
    Get the active browser tab URL and fetch its page content for the AI.

    .DESCRIPTION
    Combines Get-ActiveBrowserTab with Get-WebPageContent to deliver the
    current page's text content. Useful for "what am I looking at?" queries.

    .PARAMETER MaxLength
    Maximum characters of page content to return (default 3000).
    #>
    param([int]$MaxLength = 3000)

    $tab = Get-ActiveBrowserTab
    if (-not $tab.Success) {
        return $tab
    }

    if (-not $tab.Url) {
        return @{
            Success = $true
            Output  = "Browser tab: '$($tab.Title)' (URL not available via $($tab.Method) — try UI Automation or install sqlite3)"
            Title   = $tab.Title
            Browser = $tab.Browser
            Method  = $tab.Method
        }
    }

    # Fetch the page content using existing WebTools
    $pageResult = Get-WebPageContent -Url $tab.Url -MaxLength $MaxLength

    if ($pageResult.Success) {
        return @{
            Success = $true
            Url     = $tab.Url
            Title   = $tab.Title
            Browser = $tab.Browser
            Content = $pageResult.Content
            Method  = $tab.Method
            Output  = "Fetched $($pageResult.Length) chars from $($tab.Url) ($($tab.Browser))"
        }
    }
    else {
        return @{
            Success = $false
            Url     = $tab.Url
            Title   = $tab.Title
            Browser = $tab.Browser
            Output  = "Found tab '$($tab.Title)' at $($tab.Url) but fetch failed: $($pageResult.Message)"
            Error   = $true
        }
    }
}

function Get-BrowserTabs {
    <#
    .SYNOPSIS
    List all open browser windows with their titles.
    #>

    $tabs = @()
    foreach ($name in $global:BrowserProcessNames.Keys) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle }
        foreach ($p in $procs) {
            $browserName = $global:BrowserProcessNames[$name].Name
            $title = $p.MainWindowTitle -replace "\s*[-–—]\s*$browserName\s*$", ''
            $tabs += @{
                Browser = $browserName
                Title   = $title.Trim()
                PID     = $p.Id
            }
        }
    }

    if ($tabs.Count -eq 0) {
        Write-Host "No browser windows detected." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n===== Browser Windows =====" -ForegroundColor Cyan
    foreach ($tab in $tabs) {
        Write-Host "  [$($tab.Browser)] $($tab.Title)" -ForegroundColor White
    }
    Write-Host ""
}

# ===== Aliases =====
Set-Alias browser-url  Get-ActiveBrowserTab   -Force
Set-Alias browser-page Get-BrowserPageContent -Force
Set-Alias browser-tabs Get-BrowserTabs        -Force

Write-Verbose "BrowserAwareness loaded: Get-ActiveBrowserTab, Get-BrowserPageContent, Get-BrowserTabs"
