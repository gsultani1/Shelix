# ===== IntentAliasSystem.ps1 =====
# Friendly task aliases that the AI can call via JSON intents
# Maps user-friendly intent names to concrete PowerShell commands

# ===== Intent Categories for Organization =====
$global:IntentCategories = @{
    'document' = @{
        Name = 'Document Operations'
        Description = 'Create and manage documents'
        Intents = @('create_docx', 'create_xlsx', 'create_report')
    }
    'file' = @{
        Name = 'File Operations'
        Description = 'Open, search, and manage files'
        Intents = @('open_file', 'search_file', 'open_recent')
    }
    'web' = @{
        Name = 'Web Operations'
        Description = 'Browse and search the web'
        Intents = @('browse_web', 'search_web', 'open_url')
    }
    'app' = @{
        Name = 'Application Launching'
        Description = 'Launch applications'
        Intents = @('open_word', 'open_excel', 'open_powerpoint', 'open_notepad', 'open_calculator', 'open_browser')
    }
    'workflow' = @{
        Name = 'Workflow/Composite'
        Description = 'Multi-step automated workflows'
        Intents = @('create_and_open_doc', 'research_topic', 'daily_standup')
    }
    'filesystem' = @{
        Name = 'File System Operations'
        Description = 'Create, rename, move, and manage files/folders'
        Intents = @('create_folder', 'rename_file', 'move_file', 'copy_file', 'delete_file', 'list_files')
    }
    'clipboard' = @{
        Name = 'Clipboard Operations'
        Description = 'Copy and paste text'
        Intents = @('copy_to_clipboard', 'paste_from_clipboard')
    }
}

# ===== Intent Metadata for Validation =====
$global:IntentMetadata = @{
    'create_docx' = @{
        Category = 'document'
        Description = 'Create a new Word document'
        Parameters = @(
            @{ Name = 'name'; Required = $true; Description = 'Document name (without extension)' }
        )
    }
    'create_xlsx' = @{
        Category = 'document'
        Description = 'Create a new Excel spreadsheet'
        Parameters = @(
            @{ Name = 'name'; Required = $true; Description = 'Spreadsheet name (without extension)' }
        )
    }
    'open_file' = @{
        Category = 'file'
        Description = 'Open a file with default application'
        Parameters = @(
            @{ Name = 'path'; Required = $true; Description = 'Full path to the file' }
        )
    }
    'search_file' = @{
        Category = 'file'
        Description = 'Search for files matching a term'
        Parameters = @(
            @{ Name = 'term'; Required = $true; Description = 'Search term' }
            @{ Name = 'path'; Required = $false; Description = 'Directory to search (default: Documents)' }
        )
    }
    'browse_web' = @{
        Category = 'web'
        Description = 'Open URL in default browser'
        Parameters = @(
            @{ Name = 'url'; Required = $true; Description = 'URL to open' }
        )
    }
    'open_url' = @{
        Category = 'web'
        Description = 'Open URL with browser selection and validation'
        Parameters = @(
            @{ Name = 'url'; Required = $true; Description = 'URL to open' }
            @{ Name = 'browser'; Required = $false; Description = 'Browser: chrome, firefox, edge, default' }
        )
    }
    'search_web' = @{
        Category = 'web'
        Description = 'Search Google for a query'
        Parameters = @(
            @{ Name = 'query'; Required = $true; Description = 'Search query' }
        )
    }
    'open_word' = @{ Category = 'app'; Description = 'Launch Microsoft Word'; Parameters = @() }
    'open_excel' = @{ Category = 'app'; Description = 'Launch Microsoft Excel'; Parameters = @() }
    'open_powerpoint' = @{ Category = 'app'; Description = 'Launch Microsoft PowerPoint'; Parameters = @() }
    'open_notepad' = @{ Category = 'app'; Description = 'Launch Notepad'; Parameters = @() }
    'open_calculator' = @{ Category = 'app'; Description = 'Launch Calculator'; Parameters = @() }
    'open_browser' = @{
        Category = 'app'
        Description = 'Launch a specific browser'
        Parameters = @(
            @{ Name = 'browser'; Required = $false; Description = 'Browser: chrome, firefox, edge (default: edge)' }
        )
    }
    'create_and_open_doc' = @{
        Category = 'workflow'
        Description = 'Create a document and open it in Word'
        Parameters = @(
            @{ Name = 'name'; Required = $true; Description = 'Document name' }
        )
    }
    'research_topic' = @{
        Category = 'workflow'
        Description = 'Search web and create notes document for a topic'
        Parameters = @(
            @{ Name = 'topic'; Required = $true; Description = 'Research topic' }
        )
    }
    'daily_standup' = @{
        Category = 'workflow'
        Description = 'Open common apps for daily standup'
        Parameters = @()
    }
    # File System Operations
    'create_folder' = @{
        Category = 'filesystem'
        Description = 'Create a new folder'
        Parameters = @(
            @{ Name = 'path'; Required = $true; Description = 'Folder path to create' }
        )
    }
    'rename_file' = @{
        Category = 'filesystem'
        Description = 'Rename a file or folder'
        Parameters = @(
            @{ Name = 'path'; Required = $true; Description = 'Current file path' }
            @{ Name = 'newname'; Required = $true; Description = 'New name' }
        )
    }
    'move_file' = @{
        Category = 'filesystem'
        Description = 'Move a file or folder'
        Parameters = @(
            @{ Name = 'source'; Required = $true; Description = 'Source path' }
            @{ Name = 'destination'; Required = $true; Description = 'Destination path' }
        )
    }
    'copy_file' = @{
        Category = 'filesystem'
        Description = 'Copy a file or folder'
        Parameters = @(
            @{ Name = 'source'; Required = $true; Description = 'Source path' }
            @{ Name = 'destination'; Required = $true; Description = 'Destination path' }
        )
    }
    'delete_file' = @{
        Category = 'filesystem'
        Description = 'Delete a file (with confirmation)'
        Parameters = @(
            @{ Name = 'path'; Required = $true; Description = 'File path to delete' }
        )
    }
    'list_files' = @{
        Category = 'filesystem'
        Description = 'List files in a directory'
        Parameters = @(
            @{ Name = 'path'; Required = $false; Description = 'Directory path (default: current)' }
        )
    }
    # Clipboard
    'copy_to_clipboard' = @{
        Category = 'clipboard'
        Description = 'Copy text to clipboard'
        Parameters = @(
            @{ Name = 'text'; Required = $true; Description = 'Text to copy' }
        )
    }
    'paste_from_clipboard' = @{
        Category = 'clipboard'
        Description = 'Get text from clipboard'
        Parameters = @()
    }
}

