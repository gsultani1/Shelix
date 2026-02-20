# ===== IntentActions.ps1 =====
# Core intent scriptblocks: documents, files, web, clipboard, git, MCP, calendar.
# Initializes $global:IntentAliases — loaded after IntentRegistry.ps1.

$global:IntentAliases = @{
    # ===== Document Operations =====
    "create_docx"               = { 
        param($name, $content)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: name parameter required"; Error = $true }
        }
        
        $safeName = $name -replace '[<>:"/\\|?*]', '_'
        $sep = Get-PlatformSeparator
        $docsPath = if ($IsWindows -or $env:OS -eq 'Windows_NT') { "$env:USERPROFILE${sep}Documents" } else { "$HOME/Documents" }
        $path = Join-Path $docsPath "$safeName.docx"
        
        $validation = Test-PathAllowed -Path $path -AllowCreation
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        try {
            $initialContent = if ($content) { $content } else { "" }
            New-MinimalDocx -Path $path -Content $initialContent
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Create' -Path $path -ExecutionId 'intent'
            }
            
            Open-PlatformPath -Path $path
            @{ Success = $true; Output = "Created and opened: $path"; Path = $path; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to create DOCX: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "create_xlsx"               = { 
        param($name, $sheetName)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: name parameter required"; Error = $true }
        }
        
        $safeName = $name -replace '[<>:"/\\|?*]', '_'
        $sep = Get-PlatformSeparator
        $docsPath = if ($IsWindows -or $env:OS -eq 'Windows_NT') { "$env:USERPROFILE${sep}Documents" } else { "$HOME/Documents" }
        $path = Join-Path $docsPath "$safeName.xlsx"
        
        $validation = Test-PathAllowed -Path $path -AllowCreation
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        try {
            $sheet = if ($sheetName) { $sheetName } else { "Sheet1" }
            New-MinimalXlsx -Path $path -SheetName $sheet
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Create' -Path $path -ExecutionId 'intent'
            }
            
            Open-PlatformPath -Path $path
            @{ Success = $true; Output = "Created and opened: $path"; Path = $path; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to create XLSX: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "create_csv"                = {
        param($name, $headers)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: name parameter required"; Error = $true }
        }
        
        $safeName = $name -replace '[<>:"/\\|?*]', '_'
        $sep = Get-PlatformSeparator
        $docsPath = if ($IsWindows -or $env:OS -eq 'Windows_NT') { "$env:USERPROFILE${sep}Documents" } else { "$HOME/Documents" }
        $path = Join-Path $docsPath "$safeName.csv"
        
        $validation = Test-PathAllowed -Path $path -AllowCreation
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        try {
            # Create CSV with optional headers
            $content = if ($headers) { $headers } else { "" }
            Set-Content -Path $path -Value $content -Encoding UTF8
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Create' -Path $path -ExecutionId 'intent'
            }
            
            Open-PlatformPath -Path $path
            @{ Success = $true; Output = "Created and opened: $path"; Path = $path; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to create CSV: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    # ===== File Operations =====
    "open_file"                 = { 
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        try {
            Open-PlatformPath -Path $validation.Path
            @{ Success = $true; Output = "Opened: $($validation.Path)" }
        }
        catch {
            @{ Success = $false; Output = "Failed to open: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "search_file"               = { 
        param($term, $path)
        if (-not $term) {
            return @{ Success = $false; Output = "Error: term parameter required"; Error = $true }
        }
        
        $sep = Get-PlatformSeparator
        if (-not $path) { 
            $path = if ($IsWindows -or $env:OS -eq 'Windows_NT') { "$env:USERPROFILE${sep}Documents" } else { "$HOME/Documents" }
        }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        $resolvedPath = $validation.Path
        $maxDepth = 5
        $maxResults = 50
        
        try {
            $isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7
            
            if ($isPwsh7) {
                $results = Get-ChildItem -Path $resolvedPath -Recurse -Depth $maxDepth -Filter "*$term*" -ErrorAction SilentlyContinue | 
                Select-Object -First $maxResults |
                Select-Object -ExpandProperty FullName
            }
            else {
                $results = @()
                $queue = [System.Collections.Generic.Queue[PSObject]]::new()
                $queue.Enqueue([PSCustomObject]@{ Path = $resolvedPath; Depth = 0 })
                
                while ($queue.Count -gt 0 -and $results.Count -lt $maxResults) {
                    $current = $queue.Dequeue()
                    
                    $items = Get-ChildItem -Path $current.Path -Filter "*$term*" -ErrorAction SilentlyContinue
                    foreach ($item in $items) {
                        if ($results.Count -ge $maxResults) { break }
                        $results += $item.FullName
                    }
                    
                    if ($current.Depth -lt $maxDepth) {
                        $subdirs = Get-ChildItem -Path $current.Path -Directory -ErrorAction SilentlyContinue
                        foreach ($subdir in $subdirs) {
                            $queue.Enqueue([PSCustomObject]@{ Path = $subdir.FullName; Depth = $current.Depth + 1 })
                        }
                    }
                }
            }
            
            @{
                Success    = $true
                Output     = "Found $($results.Count) items (max depth: $maxDepth, limit: $maxResults)"
                Results    = $results
                SearchPath = $resolvedPath
                Term       = $term
            }
        }
        catch {
            @{ Success = $false; Output = "Search failed: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "open_recent"               = {
        param($count)
        if (-not $count) { $count = 5 }
        $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"
        $recent = Get-ChildItem $recentPath -Filter "*.lnk" -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First $count
        @{
            Success = $true
            Output  = "Recent $count files"
            Results = $recent | ForEach-Object { $_.Name -replace '\.lnk$', '' }
        }
    }
    
    # ===== Web Operations =====
    "browse_web"                = { 
        param($url)
        if (-not $url) {
            return @{ Success = $false; Output = "Error: url parameter required"; Error = $true }
        }
        
        $validation = Test-UrlAllowed -Url $url
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true; Reason = $validation.Reason }
        }
        
        try {
            Open-PlatformPath -Path $validation.Url
            @{ Success = $true; Output = "Opened: $($validation.Url)" }
        }
        catch {
            @{ Success = $false; Output = "Failed to open URL: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "open_url"                  = {
        param($url, $browser)
        if (-not $url) {
            return @{ Success = $false; Output = "Error: url parameter required"; Error = $true }
        }
        
        $validation = Test-UrlAllowed -Url $url
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true; Reason = $validation.Reason }
        }
        
        $validatedUrl = $validation.Url
        if (-not $browser) { $browser = "default" }
        
        $onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
        
        if ($browser -eq 'default') {
            try {
                Open-PlatformPath -Path $validatedUrl
                return @{ Success = $true; Output = "Opened $validatedUrl in default browser"; Browser = 'default'; URL = $validatedUrl }
            }
            catch {
                return @{ Success = $false; Output = "Failed to open URL: $($_.Exception.Message)"; Error = $true }
            }
        }
        
        $browserCommands = @{
            'chrome'  = @{ Windows = 'chrome'; macOS = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; Linux = 'google-chrome' }
            'firefox' = @{ Windows = 'firefox'; macOS = '/Applications/Firefox.app/Contents/MacOS/firefox'; Linux = 'firefox' }
            'edge'    = @{ Windows = 'msedge'; macOS = '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'; Linux = 'microsoft-edge' }
        }
        
        $browserKey = $browser.ToLower()
        if (-not $browserCommands.ContainsKey($browserKey)) {
            return @{ Success = $false; Output = "Unknown browser '$browser'. Supported: chrome, firefox, edge, default"; Error = $true }
        }
        
        $platform = if ($onWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
        $browserExe = $browserCommands[$browserKey][$platform]
        
        try {
            if ($onWindows) {
                Start-Process $browserExe -ArgumentList $validatedUrl
            }
            else {
                & $browserExe $validatedUrl
            }
            @{ Success = $true; Output = "Opened $validatedUrl in $browser"; Browser = $browser; URL = $validatedUrl }
        }
        catch {
            @{ Success = $false; Output = "Failed to launch $browser : $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "open_browser_search"       = { 
        # Opens browser with Google search - AI cannot see results
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: query parameter required"; Error = $true }
        }
        $encodedQuery = [System.Uri]::EscapeDataString($query)
        $url = "https://www.google.com/search?q=$encodedQuery"
        
        try {
            Open-PlatformPath -Path $url
            @{ Success = $true; Output = "Opened Google search in browser for: $query (Note: AI cannot see browser results)"; URL = $url }
        }
        catch {
            @{ Success = $false; Output = "Failed to open search: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "web_search"                = {
        # Search using DuckDuckGo API and return results to AI
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: query parameter required"; Error = $true }
        }
        $result = Invoke-WebSearch -Query $query
        if ($result.Success) {
            $output = Format-SearchResultsForAI $result
            @{ Success = $true; Output = $output; ResultCount = $result.ResultCount; Results = $result.Results }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "search_web"                = {
        # Alias for web_search (backward compatibility)
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: query parameter required"; Error = $true }
        }
        $result = Invoke-WebSearch -Query $query
        if ($result.Success) {
            $output = Format-SearchResultsForAI $result
            @{ Success = $true; Output = $output; ResultCount = $result.ResultCount; Results = $result.Results }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "wikipedia"                 = {
        # Search Wikipedia and return summary
        param($query)
        if (-not $query) {
            return @{ Success = $false; Output = "Error: query parameter required"; Error = $true }
        }
        $result = Search-Wikipedia -Query $query
        if ($result.Success) {
            $output = Format-SearchResultsForAI $result
            @{ Success = $true; Output = $output; ResultCount = $result.ResultCount }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "fetch_url"                 = {
        # Fetch and return content from a URL
        param($url)
        if (-not $url) {
            return @{ Success = $false; Output = "Error: url parameter required"; Error = $true }
        }
        $result = Get-WebPageContent -Url $url -MaxLength 3000
        if ($result.Success) {
            @{ Success = $true; Output = "Content from $url :`n`n$($result.Content)"; Length = $result.Length }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }

    "browser_tab"               = {
        # Get the active browser tab URL and title
        $result = Get-ActiveBrowserTab
        if ($result.Success) {
            $info = @("Browser: $($result.Browser)", "Title: $($result.Title)")
            if ($result.Url) { $info += "URL: $($result.Url)" }
            $info += "Method: $($result.Method)"
            @{ Success = $true; Output = ($info -join "`n"); Url = $result.Url; Title = $result.Title; Browser = $result.Browser }
        }
        else {
            @{ Success = $false; Output = $result.Output; Error = $true }
        }
    }

    "browser_content"           = {
        # Fetch the page content from the active browser tab
        $result = Get-BrowserPageContent -MaxLength 3000
        if ($result.Success -and $result.Content) {
            @{ Success = $true; Output = "[$($result.Browser)] $($result.Title)`nURL: $($result.Url)`n`n$($result.Content)"; Url = $result.Url }
        }
        elseif ($result.Success) {
            @{ Success = $true; Output = $result.Output }
        }
        else {
            @{ Success = $false; Output = $result.Output; Error = $true }
        }
    }

    # ===== CODE ARTIFACTS =====
    "save_code"                 = {
        param($code, $filename, $language)
        if (-not $code) {
            return @{ Success = $false; Output = "Error: code parameter required"; Error = $true }
        }
        $lang = if ($language) { $language } else { 'text' }
        $result = Save-Artifact -Code $code -Language $lang -Path $filename -Force
        $result
    }

    "run_code"                  = {
        param($code, $language, $filename)
        if (-not $code) {
            return @{ Success = $false; Output = "Error: code parameter required"; Error = $true }
        }
        if (-not $language) {
            return @{ Success = $false; Output = "Error: language parameter required (powershell, python, js, bash, etc.)"; Error = $true }
        }
        # Save first if filename provided
        if ($filename) {
            Save-Artifact -Code $code -Language $language -Path $filename -Force | Out-Null
        }
        $result = Invoke-Artifact -Code $code -Language $language
        $result
    }

    "list_artifacts"            = {
        Get-Artifacts
        @{ Success = $true; Output = "Listed saved artifacts." }
    }
    
    # ===== CLIPBOARD OPERATIONS =====
    "clipboard_read"            = {
        $result = Get-ClipboardContent
        if ($result.Success) {
            $preview = if ($result.Content.Length -gt 1000) { $result.Content.Substring(0, 1000) + "..." } else { $result.Content }
            @{ Success = $true; Output = "Clipboard ($($result.Type), $($result.Length) chars, $($result.Lines) lines):`n$preview" }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    "clipboard_write"           = {
        param($text)
        if (-not $text) {
            return @{ Success = $false; Output = "Error: text parameter required"; Error = $true }
        }
        $result = Set-ClipboardContent -Content $text
        @{ Success = $result.Success; Output = $result.Message }
    }
    
    "clipboard_format_json"     = {
        $result = Convert-ClipboardJson
        if ($result.Success) {
            @{ Success = $true; Output = "$($result.Output)`n`nPreview:`n$($result.Preview)" }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "clipboard_case"            = {
        param($case)
        if (-not $case) { $case = "upper" }
        $result = Convert-ClipboardCase -Case $case
        if ($result.Success) {
            @{ Success = $true; Output = "$($result.Output)`n`nPreview: $($result.Preview)" }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    # ===== TODO: I Just Wanted to see if you were paying attention =====
    # "make_coffee" = {
    #     param($strength, $sugar)
    #     if (-not $strength) { $strength = "strong" }
    #     # Check if coffee maker is connected via USB
    #     # $coffeeMaker = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*Keurig*" }
    #     # Start-CoffeeBrew -Strength $strength -Sugar $sugar
    #     @{ 
    #         Success = $false
    #         Output = "Feature coming in v2.0. For now, walk to the kitchen."
    #         Suggestion = "Have you tried mass amounts of caffeine? I have. The code still doesn't work."
    #     }
    # }
    
    # ===== FILE CONTENT ANALYSIS =====
    "read_file"                 = {
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
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "file_stats"                = {
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        $result = Get-FileStats -Path $path
        if ($result.Success) {
            $output = "File: $($result.Name)`nPath: $($result.Path)`nSize: $($result.Size)`nCreated: $($result.Created)`nModified: $($result.Modified)"
            if ($result.Lines) { $output += "`nLines: $($result.Lines)`nWords: $($result.Words)`nCharacters: $($result.Characters)" }
            @{ Success = $true; Output = $output }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    # ===== GIT INTEGRATION =====
    "git_status"                = {
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
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_log"                   = {
        param($count)
        if (-not $count) { $count = 10 }
        $result = Get-GitLog -Count $count
        if ($result.Success) {
            $output = "Recent commits ($($result.Count)):`n"
            foreach ($c in $result.Commits) {
                $output += "`n$($c.Hash) - $($c.Message) ($($c.Author), $($c.Time))"
            }
            @{ Success = $true; Output = $output }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_commit"                = {
        param($message)
        if (-not $message) {
            return @{ Success = $false; Output = "Error: message parameter required"; Error = $true }
        }
        $result = Invoke-GitCommit -Message $message
        if ($result.Success) {
            @{ Success = $true; Output = $result.Message }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_push"                  = {
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
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_pull"                  = {
        $result = Invoke-GitPull
        @{ Success = $result.Success; Output = $result.Output }
    }
    
    "git_diff"                  = {
        param($staged)
        $isStaged = $staged -eq "staged" -or $staged -eq "true"
        $result = Get-GitDiff -Staged:$isStaged
        if ($result.Success) {
            if ($result.Diff) {
                @{ Success = $true; Output = "Diff:`n$($result.Diff)" }
            }
            else {
                @{ Success = $true; Output = $result.Message }
            }
        }
        else {
            @{ Success = $false; Output = $result.Message; Error = $true }
        }
    }
    
    "git_init"                  = {
        param($path)
        if (-not $path) { $path = Get-Location }
        try {
            Push-Location $path
            $output = git init 2>&1
            Pop-Location
            if ($LASTEXITCODE -eq 0) {
                @{ Success = $true; Output = "Initialized git repository in: $path" }
            }
            else {
                @{ Success = $false; Output = "Failed to init: $output"; Error = $true }
            }
        }
        catch {
            Pop-Location
            @{ Success = $false; Output = "Error: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    # ===== MCP (Model Context Protocol) =====
    "mcp_servers"               = {
        $servers = Get-MCPServers
        if ($servers) {
            $output = "Registered MCP Servers:`n"
            foreach ($s in $servers) {
                $status = if ($s.Connected) { "[Connected]" } else { "[Not Connected]" }
                $output += "`n$($s.Name) $status - $($s.Description)"
            }
            @{ Success = $true; Output = $output }
        }
        else {
            @{ Success = $true; Output = "No MCP servers registered. Run: mcp-register" }
        }
    }
    
    "mcp_connect"               = {
        param($server)
        if (-not $server) {
            return @{ Success = $false; Output = "Error: server name required"; Error = $true }
        }
        $result = Connect-MCPServer -Name $server
        if ($result) {
            $toolList = ($result.Tools | ForEach-Object { $_.name }) -join ", "
            @{ Success = $true; Output = "Connected to $server. Tools: $toolList" }
        }
        else {
            @{ Success = $false; Output = "Failed to connect to $server"; Error = $true }
        }
    }
    
    "mcp_call"                  = {
        param($server, $tool, $toolArgs)
        if (-not $server -or -not $tool) {
            return @{ Success = $false; Output = "Error: server and tool parameters required"; Error = $true }
        }
        $arguments = @{}
        if ($toolArgs) {
            try {
                $jsonObj = $toolArgs | ConvertFrom-Json
                # Convert PSObject to hashtable (PS 5.1 compatible)
                $jsonObj.PSObject.Properties | ForEach-Object { $arguments[$_.Name] = $_.Value }
            }
            catch { }
        }
        $result = Invoke-MCPTool -ServerName $server -ToolName $tool -Arguments $arguments
        if ($result.Success) {
            @{ Success = $true; Output = $result.Output }
        }
        else {
            @{ Success = $false; Output = $result.Error; Error = $true }
        }
    }
    
    "mcp_tools"                 = {
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
    "calendar_today"            = {
        $result = Get-OutlookCalendar -Today
        if ($result.Success) {
            if ($result.Count -eq 0) {
                @{ Success = $true; Output = "No events scheduled for today" }
            }
            else {
                $output = "Today's events ($($result.Count)):`n"
                foreach ($e in $result.Events) {
                    $output += "`n- $($e.Start.Substring(11)) - $($e.Subject)"
                    if ($e.Location) { $output += " @ $($e.Location)" }
                    $output += " ($($e.Duration))"
                }
                @{ Success = $true; Output = $output }
            }
        }
        else {
            @{ Success = $false; Output = "$($result.Message). $($result.Hint)"; Error = $true }
        }
    }
    
    "calendar_week"             = {
        $result = Get-OutlookCalendar -Days 7
        if ($result.Success) {
            if ($result.Count -eq 0) {
                @{ Success = $true; Output = "No events scheduled for the next 7 days" }
            }
            else {
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
        }
        else {
            @{ Success = $false; Output = "$($result.Message). $($result.Hint)"; Error = $true }
        }
    }
    
    "calendar_create"           = {
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
            }
            else {
                @{ Success = $false; Output = $result.Message; Error = $true }
            }
        }
        catch {
            @{ Success = $false; Output = "Invalid date format. Use: YYYY-MM-DD HH:MM"; Error = $true }
        }
    }
}

Write-Verbose "IntentActions loaded: $($global:IntentAliases.Count) core intent scriptblocks"
