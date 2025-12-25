# ===== ProductivityTools.ps1 =====
# Clipboard, File Analysis, Git, and Calendar tools for AI assistant

# ===== CLIPBOARD OPERATIONS =====

function Get-ClipboardContent {
    <#
    .SYNOPSIS
    Get current clipboard content with type detection
    #>
    try {
        $content = Get-Clipboard -Raw
        if (-not $content) {
            return @{
                Success = $false
                Message = "Clipboard is empty"
            }
        }
        
        # Detect content type
        $type = "text"
        if ($content -match '^\s*[\[\{]' -and $content -match '[\]\}]\s*$') {
            try {
                $null = $content | ConvertFrom-Json
                $type = "json"
            } catch { }
        }
        elseif ($content -match '^"?[\w\s]+",') {
            $type = "csv"
        }
        elseif ($content -match '<[^>]+>') {
            $type = "html"
        }
        elseif ($content -match '^\s*https?://') {
            $type = "url"
        }
        
        return @{
            Success = $true
            Content = $content
            Type = $type
            Length = $content.Length
            Lines = ($content -split "`n").Count
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to read clipboard: $($_.Exception.Message)"
        }
    }
}

function Set-ClipboardContent {
    <#
    .SYNOPSIS
    Set clipboard content
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )
    
    try {
        Set-Clipboard -Value $Content
        return @{
            Success = $true
            Message = "Copied to clipboard ($($Content.Length) characters)"
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to set clipboard: $($_.Exception.Message)"
        }
    }
}

function Convert-ClipboardJson {
    <#
    .SYNOPSIS
    Format clipboard JSON content
    #>
    try {
        $content = Get-Clipboard -Raw
        $json = $content | ConvertFrom-Json
        $formatted = $json | ConvertTo-Json -Depth 10
        Set-Clipboard -Value $formatted
        return @{
            Success = $true
            Output = "JSON formatted and copied back to clipboard"
            Preview = if ($formatted.Length -gt 500) { $formatted.Substring(0, 500) + "..." } else { $formatted }
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to format JSON: $($_.Exception.Message)"
        }
    }
}

function Convert-ClipboardCase {
    <#
    .SYNOPSIS
    Convert clipboard text case
    #>
    param(
        [ValidateSet('upper', 'lower', 'title')]
        [string]$Case = 'upper'
    )
    
    try {
        $content = Get-Clipboard -Raw
        $result = switch ($Case) {
            'upper' { $content.ToUpper() }
            'lower' { $content.ToLower() }
            'title' { (Get-Culture).TextInfo.ToTitleCase($content.ToLower()) }
        }
        Set-Clipboard -Value $result
        return @{
            Success = $true
            Output = "Converted to $Case case and copied back"
            Preview = if ($result.Length -gt 200) { $result.Substring(0, 200) + "..." } else { $result }
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to convert case: $($_.Exception.Message)"
        }
    }
}

# ===== FILE CONTENT ANALYSIS =====