$global:IntentAliases = @{
    # ===== Document Operations =====
    "create_docx" = { 
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: name parameter required"; Error = $true }
        }
        $safeName = $name -replace '[<>:"/\\|?*]', '_'
        $path = "$env:USERPROFILE\Documents\$safeName.docx"
        New-Item $path -ItemType File -Force | Out-Null
        
        # Track for undo capability
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            Add-FileOperation -Operation 'Create' -Path $path -ExecutionId 'intent'
        }
        
        # Open the document in Word
        Start-Process $path -ErrorAction SilentlyContinue
        
        @{ Success = $true; Output = "Created and opened: $path"; Path = $path; Undoable = $true }
    }
    
    "create_xlsx" = { 
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: name parameter required"; Error = $true }
        }
        $safeName = $name -replace '[<>:"/\\|?*]', '_'
        $path = "$env:USERPROFILE\Documents\$safeName.xlsx"
        New-Item $path -ItemType File -Force | Out-Null
        
        # Track for undo capability
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            Add-FileOperation -Operation 'Create' -Path $path -ExecutionId 'intent'
        }
        
        @{ Success = $true; Output = "Created: $path"; Path = $path; Undoable = $true }
    }
    
    # ===== File Operations =====
    "open_file" = { 
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        if (Test-Path $path) {
            Start-Process $path
            @{ Success = $true; Output = "Opened: $path" }
        } else {
            @{ Success = $false; Output = "File not found: $path"; Error = $true }
        }
    }
    
    "search_file" = { 
        param($term, $searchPath)
        if (-not $term) {
            return @{ Success = $false; Output = "Error: term parameter required"; Error = $true }
        }
        if (-not $searchPath) { $searchPath = "$env:USERPROFILE\Documents" }
        $results = Get-ChildItem -Path $searchPath -Recurse -Filter "*$term*" -ErrorAction SilentlyContinue | Select-Object -First 20
        @{ 
            Success = $true
            Output = "Found $($results.Count) items"
            Results = $results | Select-Object -ExpandProperty FullName
        }
    }
    
    "open_recent" = {
        param($count)
        if (-not $count) { $count = 5 }
        $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"
        $recent = Get-ChildItem $recentPath -Filter "*.lnk" -ErrorAction SilentlyContinue | 
            Sort-Object LastWriteTime -Descending | 
            Select-Object -First $count
        @{
            Success = $true
            Output = "Recent $count files"
            Results = $recent | ForEach-Object { $_.Name -replace '\.lnk$', '' }
        }
    }
    
    # ===== Web Operations =====
    "browse_web" = { 
        param($url)
        if (-not $url) {
            return @{ Success = $false; Output = "Error: url parameter required"; Error = $true }
        }
        if ($url -notmatch '^https?://') {
            $url = "https://$url"
        }
        Start-Process $url
        @{ Success = $true; Output = "Opened: $url" }
    }
    
    "open_url" = {
        param($url, $browser)
        # Validate URL
        if (-not $url) {
            return @{ Success = $false; Output = "Error: url parameter required"; Error = $true }
        }
        
        # Auto-add protocol if missing
        if ($url -notmatch '^https?://') {
            $url = "https://$url"
        }
        
        # Validate URL format
        try {
            $uri = [System.Uri]::new($url)
            if ($uri.Scheme -notin @('http', 'https')) {
                return @{ Success = $false; Output = "Error: Invalid URL scheme. Use http or https."; Error = $true }
            }
        } catch {
            return @{ Success = $false; Output = "Error: Invalid URL format"; Error = $true }
        }
        
        # Browser selection
        if (-not $browser) { $browser = "default" }
        $browserPaths = @{
            'chrome' = 'chrome'
            'firefox' = 'firefox'
            'edge' = 'msedge'
            'default' = $null
        }
        
        $browserExe = $browserPaths[$browser.ToLower()]
        if ($null -eq $browserExe -and $browser -ne 'default') {
            return @{ Success = $false; Output = "Error: Unknown browser '$browser'. Use: chrome, firefox, edge, default"; Error = $true }
        }
        
        if ($browser -eq 'default' -or -not $browserExe) {
            Start-Process $url
        } else {
            Start-Process $browserExe -ArgumentList $url
        }
        
        @{ Success = $true; Output = "Opened $url in $browser"; Browser = $browser; URL = $url }
    }
    
    "search_web" = { 
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: query parameter required"; Error = $true }
        }
        $encodedQuery = [System.Web.HttpUtility]::UrlEncode($query)
        $url = "https://www.google.com/search?q=$encodedQuery"
        Start-Process $url
        @{ Success = $true; Output = "Opened Google search for: $query"; URL = $url }
    }
    
    "web_search" = {
        # Search and return results (doesn't open browser)
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: query parameter required"; Error = $true }
        }
        $result = Invoke-WebSearch -Query $query
        if ($result.Success) {
            $output = Format-SearchResultsForAI $result
            @{ Success = $true; Output = $output; ResultCount = $result.ResultCount }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "wikipedia" = {
        # Search Wikipedia and return summary
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: query parameter required"; Error = $true }
        }
        $result = Search-Wikipedia -Query $query
        if ($result.Success) {
            $output = Format-SearchResultsForAI $result
            @{ Success = $true; Output = $output; ResultCount = $result.ResultCount }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "fetch_url" = {
        # Fetch and return content from a URL
        param($url)
        if (-not $url) {
            return @{ Success = $false; Output = "Error: url parameter required"; Error = $true }
        }
        $result = Get-WebPageContent -Url $url -MaxLength 3000
        if ($result.Success) {
            @{ Success = $true; Output = "Content from $url :`n`n$($result.Content)"; Length = $result.Length }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    # ===== CLIPBOARD OPERATIONS =====
    "clipboard_read" = {
        $result = Get-ClipboardContent
        if ($result.Success) {
            $preview = if ($result.Content.Length -gt 1000) { $result.Content.Substring(0, 1000) + "..." } else { $result.Content }
            @{ Success = $true; Output = "Clipboard ($($result.Type), $($result.Length) chars, $($result.Lines) lines):`n$preview" }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "clipboard_write" = {
        param($text)
        if (-not $text) {
            return @{ Success = $false; Output = "Error: text parameter required"; Error = $true }
        }
        $result = Set-ClipboardContent -Content $text
        @{ Success = $result.Success; Output = $result.Message }
    }
    
    "clipboard_format_json" = {
        $result = Convert-ClipboardJson
        if ($result.Success) {
            @{ Success = $true; Output = "$($result.Output)`n`nPreview:`n$($result.Preview)" }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "clipboard_case" = {
        param($case)
        if (-not $case) { $case = "upper" }
        $result = Convert-ClipboardCase -Case $case
        if ($result.Success) {
            @{ Success = $true; Output = "$($result.Output)`n`nPreview: $($result.Preview)" }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    # ===== FILE CONTENT ANALYSIS =====
    "read_file" = {
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        $result = Read-FileContent -Path $path
        if ($result.Success) {
            $output = "File: $($result.Path)`nType: $($result.Type)"
            if ($result.TotalLines) { $output += "`nLines: $($result.ShownLines)/$($result.TotalLines)" }
            if ($result.RowCount) { $output += "`nRows: $($result.RowCount)`nColumns: $($result.Columns)" }
            if ($result.Content) { $output += "`n`n$($result.Content)" }
            if ($result.Preview) { $output += "`n`n$($result.Preview)" }
            @{ Success = $true; Output = $output }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "file_stats" = {
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        $result = Get-FileStats -Path $path
        if ($result.Success) {
            $output = "File: $($result.Name)`nPath: $($result.Path)`nSize: $($result.Size)`nCreated: $($result.Created)`nModified: $($result.Modified)"
            if ($result.Lines) { $output += "`nLines: $($result.Lines)`nWords: $($result.Words)`nCharacters: $($result.Characters)" }
            @{ Success = $true; Output = $output }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    # ===== GIT INTEGRATION =====
    "git_status" = {
        param($path)
        if (-not $path) { $path = "." }
        $result = Get-GitStatus -Path $path
        if ($result.Success) {
            $status = if ($result.Clean) { "Clean" } else { "Changes pending" }
            $output = "Branch: $($result.Branch)`nStatus: $status`nStaged: $($result.Staged)`nModified: $($result.Modified)`nUntracked: $($result.Untracked)`nLast commit: $($result.LastCommit)`nRemote: $($result.Remote)"
            if ($result.StatusLines -and $result.StatusLines.Count -gt 0) {
                $output += "`n`nChanged files:`n$($result.StatusLines -join "`n")"
            }
            @{ Success = $true; Output = $output }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_log" = {
        param($count)
        if (-not $count) { $count = 10 }
        $result = Get-GitLog -Count $count
        if ($result.Success) {
            $output = "Recent commits ($($result.Count)):`n"
            foreach ($c in $result.Commits) {
                $output += "`n$($c.Hash) - $($c.Message) ($($c.Author), $($c.Time))"
            }
            @{ Success = $true; Output = $output }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_commit" = {
        param($message)
        if (-not $message) {
            return @{ Success = $false; Output = "Error: message parameter required"; Error = $true }
        }
        $result = Invoke-GitCommit -Message $message
        if ($result.Success) {
            @{ Success = $true; Output = $result.Message }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_push" = {
        param($message)
        if (-not $message) {
            return @{ Success = $false; Output = "Error: message parameter required for commit"; Error = $true }
        }
        $result = Invoke-GitCommit -Message $message -Push
        if ($result.Success) {
            $output = $result.Message
            if ($result.Pushed) { $output += "`nPushed to remote successfully" }
            elseif ($result.PushError) { $output += "`nPush failed: $($result.PushError)" }
            @{ Success = $true; Output = $output }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_pull" = {
        $result = Invoke-GitPull
        @{ Success = $result.Success; Output = $result.Output }
    }
    
    "git_diff" = {
        param($staged)
        $isStaged = $staged -eq "staged" -or $staged -eq "true"
        $result = Get-GitDiff -Staged:$isStaged
        if ($result.Success) {
            if ($result.Diff) {
                @{ Success = $true; Output = "Diff:`n$($result.Diff)" }
            } else {
                @{ Success = $true; Output = $result.Message }
            }
        } else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    # ===== MCP (Model Context Protocol) =====
    "mcp_servers" = {
        $servers = Get-MCPServers
        if ($servers) {
            $output = "Registered MCP Servers:`n"
            foreach ($s in $servers) {
                $status = if ($s.Connected) { "[Connected]" } else { "[Not Connected]" }
                $output += "`n$($s.Name) $status - $($s.Description)"
            }
            @{ Success = $true; Output = $output }
        } else {
            @{ Success = $true; Output = "No MCP servers registered. Run: mcp-register" }
        }
    }
    
    "mcp_connect" = {
        param($server)
        if (-not $server) {
            return @{ Success = $false; Output = "Error: server name required"; Error = $true }
        }
        $result = Connect-MCPServer -Name $server
        if ($result) {
            $toolList = ($result.Tools | ForEach-Object { $_.name }) -join ", "
            @{ Success = $true; Output = "Connected to $server. Tools: $toolList" }
        } else {
            @{ Success = $false; Output = "Failed to connect to $server"; Error = $true }
        }
    }
    
    "mcp_call" = {
        param($server, $tool, $toolArgs)
        if (-not $server -or -not $tool) {
            return @{ Success = $false; Output = "Error: server and tool parameters required"; Error = $true }
        }
        $arguments = @{}
        if ($toolArgs) {
            try { $arguments = $toolArgs | ConvertFrom-Json -AsHashtable } catch { }
        }
        $result = Invoke-MCPTool -ServerName $server -ToolName $tool -Arguments $arguments
        if ($result.Success) {
            @{ Success = $true; Output = $result.Output }
        } else {
            @{ Success = $false; Output = $result.Error; Error = $true }
        }
    }
    
    "mcp_tools" = {
        param($server)
        if (-not $server) {
            return @{ Success = $false; Output = "Error: server name required"; Error = $true }
        }
        if (-not $global:MCPConnections.ContainsKey($server)) {
            return @{ Success = $false; Output = "Not connected to $server. Use mcp_connect first."; Error = $true }
        }
        $conn = $global:MCPConnections[$server]
        $output = "Tools on $server :`n"
        foreach ($tool in $conn.Tools) {
            $output += "`n- $($tool.name): $($tool.description)"
        }
        @{ Success = $true; Output = $output }
    }
    
    # ===== CALENDAR (OUTLOOK) =====
    "calendar_today" = {
        $result = Get-OutlookCalendar -Today
        if ($result.Success) {
            if ($result.Count -eq 0) {
                @{ Success = $true; Output = "No events scheduled for today" }
            } else {
                $output = "Today's events ($($result.Count)):`n"
                foreach ($e in $result.Events) {
                    $output += "`n- $($e.Start.Substring(11)) - $($e.Subject)"
                    if ($e.Location) { $output += " @ $($e.Location)" }
                    $output += " ($($e.Duration))"
                }
                @{ Success = $true; Output = $output }
            }
        } else {
            @{ Success = $false; Output = "$($result.Message). $($result.Hint)"; Error = $true }
        }
    }
    
    "calendar_week" = {
        $result = Get-OutlookCalendar -Days 7
        if ($result.Success) {
            if ($result.Count -eq 0) {
                @{ Success = $true; Output = "No events scheduled for the next 7 days" }
            } else {
                $output = "Events for $($result.DateRange) ($($result.Count) total):`n"
                $currentDate = ""
                foreach ($e in $result.Events) {
                    $eventDate = $e.Start.Substring(0, 10)
                    if ($eventDate -ne $currentDate) {
                        $currentDate = $eventDate
                        $output += "`n[$currentDate]"
                    }
                    $output += "`n  $($e.Start.Substring(11)) - $($e.Subject)"
                    if ($e.Location) { $output += " @ $($e.Location)" }
                }
                @{ Success = $true; Output = $output }
            }
        } else {
            @{ Success = $false; Output = "$($result.Message). $($result.Hint)"; Error = $true }
        }
    }
    
    "calendar_create" = {
        param($subject, $start, $duration)
        if (-not $subject) {
            return @{ Success = $false; Output = "Error: subject parameter required"; Error = $true }
        }
        if (-not $start) {
            return @{ Success = $false; Output = "Error: start parameter required (e.g., '2024-12-25 14:00')"; Error = $true }
        }
        try {
            $startDate = [datetime]::Parse($start)
            $durationMins = if ($duration) { [int]$duration } else { 60 }
            $result = New-OutlookAppointment -Subject $subject -Start $startDate -DurationMinutes $durationMins
            if ($result.Success) {
                @{ Success = $true; Output = "$($result.Message) at $($result.Start) for $($result.Duration)" }
            } else {
                @{ Success = $false; Output = $result.Message; Error = $true }
            }
        }
        catch {
            @{ Success = $false; Output = "Invalid date format. Use: YYYY-MM-DD HH:MM"; Error = $true }
        }
    }
    
    # ===== Application Launching =====
    "open_word" = { 
        Start-Process winword -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched Microsoft Word" }
    }
    
    "open_excel" = { 
        Start-Process excel -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched Microsoft Excel" }
    }
    
    "open_powerpoint" = { 
        Start-Process powerpnt -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched Microsoft PowerPoint" }
    }
    
    "open_notepad" = { 
        Start-Process notepad
        @{ Success = $true; Output = "Launched Notepad" }
    }
    
    "open_calculator" = { 
        Start-Process calc
        @{ Success = $true; Output = "Launched Calculator" }
    }
    
    "open_browser" = {
        param($browser)
        if (-not $browser) { $browser = "edge" }
        $browsers = @{
            'chrome' = 'chrome'
            'firefox' = 'firefox'
            'edge' = 'msedge'
        }
        $exe = $browsers[$browser.ToLower()]
        if (-not $exe) {
            return @{ Success = $false; Output = "Unknown browser: $browser. Use: chrome, firefox, edge"; Error = $true }
        }
        Start-Process $exe -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched $browser" }
    }
    
    # ===== Workflow/Composite Intents =====
    "create_and_open_doc" = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: name parameter required"; Error = $true }
        }
        
        # Chain: create_docx -> open_file
        $createResult = & $global:IntentAliases["create_docx"] $name
        if (-not $createResult.Success) {
            return $createResult
        }
        
        Start-Sleep -Milliseconds 500
        $openResult = & $global:IntentAliases["open_file"] $createResult.Path
        
        @{
            Success = $openResult.Success
            Output = "Created and opened: $($createResult.Path)"
            Path = $createResult.Path
            Steps = @($createResult, $openResult)
        }
    }
    
    "research_topic" = {
        param($topic)
        if (-not $topic) {
            return @{ Success = $false; Output = "Error: topic parameter required"; Error = $true }
        }
        
        # Chain: search_web -> create_docx (for notes)
        $searchResult = & $global:IntentAliases["search_web"] $topic
        
        Start-Sleep -Milliseconds 300
        $safeTopic = $topic -replace '[<>:"/\\|?*]', '_'
        $notesName = "Research_${safeTopic}_$(Get-Date -Format 'yyyyMMdd')"
        $createResult = & $global:IntentAliases["create_docx"] $notesName
        
        @{
            Success = $true
            Output = "Researching '$topic' - opened search and created notes: $($createResult.Path)"
            SearchURL = $searchResult.URL
            NotesPath = $createResult.Path
            Steps = @($searchResult, $createResult)
        }
    }
    
    "daily_standup" = {
        # Chain: open multiple apps for daily standup
        $results = @()
        
        $results += & $global:IntentAliases["open_browser"] "edge"
        Start-Sleep -Milliseconds 200
        $results += & $global:IntentAliases["open_word"]
        Start-Sleep -Milliseconds 200
        $results += & $global:IntentAliases["open_excel"]
        
        @{
            Success = $true
            Output = "Daily standup setup complete - opened browser, Word, and Excel"
            Steps = $results
        }
    }
    
    # ===== File System Operations =====
    "create_folder" = {
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        
        if (Test-Path $path) {
            return @{ Success = $false; Output = "Folder already exists: $path"; Error = $true }
        }
        
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            Add-FileOperation -Operation 'Create' -Path $path -ExecutionId 'intent'
        }
        
        @{ Success = $true; Output = "Created folder: $path"; Path = $path; Undoable = $true }
    }
    
    "rename_file" = {
        param($path, $newname)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        if (-not $newname) {
            return @{ Success = $false; Output = "Error: newname parameter required"; Error = $true }
        }
        
        if (-not (Test-Path $path)) {
            return @{ Success = $false; Output = "File not found: $path"; Error = $true }
        }
        
        $newPath = Join-Path (Split-Path $path -Parent) $newname
        Rename-Item -Path $path -NewName $newname -Force
        
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            Add-FileOperation -Operation 'Move' -Path $newPath -OriginalPath $path -ExecutionId 'intent'
        }
        
        @{ Success = $true; Output = "Renamed: $path -> $newname"; OldPath = $path; NewPath = $newPath; Undoable = $true }
    }
    
    "move_file" = {
        param($source, $destination)
        if (-not $source) {
            return @{ Success = $false; Output = "Error: source parameter required"; Error = $true }
        }
        if (-not $destination) {
            return @{ Success = $false; Output = "Error: destination parameter required"; Error = $true }
        }
        
        if (-not (Test-Path $source)) {
            return @{ Success = $false; Output = "Source not found: $source"; Error = $true }
        }
        
        Move-Item -Path $source -Destination $destination -Force
        
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            Add-FileOperation -Operation 'Move' -Path $destination -OriginalPath $source -ExecutionId 'intent'
        }
        
        @{ Success = $true; Output = "Moved: $source -> $destination"; Source = $source; Destination = $destination; Undoable = $true }
    }
    
    "copy_file" = {
        param($source, $destination)
        if (-not $source) {
            return @{ Success = $false; Output = "Error: source parameter required"; Error = $true }
        }
        if (-not $destination) {
            return @{ Success = $false; Output = "Error: destination parameter required"; Error = $true }
        }
        
        if (-not (Test-Path $source)) {
            return @{ Success = $false; Output = "Source not found: $source"; Error = $true }
        }
        
        Copy-Item -Path $source -Destination $destination -Force -Recurse
        
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            Add-FileOperation -Operation 'Copy' -Path $destination -OriginalPath $source -ExecutionId 'intent'
        }
        
        @{ Success = $true; Output = "Copied: $source -> $destination"; Source = $source; Destination = $destination; Undoable = $true }
    }
    
    "delete_file" = {
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        
        if (-not (Test-Path $path)) {
            return @{ Success = $false; Output = "File not found: $path"; Error = $true }
        }
        
        # Create backup before deletion
        $backupPath = $null
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            $backupDir = "$env:TEMP\IntentBackups"
            if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            $backupPath = Join-Path $backupDir "$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Split-Path $path -Leaf)"
            Copy-Item -Path $path -Destination $backupPath -Force -Recurse
        }
        
        Remove-Item -Path $path -Force -Recurse
        
        if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
            Add-FileOperation -Operation 'Delete' -Path $path -BackupPath $backupPath -ExecutionId 'intent'
        }
        
        @{ Success = $true; Output = "Deleted: $path"; Path = $path; BackupPath = $backupPath; Undoable = ($null -ne $backupPath) }
    }
    
    "list_files" = {
        param($path)
        if (-not $path) { $path = Get-Location }
        
        if (-not (Test-Path $path)) {
            return @{ Success = $false; Output = "Path not found: $path"; Error = $true }
        }
        
        $items = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        $output = $items | ForEach-Object {
            $type = if ($_.PSIsContainer) { "[DIR]" } else { "[FILE]" }
            "$type $($_.Name)"
        }
        
        @{ 
            Success = $true
            Output = "Listed $($items.Count) items in $path"
            Items = $items | Select-Object Name, Length, LastWriteTime, PSIsContainer
            FormattedList = $output -join "`n"
        }
    }
    
    # ===== Clipboard Operations =====
    "copy_to_clipboard" = {
        param($text)
        if (-not $text) {
            return @{ Success = $false; Output = "Error: text parameter required"; Error = $true }
        }
        
        Set-Clipboard -Value $text
        $preview = if ($text.Length -gt 50) { $text.Substring(0, 50) + "..." } else { $text }
        @{ Success = $true; Output = "Copied to clipboard: $preview"; Length = $text.Length }
    }
    
    "paste_from_clipboard" = {
        $text = Get-Clipboard -Raw
        if (-not $text) {
            return @{ Success = $true; Output = "Clipboard is empty"; Text = "" }
        }
        
        $preview = if ($text.Length -gt 100) { $text.Substring(0, 100) + "..." } else { $text }
        @{ Success = $true; Output = "Clipboard contents: $preview"; Text = $text; Length = $text.Length }
    }
}

function Invoke-IntentAction {
    <#
    .SYNOPSIS
    Router function for intent-based actions with safety validation and logging
    
    .DESCRIPTION
    Accepts intent payloads (JSON or hashtable), validates against $IntentAliases,
    and executes with confirmation and logging. Supports both positional params
    (param, param2) and named parameters from JSON payload.
    
    .PARAMETER Intent
    The intent name (e.g., "open_file", "create_docx")
    
    .PARAMETER Param
    First positional parameter (legacy support)
    
    .PARAMETER Param2
    Second positional parameter (legacy support)
    
    .PARAMETER Payload
    Full JSON payload hashtable with named parameters
    
    .PARAMETER AutoConfirm
    Skip confirmation and execute immediately
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Intent,
        [string]$Param = "",
        [string]$Param2 = "",
        [hashtable]$Payload = @{},
        [switch]$AutoConfirm
    )
    
    $intentId = [guid]::NewGuid().ToString().Substring(0,8)
    
    try {
        # Validate intent exists
        if (-not $global:IntentAliases.ContainsKey($Intent)) {
            Write-Host "[Intent-$intentId] REJECTED: Intent '$Intent' not found" -ForegroundColor Red
            Write-Host "Available intents: $($global:IntentAliases.Keys -join ', ')" -ForegroundColor Yellow
            return @{
                Success = $false
                Output = "Intent '$Intent' not found"
                Error = $true
                IntentId = $intentId
            }
        }
        
        Write-Host "[Intent-$intentId] Validating intent: $Intent" -ForegroundColor DarkCyan
        
        # Build parameter list - prefer named params from Payload, fall back to positional
        $namedParams = @{}
        $positionalParams = @()
        
        # Check if we have a full payload with named parameters
        if ($Payload.Count -gt 0) {
            # Extract all non-intent keys as named parameters
            foreach ($key in $Payload.Keys) {
                if ($key -notin @('intent', 'action')) {
                    $namedParams[$key] = $Payload[$key]
                }
            }
        }
        
        # Map common JSON keys to expected parameter names
        if ($namedParams.ContainsKey('param') -and -not $Param) {
            $Param = $namedParams['param']
        }
        if ($namedParams.ContainsKey('param2') -and -not $Param2) {
            $Param2 = $namedParams['param2']
        }
        
        # Build positional params for legacy scriptblocks
        if ($Param) { $positionalParams += $Param }
        if ($Param2) { $positionalParams += $Param2 }
        
        # Show confirmation for user awareness
        if (-not $AutoConfirm) {
            Write-Host "`nIntent Action: $Intent" -ForegroundColor Yellow
            if ($namedParams.Count -gt 0) {
                foreach ($key in $namedParams.Keys) {
                    Write-Host "  $key : $($namedParams[$key])" -ForegroundColor Gray
                }
            } else {
                if ($Param) { Write-Host "  Parameter 1: $Param" -ForegroundColor Gray }
                if ($Param2) { Write-Host "  Parameter 2: $Param2" -ForegroundColor Gray }
            }
            
            $response = Read-Host "Proceed? (y/n)"
            if ($response -notin @('y', 'yes')) {
                Write-Host "[Intent-$intentId] Cancelled by user" -ForegroundColor Yellow
                return @{
                    Success = $false
                    Output = "Intent execution cancelled by user"
                    Error = $false
                    IntentId = $intentId
                }
            }
        }
        
        # Execute the intent action
        Write-Host "[Intent-$intentId] Executing: $Intent" -ForegroundColor Cyan
        $startTime = Get-Date
        
        $scriptBlock = $global:IntentAliases[$Intent]
        
        # Try named parameters first if metadata exists, otherwise use positional
        $result = $null
        $meta = $global:IntentMetadata[$Intent]
        
        if ($meta -and $meta.Parameters.Count -gt 0 -and $namedParams.Count -gt 0) {
            # Build ordered positional array from named params based on metadata order
            $orderedParams = @()
            foreach ($paramDef in $meta.Parameters) {
                $paramName = $paramDef.Name
                if ($namedParams.ContainsKey($paramName)) {
                    $orderedParams += $namedParams[$paramName]
                } elseif ($paramName -eq 'url' -and $namedParams.ContainsKey('param')) {
                    $orderedParams += $namedParams['param']
                } elseif ($paramName -eq 'browser' -and $namedParams.ContainsKey('param2')) {
                    $orderedParams += $namedParams['param2']
                } elseif (-not $paramDef.Required) {
                    # Optional param not provided, skip
                } else {
                    # Required param missing, use positional fallback
                    break
                }
            }
            if ($orderedParams.Count -gt 0) {
                $result = & $scriptBlock @orderedParams
            }
        }
        
        # Fallback to positional if named didn't work
        if ($null -eq $result) {
            $result = & $scriptBlock @positionalParams
        }
        
        $executionTime = ((Get-Date) - $startTime).TotalSeconds
        
        Write-Host "[Intent-$intentId] Completed ($([math]::Round($executionTime, 2))s)" -ForegroundColor Green
        
        return @{
            Success = $true
            Output = $result.Output
            IntentId = $intentId
            ExecutionTime = $executionTime
            Result = $result
        }
        
    } catch {
        Write-Host "[Intent-$intentId] Error: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success = $false
            Output = "Error: $($_.Exception.Message)"
            Error = $true
            IntentId = $intentId
        }
    }
}

function Get-IntentAliases {
    <#
    .SYNOPSIS
    List all available intent aliases
    #>
    Write-Host "`n===== Available Intent Aliases =====" -ForegroundColor Cyan
    $global:IntentAliases.Keys | Sort-Object | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Green
    }
    Write-Host ""
}

function Test-Intent {
    <#
    .SYNOPSIS
    Test an intent manually
    
    .PARAMETER JsonPayload
    JSON payload like {"intent":"open_file","param":"C:\path\file.txt"}
    #>
    param([Parameter(Mandatory=$true)][string]$JsonPayload)
    
    try {
        $payload = $JsonPayload | ConvertFrom-Json
        Invoke-IntentAction -Intent $payload.intent -Param $payload.param -Param2 $payload.param2 -AutoConfirm
    } catch {
        Write-Host "Invalid JSON payload: $_" -ForegroundColor Red
    }
}

function Get-IntentDescription {
    <#
    .SYNOPSIS
    Display detailed information about a specific intent
    
    .PARAMETER Name
    Intent name to describe
    #>
    param([Parameter(Mandatory=$true)][string]$Name)
    
    if ($global:IntentAliases.ContainsKey($Name)) {
        Write-Host "`nIntent: $Name" -ForegroundColor Cyan
        Write-Host "Status: Available" -ForegroundColor Green
        Write-Host "Type: Script Block" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "Intent '$Name' not found" -ForegroundColor Red
        Write-Host "Available intents: $($global:IntentAliases.Keys -join ', ')" -ForegroundColor Yellow
    }
}

function Show-IntentHelp {
    <#
    .SYNOPSIS
    Display help for all intents with usage examples, organized by category
    
    .PARAMETER Category
    Optional: Show only intents in a specific category
    #>
    param([string]$Category = "")
    
    Write-Host "`n===== Intent Alias System Help ====="  -ForegroundColor Cyan
    
    # Filter categories if specified
    $categoriesToShow = if ($Category) {
        if ($global:IntentCategories.ContainsKey($Category)) {
            @{ $Category = $global:IntentCategories[$Category] }
        } else {
            Write-Host "Unknown category: $Category" -ForegroundColor Red
            Write-Host "Available categories: $($global:IntentCategories.Keys -join ', ')" -ForegroundColor Yellow
            return
        }
    } else {
        $global:IntentCategories
    }
    
    foreach ($catKey in $categoriesToShow.Keys | Sort-Object) {
        $cat = $categoriesToShow[$catKey]
        Write-Host "`n$($cat.Name) [$catKey]" -ForegroundColor Green
        Write-Host "  $($cat.Description)" -ForegroundColor DarkGray
        
        foreach ($intentName in $cat.Intents) {
            if ($global:IntentMetadata.ContainsKey($intentName)) {
                $meta = $global:IntentMetadata[$intentName]
                $paramStr = ""
                if ($meta.Parameters.Count -gt 0) {
                    $paramNames = $meta.Parameters | ForEach-Object {
                        if ($_.Required) { "[$($_.Name)]" } else { "[$($_.Name)?]" }
                    }
                    $paramStr = " " + ($paramNames -join " ")
                }
                $intentDisplay = "  $intentName$paramStr"
                Write-Host $intentDisplay.PadRight(35) -NoNewline -ForegroundColor White
                Write-Host "- $($meta.Description)" -ForegroundColor Gray
            } elseif ($global:IntentAliases.ContainsKey($intentName)) {
                Write-Host "  $intentName" -ForegroundColor White
            }
        }
    }
    
    Write-Host "`n===== Usage Examples =====" -ForegroundColor Yellow
    Write-Host "  Manual test:  intent '{\"intent\":\"open_file\",\"param\":\"C:\\report.docx\"}'"
    Write-Host "  With browser: intent '{\"intent\":\"open_url\",\"param\":\"google.com\",\"param2\":\"chrome\"}'"
    Write-Host "  Workflow:     intent '{\"intent\":\"research_topic\",\"param\":\"PowerShell automation\"}'"
    Write-Host "  AI JSON:      {\"intent\":\"browse_web\",\"param\":\"https://google.com\"}"
    
    Write-Host "`n===== Categories =====" -ForegroundColor Yellow
    Write-Host "  View specific: intent-help -Category workflow"
    Write-Host "  Available: $($global:IntentCategories.Keys -join ', ')" -ForegroundColor Gray
    
    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Get-IntentInfo {
    <#
    .SYNOPSIS
    Get detailed information about a specific intent including parameters
    #>
    param([Parameter(Mandatory=$true)][string]$Name)
    
    if (-not $global:IntentAliases.ContainsKey($Name)) {
        Write-Host "Intent '$Name' not found" -ForegroundColor Red
        Write-Host "Available intents: $($global:IntentAliases.Keys -join ', ')" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n===== Intent: $Name =====" -ForegroundColor Cyan
    
    if ($global:IntentMetadata.ContainsKey($Name)) {
        $meta = $global:IntentMetadata[$Name]
        Write-Host "Category: $($meta.Category)" -ForegroundColor Gray
        Write-Host "Description: $($meta.Description)" -ForegroundColor White
        
        if ($meta.Parameters.Count -gt 0) {
            Write-Host "`nParameters:" -ForegroundColor Yellow
            foreach ($param in $meta.Parameters) {
                $reqStr = if ($param.Required) { "(required)" } else { "(optional)" }
                Write-Host "  $($param.Name) $reqStr" -ForegroundColor Green
                Write-Host "    $($param.Description)" -ForegroundColor Gray
            }
        } else {
            Write-Host "`nParameters: None" -ForegroundColor Gray
        }
        
        # Check if it's a workflow
        if ($meta.Category -eq 'workflow') {
            Write-Host "`nType: Composite/Workflow Intent" -ForegroundColor Magenta
            Write-Host "  This intent chains multiple actions together." -ForegroundColor Gray
        }
    } else {
        Write-Host "Status: Available (no metadata)" -ForegroundColor Yellow
    }
    
    Write-Host "`nExample:" -ForegroundColor Yellow
    if ($global:IntentMetadata.ContainsKey($Name) -and $global:IntentMetadata[$Name].Parameters.Count -gt 0) {
        $exampleParams = $global:IntentMetadata[$Name].Parameters | ForEach-Object { "`"$($_.Name)`":`"example`"" }
        Write-Host "  {`"intent`":`"$Name`",$($exampleParams -join ',')}" -ForegroundColor Gray
    } else {
        Write-Host "  {`"intent`":`"$Name`"}" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# Alias for quick testing
Set-Alias -Name intent -Value Test-Intent -Force
Set-Alias -Name intent-help -Value Show-IntentHelp -Force

# ===== Tab Completion for Intents =====
Register-ArgumentCompleter -CommandName Invoke-IntentAction -ParameterName Intent -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $global:IntentAliases.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        $description = if ($global:IntentMetadata.ContainsKey($_)) { $global:IntentMetadata[$_].Description } else { "Intent action" }
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
    }
}

# Tab completion for Test-Intent (intent alias) - complete JSON payloads
Register-ArgumentCompleter -CommandName Test-Intent -ParameterName JsonPayload -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $global:IntentAliases.Keys | Sort-Object | ForEach-Object {
        $json = "{`"intent`":`"$_`"}"
        $description = if ($global:IntentMetadata.ContainsKey($_)) { $global:IntentMetadata[$_].Description } else { "Intent action" }
        [System.Management.Automation.CompletionResult]::new("'$json'", $_, 'ParameterValue', $description)
    }
}

# Tab completion for Get-IntentInfo
Register-ArgumentCompleter -CommandName Get-IntentInfo -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $global:IntentAliases.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# Tab completion for Show-IntentHelp -Category
Register-ArgumentCompleter -CommandName Show-IntentHelp -ParameterName Category -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $global:IntentCategories.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        $desc = $global:IntentCategories[$_].Name
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
    }
}