function Read-FileContent {
    <#
    .SYNOPSIS
    Read and analyze file content for AI
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [int]$MaxLines = 100,
        [int]$MaxLength = 5000
    )
    
    try {
        # Resolve path
        if (-not [System.IO.Path]::IsPathRooted($Path)) {
            $Path = Join-Path (Get-Location) $Path
        }
        
        if (-not (Test-Path $Path)) {
            return @{
                Success = $false
                Message = "File not found: $Path"
            }
        }
        
        $file = Get-Item $Path
        $extension = $file.Extension.ToLower()
        
        # Handle different file types
        switch ($extension) {
            '.json' {
                $content = Get-Content $Path -Raw
                try {
                    $json = $content | ConvertFrom-Json
                    $formatted = $json | ConvertTo-Json -Depth 5
                    if ($formatted.Length -gt $MaxLength) {
                        $formatted = $formatted.Substring(0, $MaxLength) + "`n... [truncated]"
                    }
                    return @{
                        Success = $true
                        Type = "JSON"
                        Content = $formatted
                        Path = $Path
                        Size = $file.Length
                    }
                }
                catch {
                    return @{
                        Success = $true
                        Type = "JSON (invalid)"
                        Content = $content.Substring(0, [Math]::Min($content.Length, $MaxLength))
                        Path = $Path
                    }
                }
            }
            '.csv' {
                $csv = Import-Csv $Path -ErrorAction Stop
                $rowCount = $csv.Count
                $columns = if ($csv.Count -gt 0) { $csv[0].PSObject.Properties.Name } else { @() }
                $preview = $csv | Select-Object -First 10 | Format-Table -AutoSize | Out-String
                return @{
                    Success = $true
                    Type = "CSV"
                    Columns = $columns -join ", "
                    RowCount = $rowCount
                    Preview = $preview
                    Path = $Path
                }
            }
            '.xml' {
                $content = Get-Content $Path -Raw
                if ($content.Length -gt $MaxLength) {
                    $content = $content.Substring(0, $MaxLength) + "`n... [truncated]"
                }
                return @{
                    Success = $true
                    Type = "XML"
                    Content = $content
                    Path = $Path
                    Size = $file.Length
                }
            }
            { $_ -in '.log', '.txt', '.md', '.ps1', '.py', '.js', '.ts', '.html', '.css' } {
                $lines = Get-Content $Path -TotalCount $MaxLines
                $content = $lines -join "`n"
                $totalLines = (Get-Content $Path | Measure-Object -Line).Lines
                if ($content.Length -gt $MaxLength) {
                    $content = $content.Substring(0, $MaxLength) + "`n... [truncated]"
                }
                return @{
                    Success = $true
                    Type = $extension.TrimStart('.')
                    Content = $content
                    Path = $Path
                    TotalLines = $totalLines
                    ShownLines = [Math]::Min($MaxLines, $totalLines)
                }
            }
            { $_ -in '.xlsx', '.xls' } {
                # Try to use ImportExcel module if available
                if (Get-Command Import-Excel -ErrorAction SilentlyContinue) {
                    $excel = Import-Excel $Path -ErrorAction Stop
                    $rowCount = $excel.Count
                    $columns = if ($excel.Count -gt 0) { $excel[0].PSObject.Properties.Name } else { @() }
                    $preview = $excel | Select-Object -First 10 | Format-Table -AutoSize | Out-String
                    return @{
                        Success = $true
                        Type = "Excel"
                        Columns = $columns -join ", "
                        RowCount = $rowCount
                        Preview = $preview
                        Path = $Path
                    }
                }
                else {
                    return @{
                        Success = $false
                        Message = "Excel reading requires ImportExcel module. Install with: Install-Module ImportExcel"
                        Path = $Path
                    }
                }
            }
            default {
                # Try to read as text
                try {
                    $content = Get-Content $Path -Raw -ErrorAction Stop
                    if ($content.Length -gt $MaxLength) {
                        $content = $content.Substring(0, $MaxLength) + "`n... [truncated]"
                    }
                    return @{
                        Success = $true
                        Type = "text"
                        Content = $content
                        Path = $Path
                        Size = $file.Length
                    }
                }
                catch {
                    return @{
                        Success = $false
                        Message = "Cannot read file as text: $($_.Exception.Message)"
                        Path = $Path
                    }
                }
            }
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to read file: $($_.Exception.Message)"
        }
    }
}

function Get-FileStats {
    <#
    .SYNOPSIS
    Get statistics about a file
    #>
    param([string]$Path)
    
    try {
        if (-not (Test-Path $Path)) {
            return @{ Success = $false; Message = "File not found: $Path" }
        }
        
        $file = Get-Item $Path
        $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue
        
        $stats = @{
            Success = $true
            Name = $file.Name
            Path = $file.FullName
            Size = "{0:N2} KB" -f ($file.Length / 1KB)
            Created = $file.CreationTime.ToString("yyyy-MM-dd HH:mm")
            Modified = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            Extension = $file.Extension
        }
        
        if ($content) {
            $stats.Lines = ($content -split "`n").Count
            $stats.Words = ($content -split '\s+').Count
            $stats.Characters = $content.Length
        }
        
        return $stats
    }
    catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

# ===== GIT INTEGRATION =====

function Get-GitStatus {
    <#
    .SYNOPSIS
    Get git repository status
    #>
    param([string]$Path = ".")
    
    try {
        Push-Location $Path
        
        # Check if in git repo
        $gitDir = git rev-parse --git-dir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            return @{
                Success = $false
                Message = "Not a git repository"
            }
        }
        
        $branch = git branch --show-current 2>&1
        $status = git status --porcelain 2>&1
        $remote = git remote -v 2>&1 | Select-Object -First 1
        $lastCommit = git log -1 --pretty=format:"%h - %s (%cr)" 2>&1
        
        $staged = @($status | Where-Object { $_ -match '^[MADRC]' }).Count
        $modified = @($status | Where-Object { $_ -match '^.[MD]' }).Count
        $untracked = @($status | Where-Object { $_ -match '^\?\?' }).Count
        
        Pop-Location
        
        return @{
            Success = $true
            Branch = $branch
            Staged = $staged
            Modified = $modified
            Untracked = $untracked
            LastCommit = $lastCommit
            Remote = if ($remote) { ($remote -split '\s+')[1] } else { "none" }
            Clean = ($staged -eq 0 -and $modified -eq 0 -and $untracked -eq 0)
            StatusLines = $status
        }
    }
    catch {
        if ((Get-Location).Path -ne $Path) { Pop-Location }
        return @{
            Success = $false
            Message = "Git error: $($_.Exception.Message)"
        }
    }
}

function Get-GitLog {
    <#
    .SYNOPSIS
    Get recent git commits
    #>
    param(
        [string]$Path = ".",
        [int]$Count = 10
    )
    
    try {
        Push-Location $Path
        
        $log = git log -$Count --pretty=format:"%h|%an|%ar|%s" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            return @{ Success = $false; Message = "Not a git repository or no commits" }
        }
        
        $commits = @()
        $log | ForEach-Object {
            $parts = $_ -split '\|'
            $commits += @{
                Hash = $parts[0]
                Author = $parts[1]
                Time = $parts[2]
                Message = $parts[3]
            }
        }
        
        Pop-Location
        
        return @{
            Success = $true
            Commits = $commits
            Count = $commits.Count
        }
    }
    catch {
        if ((Get-Location).Path -ne $Path) { Pop-Location }
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Invoke-GitCommit {
    <#
    .SYNOPSIS
    Stage all changes and commit
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Path = ".",
        [switch]$Push
    )
    
    try {
        Push-Location $Path
        
        # Stage all changes
        git add -A 2>&1 | Out-Null
        
        # Commit
        $result = git commit -m $Message 2>&1
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            return @{
                Success = $false
                Message = "Commit failed: $result"
            }
        }
        
        $output = @{
            Success = $true
            Message = "Committed: $Message"
            Output = $result -join "`n"
        }
        
        # Push if requested
        if ($Push) {
            $pushResult = git push 2>&1
            if ($LASTEXITCODE -eq 0) {
                $output.Pushed = $true
                $output.PushOutput = $pushResult -join "`n"
            }
            else {
                $output.Pushed = $false
                $output.PushError = $pushResult -join "`n"
            }
        }
        
        Pop-Location
        return $output
    }
    catch {
        if ((Get-Location).Path -ne $Path) { Pop-Location }
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Invoke-GitPull {
    <#
    .SYNOPSIS
    Pull latest changes from remote
    #>
    param([string]$Path = ".")
    
    try {
        Push-Location $Path
        $result = git pull 2>&1
        Pop-Location
        
        return @{
            Success = ($LASTEXITCODE -eq 0)
            Output = $result -join "`n"
        }
    }
    catch {
        if ((Get-Location).Path -ne $Path) { Pop-Location }
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

function Get-GitDiff {
    <#
    .SYNOPSIS
    Get diff of changes
    #>
    param(
        [string]$Path = ".",
        [switch]$Staged
    )
    
    try {
        Push-Location $Path
        
        $diff = if ($Staged) {
            git diff --staged 2>&1
        } else {
            git diff 2>&1
        }
        
        Pop-Location
        
        if (-not $diff) {
            return @{
                Success = $true
                Message = "No changes to show"
                Diff = ""
            }
        }
        
        # Truncate if too long
        $diffText = $diff -join "`n"
        if ($diffText.Length -gt 5000) {
            $diffText = $diffText.Substring(0, 5000) + "`n... [truncated]"
        }
        
        return @{
            Success = $true
            Diff = $diffText
        }
    }
    catch {
        if ((Get-Location).Path -ne $Path) { Pop-Location }
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

# ===== CALENDAR (OUTLOOK) =====

function Get-OutlookCalendar {
    <#
    .SYNOPSIS
    Get calendar events from Outlook
    #>
    param(
        [int]$Days = 7,
        [switch]$Today
    )
    
    try {
        $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
        $namespace = $outlook.GetNamespace("MAPI")
        $calendar = $namespace.GetDefaultFolder(9) # 9 = Calendar
        
        $startDate = (Get-Date).Date
        $endDate = if ($Today) { $startDate.AddDays(1) } else { $startDate.AddDays($Days) }
        
        $filter = "[Start] >= '$($startDate.ToString("g"))' AND [Start] < '$($endDate.ToString("g"))'"
        $events = $calendar.Items.Restrict($filter)
        $events.Sort("[Start]")
        
        $results = @()
        foreach ($event in $events) {
            $results += @{
                Subject = $event.Subject
                Start = $event.Start.ToString("yyyy-MM-dd HH:mm")
                End = $event.End.ToString("yyyy-MM-dd HH:mm")
                Location = $event.Location
                Duration = "$([math]::Round(($event.End - $event.Start).TotalMinutes)) min"
                IsRecurring = $event.IsRecurring
                Organizer = $event.Organizer
            }
        }
        
        # Release COM objects
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($events) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($calendar) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($namespace) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null
        
        return @{
            Success = $true
            Events = $results
            Count = $results.Count
            DateRange = "$($startDate.ToString('MMM dd')) - $($endDate.AddDays(-1).ToString('MMM dd'))"
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to access Outlook calendar: $($_.Exception.Message)"
            Hint = "Make sure Outlook is installed and configured"
        }
    }
}

function New-OutlookAppointment {
    <#
    .SYNOPSIS
    Create a new calendar appointment
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Subject,
        [Parameter(Mandatory=$true)]
        [datetime]$Start,
        [int]$DurationMinutes = 60,
        [string]$Location = "",
        [string]$Body = ""
    )
    
    try {
        $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
        $appointment = $outlook.CreateItem(1) # 1 = Appointment
        
        $appointment.Subject = $Subject
        $appointment.Start = $Start
        $appointment.Duration = $DurationMinutes
        $appointment.Location = $Location
        $appointment.Body = $Body
        $appointment.ReminderSet = $true
        $appointment.ReminderMinutesBeforeStart = 15
        
        $appointment.Save()
        
        $result = @{
            Success = $true
            Message = "Appointment created: $Subject"
            Start = $Start.ToString("yyyy-MM-dd HH:mm")
            Duration = "$DurationMinutes minutes"
        }
        
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($appointment) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null
        
        return $result
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create appointment: $($_.Exception.Message)"
        }
    }
}

# ===== EXPORT =====
$global:ProductivityToolsAvailable = $true
