# ===== IntentAliasSystem.ps1 =====
# Friendly task aliases that the AI can call via JSON intents
# Maps user-friendly intent names to concrete PowerShell commands
# If you're reading this, you're exactly the kind of person who should be using this tool

# ===== Required Module Dependencies =====
# This file depends on functions from other modules. Ensure these are loaded:
# - ProductivityTools.ps1: Get-ClipboardContent, Set-ClipboardContent, Convert-ClipboardJson, 
#   Convert-ClipboardCase, Read-FileContent, Get-FileStats, Get-GitStatus, Get-GitLog,
#   Invoke-GitCommit, Invoke-GitPull, Get-GitDiff, Get-OutlookCalendar, New-OutlookAppointment
# - WebTools.ps1: Invoke-WebSearch, Format-SearchResultsForAI, Search-Wikipedia, Get-WebPageContent
# - MCPClient.ps1: Get-MCPServers, Connect-MCPServer, Invoke-MCPTool
# - SafetySystem.ps1: Add-FileOperation

# ===== Category Definitions (metadata only, intents auto-populated) =====
$global:CategoryDefinitions = @{
    'document'   = @{ Name = 'Document Operations'; Description = 'Create and manage documents' }
    'file'       = @{ Name = 'File Operations'; Description = 'Open, search, and manage files' }
    'web'        = @{ Name = 'Web Operations'; Description = 'Browse and search the web' }
    'app'        = @{ Name = 'Application Launching'; Description = 'Launch applications' }
    'clipboard'  = @{ Name = 'Clipboard Operations'; Description = 'Read, write, and transform clipboard content' }
    'git'        = @{ Name = 'Git Operations'; Description = 'Version control with Git' }
    'calendar'   = @{ Name = 'Calendar (Outlook)'; Description = 'View and manage Outlook calendar' }
    'mcp'        = @{ Name = 'MCP (Model Context Protocol)'; Description = 'Connect to external MCP servers' }
    'system'     = @{ Name = 'System Automation'; Description = 'Services, scheduled tasks, and system info' }
    'workflow'   = @{ Name = 'Workflows'; Description = 'Multi-step automated workflows' }
    'filesystem' = @{ Name = 'File System Operations'; Description = 'Create, rename, move, and manage files/folders' }
}

# ===== Module Initialization =====
if (-not $global:MCPConnections) { $global:MCPConnections = @{} }

# ===== Dependencies =====
# These functions are now in separate modules (loaded before this file):
# - PlatformUtils.ps1: Get-PlatformSeparator, Get-NormalizedPath, Open-PlatformPath
# - SecurityUtils.ps1: Test-PathAllowed, Test-UrlAllowed, $AllowedRoots, $BlockedDomains
# - DocumentTools.ps1: New-MinimalDocx, New-MinimalXlsx

# ===== Intent Metadata for Validation =====
$global:IntentMetadata = @{
    'create_docx'               = @{
        Category    = 'document'
        Description = 'Create a new Word document'
        Parameters  = @(
            @{ Name = 'name'; Required = $true; Description = 'Document name (without extension)' }
        )
    }
    'create_xlsx'               = @{
        Category    = 'document'
        Description = 'Create a new Excel spreadsheet'
        Parameters  = @(
            @{ Name = 'name'; Required = $true; Description = 'Spreadsheet name (without extension)' }
        )
    }
    'create_csv'                = @{
        Category    = 'document'
        Description = 'Create a new CSV file'
        Parameters  = @(
            @{ Name = 'name'; Required = $true; Description = 'CSV file name (without extension)' }
            @{ Name = 'headers'; Required = $false; Description = 'Optional column headers' }
        )
    }
    'open_file'                 = @{
        Category    = 'file'
        Description = 'Open a file with default application'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Full path to the file' }
        )
    }
    'search_file'               = @{
        Category    = 'file'
        Description = 'Search for files matching a term'
        Parameters  = @(
            @{ Name = 'term'; Required = $true; Description = 'Search term' }
            @{ Name = 'path'; Required = $false; Description = 'Directory to search (default: Documents)' }
        )
    }
    'browse_web'                = @{
        Category    = 'web'
        Description = 'Open URL in default browser'
        Parameters  = @(
            @{ Name = 'url'; Required = $true; Description = 'URL to open' }
        )
    }
    'open_url'                  = @{
        Category    = 'web'
        Description = 'Open URL with browser selection and validation'
        Parameters  = @(
            @{ Name = 'url'; Required = $true; Description = 'URL to open' }
            @{ Name = 'browser'; Required = $false; Description = 'Browser: chrome, firefox, edge, default' }
        )
    }
    'search_web'                = @{
        Category    = 'web'
        Description = 'Search Google for a query'
        Parameters  = @(
            @{ Name = 'query'; Required = $true; Description = 'Search query' }
        )
    }
    'open_word'                 = @{ Category = 'app'; Description = 'Launch Microsoft Word'; Parameters = @() }
    'open_excel'                = @{ Category = 'app'; Description = 'Launch Microsoft Excel'; Parameters = @() }
    'open_powerpoint'           = @{ Category = 'app'; Description = 'Launch Microsoft PowerPoint'; Parameters = @() }
    'open_notepad'              = @{ Category = 'app'; Description = 'Launch Notepad'; Parameters = @() }
    'open_calculator'           = @{ Category = 'app'; Description = 'Launch Calculator'; Parameters = @() }
    'open_browser'              = @{
        Category    = 'app'
        Description = 'Launch a specific browser'
        Parameters  = @(
            @{ Name = 'browser'; Required = $false; Description = 'Browser: chrome, firefox, edge (default: edge)' }
        )
    }
    'open_recent'               = @{
        Category    = 'file'
        Description = 'Open recently modified files'
        Parameters  = @(@{ Name = 'count'; Required = $false; Description = 'Number of files to show (default: 10)' })
    }
    'create_and_open_doc'       = @{
        Category    = 'workflow'
        Description = 'Create a document and open it in Word'
        Parameters  = @(
            @{ Name = 'name'; Required = $true; Description = 'Document name' }
        )
    }
    'research_topic'            = @{
        Category    = 'workflow'
        Description = 'Search web and create notes document for a topic'
        Parameters  = @(
            @{ Name = 'topic'; Required = $true; Description = 'Research topic' }
        )
    }
    'daily_standup'             = @{
        Category    = 'workflow'
        Description = 'Open common apps for daily standup'
        Parameters  = @()
    }
    # File System Operations
    'create_folder'             = @{
        Category    = 'filesystem'
        Description = 'Create a new folder'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Folder path to create' }
        )
    }
    'rename_file'               = @{
        Category    = 'filesystem'
        Description = 'Rename a file or folder'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Current file path' }
            @{ Name = 'newname'; Required = $true; Description = 'New name' }
        )
    }
    'move_file'                 = @{
        Category    = 'filesystem'
        Description = 'Move a file or folder'
        Parameters  = @(
            @{ Name = 'source'; Required = $true; Description = 'Source path' }
            @{ Name = 'destination'; Required = $true; Description = 'Destination path' }
        )
    }
    'copy_file'                 = @{
        Category    = 'filesystem'
        Description = 'Copy a file or folder'
        Parameters  = @(
            @{ Name = 'source'; Required = $true; Description = 'Source path' }
            @{ Name = 'destination'; Required = $true; Description = 'Destination path' }
        )
    }
    'delete_file'               = @{
        Category    = 'filesystem'
        Description = 'Delete a file (with confirmation)'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'File path to delete' }
        )
    }
    'list_files'                = @{
        Category    = 'filesystem'
        Description = 'List files in a directory'
        Parameters  = @(
            @{ Name = 'path'; Required = $false; Description = 'Directory path (default: current)' }
        )
    }
    # Clipboard (actual intents)
    'clipboard_read'            = @{ Category = 'clipboard'; Description = 'Read clipboard content'; Parameters = @() }
    'clipboard_write'           = @{
        Category    = 'clipboard'
        Description = 'Write text to clipboard'
        Parameters  = @(@{ Name = 'text'; Required = $true; Description = 'Text to copy' })
    }
    'clipboard_format_json'     = @{ Category = 'clipboard'; Description = 'Format clipboard content as JSON'; Parameters = @() }
    'clipboard_case'            = @{
        Category    = 'clipboard'
        Description = 'Change clipboard text case'
        Parameters  = @(@{ Name = 'case'; Required = $true; Description = 'upper, lower, or title' })
    }
    # Web
    'web_search'                = @{
        Category    = 'web'
        Description = 'Search the web'
        Parameters  = @(@{ Name = 'query'; Required = $true; Description = 'Search query' })
    }
    'wikipedia'                 = @{
        Category    = 'web'
        Description = 'Search Wikipedia'
        Parameters  = @(@{ Name = 'query'; Required = $true; Description = 'Wikipedia search term' })
    }
    'fetch_url'                 = @{
        Category    = 'web'
        Description = 'Fetch content from a URL'
        Parameters  = @(@{ Name = 'url'; Required = $true; Description = 'URL to fetch' })
    }
    # File
    'open_folder'               = @{
        Category    = 'file'
        Description = 'Open folder in Explorer'
        Parameters  = @(@{ Name = 'path'; Required = $false; Description = 'Folder path (default: current)' })
    }
    'read_file'                 = @{
        Category    = 'file'
        Description = 'Read file contents'
        Parameters  = @(@{ Name = 'path'; Required = $true; Description = 'File path to read' })
    }
    'file_stats'                = @{
        Category    = 'file'
        Description = 'Get file statistics'
        Parameters  = @(@{ Name = 'path'; Required = $true; Description = 'File path' })
    }
    # App
    'open_terminal'             = @{
        Category    = 'app'
        Description = 'Open terminal at path'
        Parameters  = @(@{ Name = 'path'; Required = $false; Description = 'Directory path (default: current)' })
    }
    # Git
    'git_status'                = @{ Category = 'git'; Description = 'Show git repository status'; Parameters = @() }
    'git_log'                   = @{
        Category    = 'git'
        Description = 'Show git commit history'
        Parameters  = @(@{ Name = 'count'; Required = $false; Description = 'Number of commits (default: 10)' })
    }
    'git_commit'                = @{
        Category    = 'git'
        Description = 'Commit staged changes'
        Parameters  = @(@{ Name = 'message'; Required = $true; Description = 'Commit message' })
    }
    'git_push'                  = @{
        Category    = 'git'
        Description = 'Commit and push changes to remote'
        Parameters  = @(@{ Name = 'message'; Required = $true; Description = 'Commit message' })
    }
    'git_pull'                  = @{ Category = 'git'; Description = 'Pull changes from remote'; Parameters = @() }
    'git_diff'                  = @{ Category = 'git'; Description = 'Show uncommitted changes'; Parameters = @() }
    'git_init'                  = @{
        Category    = 'git'
        Description = 'Initialize a new git repository'
        Parameters  = @(@{ Name = 'path'; Required = $false; Description = 'Path to initialize (default: current directory)' })
    }
    # Calendar
    'calendar_today'            = @{ Category = 'calendar'; Description = 'Show today''s calendar events'; Parameters = @() }
    'calendar_week'             = @{ Category = 'calendar'; Description = 'Show this week''s calendar events'; Parameters = @() }
    'calendar_create'           = @{
        Category    = 'calendar'
        Description = 'Create calendar event'
        Parameters  = @(
            @{ Name = 'subject'; Required = $true; Description = 'Event subject' }
            @{ Name = 'start'; Required = $true; Description = 'Start time (e.g., "2pm", "14:00")' }
            @{ Name = 'duration'; Required = $false; Description = 'Duration in minutes (default: 60)' }
        )
    }
    # MCP
    'mcp_servers'               = @{ Category = 'mcp'; Description = 'List registered MCP servers'; Parameters = @() }
    'mcp_connect'               = @{
        Category    = 'mcp'
        Description = 'Connect to an MCP server'
        Parameters  = @(@{ Name = 'server'; Required = $true; Description = 'Server name' })
    }
    'mcp_tools'                 = @{
        Category    = 'mcp'
        Description = 'List tools from connected MCP server'
        Parameters  = @(@{ Name = 'server'; Required = $true; Description = 'Server name' })
    }
    'mcp_call'                  = @{
        Category    = 'mcp'
        Description = 'Call an MCP tool'
        Parameters  = @(
            @{ Name = 'server'; Required = $true; Description = 'Server name' }
            @{ Name = 'tool'; Required = $true; Description = 'Tool name' }
            @{ Name = 'toolArgs'; Required = $false; Description = 'Tool arguments as JSON' }
        )
    }
    # System
    'service_status'            = @{
        Category    = 'system'
        Description = 'Check service status'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Service name' })
    }
    'service_start'             = @{
        Category    = 'system'
        Description = 'Start a service'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Service name' })
        Safety      = 'RequiresConfirmation'
    }
    'service_stop'              = @{
        Category    = 'system'
        Description = 'Stop a service'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Service name' })
        Safety      = 'RequiresConfirmation'
    }
    'service_restart'           = @{
        Category    = 'system'
        Description = 'Restart a service'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Service name' })
        Safety      = 'RequiresConfirmation'
    }
    'services_list'             = @{
        Category    = 'system'
        Description = 'List services'
        Parameters  = @(@{ Name = 'filter'; Required = $false; Description = 'Filter by name' })
    }
    'scheduled_tasks'           = @{
        Category    = 'system'
        Description = 'List scheduled tasks'
        Parameters  = @(@{ Name = 'filter'; Required = $false; Description = 'Filter by name' })
    }
    'scheduled_task_run'        = @{
        Category    = 'system'
        Description = 'Run a scheduled task'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Task name' })
    }
    'scheduled_task_enable'     = @{
        Category    = 'system'
        Description = 'Enable a scheduled task'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Task name' })
    }
    'scheduled_task_disable'    = @{
        Category    = 'system'
        Description = 'Disable a scheduled task'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Task name' })
        Safety      = 'RequiresConfirmation'
    }
    'system_info'               = @{ Category = 'system'; Description = 'Show system information (OS, memory, disk)'; Parameters = @() }
    'network_status'            = @{ Category = 'system'; Description = 'Show network status and IP addresses'; Parameters = @() }
    'process_list'              = @{
        Category    = 'system'
        Description = 'List running processes'
        Parameters  = @(@{ Name = 'filter'; Required = $false; Description = 'Filter by name' })
    }
    'process_kill'              = @{
        Category    = 'system'
        Description = 'Kill a process'
        Parameters  = @(@{ Name = 'name'; Required = $true; Description = 'Process name or ID' })
        Safety      = 'RequiresConfirmation'
    }
    # Workflow
    'run_workflow'              = @{
        Category    = 'workflow'
        Description = 'Run a multi-step workflow'
        Parameters  = @(
            @{ Name = 'name'; Required = $true; Description = 'Workflow name' }
            @{ Name = 'params'; Required = $false; Description = 'Workflow parameters as JSON' }
        )
    }
    'schedule_workflow'         = @{
        Category    = 'workflow'
        Description = 'Schedule a workflow to run automatically'
        Parameters  = @(
            @{ Name = 'workflow'; Required = $true; Description = 'Workflow name' }
            @{ Name = 'schedule'; Required = $true; Description = 'Schedule type: daily, weekly, interval, startup, logon' }
            @{ Name = 'time'; Required = $false; Description = 'Time for daily/weekly (e.g. "09:00")' }
            @{ Name = 'interval'; Required = $false; Description = 'Interval (e.g. "1h", "30m")' }
            @{ Name = 'days'; Required = $false; Description = 'Days for weekly (e.g. "Mon,Tue,Fri")' }
        )
        Safety      = 'RequiresConfirmation'
    }
    'remove_scheduled_workflow' = @{
        Category    = 'workflow'
        Description = 'Remove a scheduled workflow (unregister task and delete bootstrap script)'
        Parameters  = @(
            @{ Name = 'workflow'; Required = $true; Description = 'Workflow name to unschedule' }
        )
        Safety      = 'RequiresConfirmation'
    }
    'list_scheduled_workflows'  = @{
        Category    = 'workflow'
        Description = 'List Shelix-managed scheduled workflows'
        Parameters  = @(
            @{ Name = 'filter'; Required = $false; Description = 'Filter by workflow name' }
        )
    }
    'list_workflows'            = @{ Category = 'workflow'; Description = 'List available workflows'; Parameters = @() }
    
    # File content operations
    'append_to_file'            = @{
        Category    = 'filesystem'
        Description = 'Append content to an existing file'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Path to the file' }
            @{ Name = 'content'; Required = $true; Description = 'Content to append' }
        )
        SafetyTier  = 'RequiresConfirmation'
    }
    'write_to_file'             = @{
        Category    = 'filesystem'
        Description = 'Write content to a file (creates or overwrites)'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Path to the file' }
            @{ Name = 'content'; Required = $true; Description = 'Content to write' }
        )
        SafetyTier  = 'RequiresConfirmation'
    }
    'read_file_content'         = @{
        Category    = 'filesystem'
        Description = 'Read content from a text file'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Path to the file' }
            @{ Name = 'lines'; Required = $false; Description = 'Max lines to read (default 100)' }
        )
    }
}

# ===== Generate IntentCategories from IntentMetadata (single source of truth) =====
$global:IntentCategories = @{}
foreach ($category in $global:CategoryDefinitions.Keys) {
    $global:IntentCategories[$category] = @{
        Name        = $global:CategoryDefinitions[$category].Name
        Description = $global:CategoryDefinitions[$category].Description
        Intents     = @($global:IntentMetadata.Keys | Where-Object { $global:IntentMetadata[$_].Category -eq $category } | Sort-Object)
    }
}

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
    
    # ===== Application Launching =====
    "open_word"                 = { 
        Start-Process winword -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched Microsoft Word" }
    }
    
    "open_excel"                = { 
        Start-Process excel -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched Microsoft Excel" }
    }
    
    "open_powerpoint"           = { 
        Start-Process powerpnt -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched Microsoft PowerPoint" }
    }
    
    "open_notepad"              = { 
        Start-Process notepad
        @{ Success = $true; Output = "Launched Notepad" }
    }
    
    "open_calculator"           = { 
        Start-Process calc
        @{ Success = $true; Output = "Launched Calculator" }
    }
    
    "open_folder"               = {
        param($path)
        if (-not $path) { $path = Get-Location }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        if (-not (Test-Path $validation.Path -PathType Container)) {
            return @{ Success = $false; Output = "Not a folder: $($validation.Path)"; Error = $true }
        }
        
        try {
            Open-PlatformPath -Path $validation.Path -Folder
            @{ Success = $true; Output = "Opened folder: $($validation.Path)" }
        }
        catch {
            @{ Success = $false; Output = "Failed to open folder: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "open_terminal"             = {
        param($path)
        if (-not $path) { $path = Get-Location }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        $onWindows = $IsWindows -or $env:OS -eq 'Windows_NT'
        
        try {
            if ($onWindows) {
                Start-Process wt -ArgumentList "-d", $validation.Path -ErrorAction SilentlyContinue
            }
            elseif ($IsMacOS) {
                & open -a Terminal $validation.Path
            }
            else {
                $termLaunched = $false
                try { & gnome-terminal --working-directory=$validation.Path 2>$null; $termLaunched = $true } catch {}
                if (-not $termLaunched) { & xterm -e "cd $($validation.Path) && bash" 2>$null }
            }
            @{ Success = $true; Output = "Opened terminal at: $($validation.Path)" }
        }
        catch {
            @{ Success = $false; Output = "Failed to open terminal: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "open_browser"              = {
        param($browser)
        if (-not $browser) { $browser = "edge" }
        $browsers = @{
            'chrome'  = 'chrome'
            'firefox' = 'firefox'
            'edge'    = 'msedge'
        }
        $exe = $browsers[$browser.ToLower()]
        if (-not $exe) {
            return @{ Success = $false; Output = "Unknown browser: $browser. Use: chrome, firefox, edge"; Error = $true }
        }
        Start-Process $exe -ErrorAction SilentlyContinue
        @{ Success = $true; Output = "Launched $browser" }
    }
    
    # ===== Workflow/Composite Intents =====
    "create_and_open_doc"       = {
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
            Output  = "Created and opened: $($createResult.Path)"
            Path    = $createResult.Path
            Steps   = @($createResult, $openResult)
        }
    }
    
    "research_topic"            = {
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
            Success   = $true
            Output    = "Researching '$topic' - opened search and created notes: $($createResult.Path)"
            SearchURL = $searchResult.URL
            NotesPath = $createResult.Path
            Steps     = @($searchResult, $createResult)
        }
    }
    
    "daily_standup"             = {
        # Chain: open multiple apps for daily standup
        $results = @()
        
        $results += & $global:IntentAliases["open_browser"] "edge"
        Start-Sleep -Milliseconds 200
        $results += & $global:IntentAliases["open_word"]
        Start-Sleep -Milliseconds 200
        $results += & $global:IntentAliases["open_excel"]
        
        @{
            Success = $true
            Output  = "Daily standup setup complete - opened browser, Word, and Excel"
            Steps   = $results
        }
    }
    
    "run_workflow"              = {
        param($name, $params)
        if (-not $name) {
            $available = $global:Workflows.Keys -join ", "
            return @{ Success = $false; Output = "Error: workflow name required. Available: $available"; Error = $true }
        }
        
        $workflowParams = @{}
        if ($params) {
            try {
                $jsonObj = $params | ConvertFrom-Json
                $jsonObj.PSObject.Properties | ForEach-Object { $workflowParams[$_.Name] = $_.Value }
            }
            catch { }
        }
        
        $result = Invoke-Workflow -Name $name -Params $workflowParams
        @{ Success = $result.Success; Output = "Workflow '$name' completed"; Results = $result.Results }
    }
    
    "schedule_workflow"         = {
        param($workflow, $schedule, $time, $interval, $days)
        
        # 1. Validate inputs
        if (-not $workflow) { return @{ Success = $false; Output = "Error: workflow name required"; Error = $true } }
        if (-not $global:Workflows.ContainsKey($workflow)) {
            return @{ Success = $false; Output = "Error: Workflow '$workflow' not found"; Error = $true }
        }
        
        if (-not $schedule) { return @{ Success = $false; Output = "Error: schedule type required"; Error = $true } }
        $validSchedules = @('daily', 'weekly', 'interval', 'startup', 'logon')
        if ($schedule -notin $validSchedules) {
            return @{ Success = $false; Output = "Error: Invalid schedule '$schedule'. Use: $($validSchedules -join ', ')"; Error = $true }
        }
        
        # 2. Build Trigger
        try {
            $trigger = switch ($schedule) {
                'daily' {
                    if (-not $time) { throw "Time required for daily schedule (e.g. '09:00')" }
                    New-ScheduledTaskTrigger -Daily -At $time
                }
                'weekly' {
                    if (-not $time) { throw "Time required for weekly schedule" }
                    if (-not $days) { throw "Days required for weekly schedule (e.g. 'Mon,Fri')" }
                    # New-ScheduledTaskTrigger handles string days (Mon, Tue, etc.)
                    New-ScheduledTaskTrigger -Weekly -Days $days -At $time
                }
                'interval' {
                    if (-not $interval) { throw "Interval required (e.g. '1h', '30m')" }
                    
                    # Parse custom interval format
                    $timespan = $null
                    if ($interval -match '^(\d+)([hms])$') {
                        $val = [int]$matches[1]
                        $unit = $matches[2]
                        if ($unit -eq 'h') { $timespan = New-TimeSpan -Hours $val }
                        elseif ($unit -eq 'm') { $timespan = New-TimeSpan -Minutes $val }
                        elseif ($unit -eq 's') { $timespan = New-TimeSpan -Seconds $val }
                    }
                    else {
                        # Try standard Parse
                        try { $timespan = [timespan]::Parse($interval) } catch {}
                    }
                    
                    if (-not $timespan) { throw "Invalid interval format '$interval'. Use '1h', '30m', or 'HH:MM:SS'" }
                    
                    # Create trigger: Once (starting now) + Repetition
                    New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval $timespan
                }
                'startup' { New-ScheduledTaskTrigger -AtStartup }
                'logon' { New-ScheduledTaskTrigger -AtLogon }
            }
        }
        catch {
            return @{ Success = $false; Output = "Error creating trigger: $($_.Exception.Message)"; Error = $true }
        }
        
        # 3. Build Action — generate a self-contained bootstrap script
        # Scheduled tasks run in isolated sessions with NO profile, so we
        # must explicitly dot-source every module the workflow needs.
        $pwshPath = (Get-Process -Id $PID).Path
        $modulesPath = $global:ModulesPath  # Resolved NOW while we have context
        $errorLog = "$env:TEMP\shelix_task_errors.log"
        
        # Create scripts directory for scheduled task bootstrap scripts
        $scriptsDir = Join-Path (Split-Path $modulesPath -Parent) "ScheduledScripts"
        if (-not (Test-Path $scriptsDir)) { New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null }
        
        $scriptPath = Join-Path $scriptsDir "Shelix_$workflow.ps1"
        
        # Build bootstrap script content with absolute paths
        $scriptContent = @"
# Auto-generated by Shelix schedule_workflow — do not edit
# Workflow: $workflow | Schedule: $schedule | Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
`$ErrorActionPreference = 'Stop'
`$errorLog = '$errorLog'
try {
    `$global:ModulesPath = '$modulesPath'

    # Load order-sensitive core modules first (other modules depend on these)
    `$orderedModules = @('ConfigLoader.ps1', 'PlatformUtils.ps1', 'SecurityUtils.ps1', 'CommandValidation.ps1')
    foreach (`$mod in `$orderedModules) {
        . (Join-Path `$global:ModulesPath `$mod)
    }

    # Dynamically load all remaining modules (except IntentAliasSystem and interactive-only modules)
    `$lastModules = @('IntentAliasSystem.ps1', 'ChatProviders.ps1', 'ChatSession.ps1')
    Get-ChildItem (Join-Path `$global:ModulesPath '*.ps1') |
        Where-Object { `$_.Name -notin `$orderedModules -and `$_.Name -notin `$lastModules } |
        ForEach-Object { . `$_.FullName }

    # IntentAliasSystem loads last (depends on all other modules)
    . (Join-Path `$global:ModulesPath 'IntentAliasSystem.ps1')

    Invoke-Workflow -Name '$workflow'
} catch {
    "[`$(Get-Date)] SHELIX TASK ERROR ($workflow): `$(`$_.Exception.Message)" | Out-File `$errorLog -Append
    "`$(`$_.ScriptStackTrace)" | Out-File `$errorLog -Append
}
"@
        Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8
        
        $action = New-ScheduledTaskAction -Execute $pwshPath -Argument "-WindowStyle Hidden -NonInteractive -File `"$scriptPath`""
        
        # 4. Register Task under \Shelix folder
        $taskFolder = "\Shelix"
        $taskName = "Workflow_$workflow"
        $description = "Shelix automated workflow '$workflow' ($schedule)"
        
        try {
            Register-ScheduledTask -TaskName $taskName -TaskPath $taskFolder -Action $action -Trigger $trigger -Description $description -Force | Out-Null
            
            @{ 
                Success    = $true 
                Output     = "Scheduled workflow '$workflow' as task '$taskName' in '$taskFolder' ($schedule)"
                TaskName   = $taskName
                TaskPath   = $taskFolder
                ScriptPath = $scriptPath
            }
        }
        catch {
            @{ Success = $false; Output = "Failed to register task: $($_.Exception.Message)"; Error = $true }
        }
    }

    "remove_scheduled_workflow" = {
        param($workflow)

        if (-not $workflow) {
            return @{ Success = $false; Output = "Error: workflow name required"; Error = $true }
        }

        $taskFolder = "\Shelix"
        $taskName = "Workflow_$workflow"
        $modulesPath = $global:ModulesPath
        $scriptsDir = Join-Path (Split-Path $modulesPath -Parent) "ScheduledScripts"
        $scriptPath = Join-Path $scriptsDir "Shelix_$workflow.ps1"

        $taskRemoved = $false
        $scriptRemoved = $false
        $errors = @()

        # Unregister the scheduled task if it exists
        try {
            $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -Confirm:$false -ErrorAction Stop
                $taskRemoved = $true
            }
            else {
                $errors += "Task '$taskFolder\$taskName' not found in Task Scheduler"
            }
        }
        catch {
            $errors += "Failed to unregister task: $($_.Exception.Message)"
        }

        # Delete the bootstrap script if it exists
        try {
            if (Test-Path $scriptPath) {
                Remove-Item -Path $scriptPath -Force -ErrorAction Stop
                $scriptRemoved = $true
            }
            else {
                $errors += "Bootstrap script not found: $scriptPath"
            }
        }
        catch {
            $errors += "Failed to delete script: $($_.Exception.Message)"
        }

        # Report what was cleaned up
        if ($taskRemoved -or $scriptRemoved) {
            $parts = @()
            if ($taskRemoved) { $parts += "task unregistered" }
            if ($scriptRemoved) { $parts += "script deleted" }
            $output = "Removed scheduled workflow '$workflow' ($($parts -join ', '))"
            if ($errors.Count -gt 0) {
                $output += ". Warnings: $($errors -join '; ')"
            }
            @{ Success = $true; Output = $output }
        }
        else {
            @{ Success = $false; Output = "Scheduled workflow '$workflow' not found. $($errors -join '; ')"; Error = $true }
        }
    }

    "list_scheduled_workflows"  = {
        param($filter)

        try {
            $taskFolder = "\Shelix\"
            $tasks = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue

            if (-not $tasks) {
                return @{ Success = $true; Output = "No scheduled workflows found in \Shelix\" }
            }

            if ($filter) {
                $tasks = $tasks | Where-Object { $_.TaskName -like "*$filter*" }
            }

            $output = "Scheduled Workflows ($($tasks.Count) found):"

            foreach ($task in $tasks | Sort-Object TaskName) {
                $wfName = $task.TaskName -replace '^Workflow_', ''
                $state = $task.State

                # Determine trigger type
                $triggerInfo = "Unknown"
                if ($task.Triggers.Count -gt 0) {
                    $trig = $task.Triggers[0]
                    $triggerInfo = switch -Wildcard ($trig.CimClass.CimClassName) {
                        '*Daily*' { "Daily at $($trig.StartBoundary -replace '.*T(\d{2}:\d{2}).*', '$1')" }
                        '*Weekly*' { "Weekly at $($trig.StartBoundary -replace '.*T(\d{2}:\d{2}).*', '$1')" }
                        '*Boot*' { "At startup" }
                        '*Logon*' { "At logon" }
                        default { $trig.CimClass.CimClassName -replace '.*_Task', '' -replace 'Trigger$', '' }
                    }
                    # Check for repetition interval (interval schedule type)
                    if ($trig.Repetition -and $trig.Repetition.Interval) {
                        $triggerInfo = "Every $($trig.Repetition.Interval)"
                    }
                }

                # Get last run info
                $lastResult = "Never run"
                $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $taskFolder -ErrorAction SilentlyContinue
                if ($taskInfo -and $taskInfo.LastRunTime -ne [DateTime]::MinValue) {
                    $resultCode = $taskInfo.LastTaskResult
                    $lastResult = if ($resultCode -eq 0) { "Success" }
                    elseif ($resultCode -eq 267011) { "Never run" }
                    else { "Error (0x{0:X})" -f $resultCode }
                }

                $output += "`n  [$state] $wfName — $triggerInfo | Last: $lastResult"
            }

            @{ Success = $true; Output = $output }
        }
        catch {
            @{ Success = $false; Output = "Failed to list scheduled workflows: $($_.Exception.Message)"; Error = $true }
        }
    }

    "list_workflows"            = {
        $output = "Available workflows:`n"
        foreach ($name in $global:Workflows.Keys | Sort-Object) {
            $wf = $global:Workflows[$name]
            $output += "`n- $name : $($wf.Description)"
        }
        @{ Success = $true; Output = $output }
    }
    
    # ===== System Automation =====
    # "Restart the print spooler service" - now you can
    
    "service_status"            = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: service name required"; Error = $true }
        }
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            @{ 
                Success     = $true
                Output      = "Service '$($svc.DisplayName)': $($svc.Status)"
                Name        = $svc.Name
                DisplayName = $svc.DisplayName
                Status      = $svc.Status.ToString()
            }
        }
        catch {
            @{ Success = $false; Output = "Service not found: $name"; Error = $true }
        }
    }
    
    "service_start"             = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: service name required"; Error = $true }
        }
        try {
            Start-Service -Name $name -ErrorAction Stop
            @{ Success = $true; Output = "Started service: $name" }
        }
        catch {
            @{ Success = $false; Output = "Failed to start service: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "service_stop"              = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: service name required"; Error = $true }
        }
        try {
            Stop-Service -Name $name -Force -ErrorAction Stop
            @{ Success = $true; Output = "Stopped service: $name" }
        }
        catch {
            @{ Success = $false; Output = "Failed to stop service: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "service_restart"           = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: service name required"; Error = $true }
        }
        try {
            Restart-Service -Name $name -Force -ErrorAction Stop
            @{ Success = $true; Output = "Restarted service: $name" }
        }
        catch {
            @{ Success = $false; Output = "Failed to restart service: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "services_list"             = {
        param($filter)
        $services = Get-Service
        if ($filter) {
            $services = $services | Where-Object { $_.Name -like "*$filter*" -or $_.DisplayName -like "*$filter*" }
        }
        $running = ($services | Where-Object { $_.Status -eq 'Running' }).Count
        $stopped = ($services | Where-Object { $_.Status -eq 'Stopped' }).Count
        $output = "Services: $($services.Count) total ($running running, $stopped stopped)"
        if ($filter) {
            $output += "`nFiltered by: $filter"
            foreach ($svc in $services | Select-Object -First 10) {
                $output += "`n  [$($svc.Status)] $($svc.Name) - $($svc.DisplayName)"
            }
        }
        @{ Success = $true; Output = $output }
    }
    
    "scheduled_tasks"           = {
        param($filter)
        try {
            $tasks = Get-ScheduledTask -ErrorAction Stop
            if ($filter) {
                $tasks = $tasks | Where-Object { $_.TaskName -like "*$filter*" }
            }
            $output = "Scheduled Tasks: $($tasks.Count) found"
            foreach ($task in $tasks | Select-Object -First 15) {
                $state = $task.State
                $output += "`n  [$state] $($task.TaskName)"
            }
            @{ Success = $true; Output = $output }
        }
        catch {
            @{ Success = $false; Output = "Failed to get scheduled tasks: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "scheduled_task_run"        = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: task name required"; Error = $true }
        }
        try {
            Start-ScheduledTask -TaskName $name -ErrorAction Stop
            @{ Success = $true; Output = "Started scheduled task: $name" }
        }
        catch {
            @{ Success = $false; Output = "Failed to run task: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "scheduled_task_enable"     = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: task name required"; Error = $true }
        }
        try {
            Enable-ScheduledTask -TaskName $name -ErrorAction Stop
            @{ Success = $true; Output = "Enabled scheduled task: $name" }
        }
        catch {
            @{ Success = $false; Output = "Failed to enable task: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "scheduled_task_disable"    = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: task name required"; Error = $true }
        }
        try {
            Disable-ScheduledTask -TaskName $name -ErrorAction Stop
            @{ Success = $true; Output = "Disabled scheduled task: $name" }
        }
        catch {
            @{ Success = $false; Output = "Failed to disable task: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "system_info"               = {
        try {
            $os = Get-CimInstance Win32_OperatingSystem
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            $mem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $memFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
            $diskFree = [math]::Round($disk.FreeSpace / 1GB, 1)
            $diskTotal = [math]::Round($disk.Size / 1GB, 1)
            
            $output = "System Info:`n"
            $output += "  OS: $($os.Caption) $($os.Version)`n"
            $output += "  CPU: $($cpu.Name)`n"
            $output += "  RAM: $memFree GB free / $mem GB total`n"
            $output += "  Disk C: $diskFree GB free / $diskTotal GB total"
            @{ Success = $true; Output = $output }
        }
        catch {
            @{ Success = $false; Output = "Failed to get system info: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "network_status"            = {
        try {
            $adapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' }
            $output = "Network Status:`n"
            foreach ($adapter in $adapters) {
                $output += "  $($adapter.InterfaceAlias): $($adapter.IPAddress)`n"
            }
            $internet = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
            $output += "  Internet: $(if ($internet) { 'Connected' } else { 'Disconnected' })"
            @{ Success = $true; Output = $output }
        }
        catch {
            @{ Success = $false; Output = "Failed to get network status: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "process_list"              = {
        param($filter)
        $procs = Get-Process | Sort-Object CPU -Descending
        if ($filter) {
            $procs = $procs | Where-Object { $_.Name -like "*$filter*" }
        }
        $top = $procs | Select-Object -First 15
        $output = "Processes: $($procs.Count) total"
        if ($filter) { $output += " (filtered: $filter)" }
        $output += "`n"
        foreach ($p in $top) {
            $mem = [math]::Round($p.WorkingSet64 / 1MB, 1)
            $output += "  $($p.Name) (PID $($p.Id)) - ${mem}MB`n"
        }
        @{ Success = $true; Output = $output }
    }
    
    "process_kill"              = {
        param($name)
        if (-not $name) {
            return @{ Success = $false; Output = "Error: process name or ID required"; Error = $true }
        }
        try {
            if ($name -match '^\d+$') {
                Stop-Process -Id ([int]$name) -Force -ErrorAction Stop
                @{ Success = $true; Output = "Killed process ID: $name" }
            }
            else {
                $procs = Get-Process -Name $name -ErrorAction Stop
                $procs | Stop-Process -Force
                @{ Success = $true; Output = "Killed $($procs.Count) process(es): $name" }
            }
        }
        catch {
            @{ Success = $false; Output = "Failed to kill process: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    # ===== File System Operations =====
    "create_folder"             = {
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        
        $validation = Test-PathAllowed -Path $path -AllowCreation
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        if (Test-Path $path) {
            return @{ Success = $false; Output = "Folder already exists: $path"; Error = $true }
        }
        
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Create' -Path $path -ExecutionId 'intent'
            }
            
            @{ Success = $true; Output = "Created folder: $path"; Path = $path; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to create folder: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "rename_file"               = {
        param($path, $newname)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        if (-not $newname) {
            return @{ Success = $false; Output = "Error: newname parameter required"; Error = $true }
        }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        $newPath = Join-Path (Split-Path $validation.Path -Parent) $newname
        $newValidation = Test-PathAllowed -Path $newPath -AllowCreation
        if (-not $newValidation.Success) {
            return @{ Success = $false; Output = "Security (destination): $($newValidation.Message)"; Error = $true }
        }
        
        try {
            Rename-Item -Path $validation.Path -NewName $newname -Force
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Move' -Path $newPath -OriginalPath $validation.Path -ExecutionId 'intent'
            }
            
            @{ Success = $true; Output = "Renamed: $($validation.Path) -> $newname"; OldPath = $validation.Path; NewPath = $newPath; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to rename: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "move_file"                 = {
        param($source, $destination)
        if (-not $source) {
            return @{ Success = $false; Output = "Error: source parameter required"; Error = $true }
        }
        if (-not $destination) {
            return @{ Success = $false; Output = "Error: destination parameter required"; Error = $true }
        }
        
        $srcValidation = Test-PathAllowed -Path $source
        if (-not $srcValidation.Success) {
            return @{ Success = $false; Output = "Security (source): $($srcValidation.Message)"; Error = $true }
        }
        
        $destValidation = Test-PathAllowed -Path $destination -AllowCreation
        if (-not $destValidation.Success) {
            return @{ Success = $false; Output = "Security (destination): $($destValidation.Message)"; Error = $true }
        }
        
        try {
            Move-Item -Path $srcValidation.Path -Destination $destination -Force
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Move' -Path $destination -OriginalPath $srcValidation.Path -ExecutionId 'intent'
            }
            
            @{ Success = $true; Output = "Moved: $($srcValidation.Path) -> $destination"; Source = $srcValidation.Path; Destination = $destination; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to move: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "copy_file"                 = {
        param($source, $destination)
        if (-not $source) {
            return @{ Success = $false; Output = "Error: source parameter required"; Error = $true }
        }
        if (-not $destination) {
            return @{ Success = $false; Output = "Error: destination parameter required"; Error = $true }
        }
        
        $srcValidation = Test-PathAllowed -Path $source
        if (-not $srcValidation.Success) {
            return @{ Success = $false; Output = "Security (source): $($srcValidation.Message)"; Error = $true }
        }
        
        $destValidation = Test-PathAllowed -Path $destination -AllowCreation
        if (-not $destValidation.Success) {
            return @{ Success = $false; Output = "Security (destination): $($destValidation.Message)"; Error = $true }
        }
        
        try {
            Copy-Item -Path $srcValidation.Path -Destination $destination -Force -Recurse
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Copy' -Path $destination -OriginalPath $srcValidation.Path -ExecutionId 'intent'
            }
            
            @{ Success = $true; Output = "Copied: $($srcValidation.Path) -> $destination"; Source = $srcValidation.Path; Destination = $destination; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to copy: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "delete_file"               = {
        param($path)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        try {
            # Create backup before deletion
            $backupPath = $null
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                $backupDir = "$env:TEMP\IntentBackups"
                if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
                $backupPath = Join-Path $backupDir "$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Split-Path $validation.Path -Leaf)"
                Copy-Item -Path $validation.Path -Destination $backupPath -Force -Recurse
            }
            
            Remove-Item -Path $validation.Path -Force -Recurse
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                Add-FileOperation -Operation 'Delete' -Path $validation.Path -BackupPath $backupPath -ExecutionId 'intent'
            }
            
            @{ Success = $true; Output = "Deleted: $($validation.Path)"; Path = $validation.Path; BackupPath = $backupPath; Undoable = ($null -ne $backupPath) }
        }
        catch {
            @{ Success = $false; Output = "Failed to delete: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "list_files"                = {
        param($path)
        if (-not $path) { $path = Get-Location }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        try {
            $items = Get-ChildItem -Path $validation.Path -ErrorAction SilentlyContinue
            $output = $items | ForEach-Object {
                $type = if ($_.PSIsContainer) { "[DIR]" } else { "[FILE]" }
                "$type $($_.Name)"
            }
            
            @{ 
                Success       = $true
                Output        = "Listed $($items.Count) items in $($validation.Path)"
                Items         = $items | Select-Object Name, Length, LastWriteTime, PSIsContainer
                FormattedList = $output -join "`n"
            }
        }
        catch {
            @{ Success = $false; Output = "Failed to list: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "append_to_file"            = {
        param($path, $content)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        if (-not $content) {
            return @{ Success = $false; Output = "Error: content parameter required"; Error = $true }
        }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        if (-not (Test-Path $validation.Path)) {
            return @{ Success = $false; Output = "File not found: $($validation.Path)"; Error = $true }
        }
        
        try {
            Add-Content -Path $validation.Path -Value $content -Encoding UTF8
            @{ Success = $true; Output = "Appended content to: $($validation.Path)"; Path = $validation.Path; ContentLength = $content.Length }
        }
        catch {
            @{ Success = $false; Output = "Failed to append: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "write_to_file"             = {
        param($path, $content)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        if ($null -eq $content) {
            return @{ Success = $false; Output = "Error: content parameter required"; Error = $true }
        }
        
        $validation = Test-PathAllowed -Path $path -AllowCreation
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        try {
            $existed = Test-Path $validation.Path
            Set-Content -Path $validation.Path -Value $content -Encoding UTF8 -Force
            
            if (Get-Command Add-FileOperation -ErrorAction SilentlyContinue) {
                $op = if ($existed) { 'Modify' } else { 'Create' }
                Add-FileOperation -Operation $op -Path $validation.Path -ExecutionId 'intent'
            }
            
            $verb = if ($existed) { "Updated" } else { "Created" }
            @{ Success = $true; Output = "$verb file: $($validation.Path)"; Path = $validation.Path; ContentLength = $content.Length; Undoable = $true }
        }
        catch {
            @{ Success = $false; Output = "Failed to write: $($_.Exception.Message)"; Error = $true }
        }
    }
    
    "read_file_content"         = {
        param($path, $lines)
        if (-not $path) {
            return @{ Success = $false; Output = "Error: path parameter required"; Error = $true }
        }
        
        $validation = Test-PathAllowed -Path $path
        if (-not $validation.Success) {
            return @{ Success = $false; Output = "Security: $($validation.Message)"; Error = $true }
        }
        
        if (-not (Test-Path $validation.Path)) {
            return @{ Success = $false; Output = "File not found: $($validation.Path)"; Error = $true }
        }
        
        try {
            $maxLines = if ($lines) { [int]$lines } else { 100 }
            $content = Get-Content -Path $validation.Path -TotalCount $maxLines -Raw -ErrorAction Stop
            $totalLines = (Get-Content -Path $validation.Path).Count
            
            @{ 
                Success    = $true
                Output     = "Read $([Math]::Min($maxLines, $totalLines)) of $totalLines lines from $($validation.Path)"
                Content    = $content
                Path       = $validation.Path
                LinesShown = [Math]::Min($maxLines, $totalLines)
                TotalLines = $totalLines
            }
        }
        catch {
            @{ Success = $false; Output = "Failed to read: $($_.Exception.Message)"; Error = $true }
        }
    }
    
}

function Invoke-IntentAction {
    <#
    .SYNOPSIS
    Router function for intent-based actions with metadata validation, safety enforcement, and logging
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Intent,
        [string]$Param = "",
        [string]$Param2 = "",
        [hashtable]$Payload = @{},
        [switch]$AutoConfirm,
        [switch]$Force
    )
    
    $intentId = [guid]::NewGuid().ToString().Substring(0, 8)
    
    try {
        # ===== Validate intent exists =====
        if (-not $global:IntentAliases.ContainsKey($Intent)) {
            Write-Host "[Intent-$intentId] REJECTED: Intent '$Intent' not found" -ForegroundColor Red
            return @{
                Success  = $false
                Output   = "Intent '$Intent' not found. Available: $($global:IntentAliases.Keys -join ', ')"
                Error    = $true
                IntentId = $intentId
                Reason   = "IntentNotFound"
            }
        }
        
        Write-Host "[Intent-$intentId] Validating intent: $Intent" -ForegroundColor DarkCyan
        
        # ===== Get metadata for validation =====
        $meta = $global:IntentMetadata[$Intent]
        
        # ===== Build unified parameter set from Payload and positional args =====
        $providedParams = @{}
        
        # Extract from Payload (excluding meta keys)
        foreach ($key in $Payload.Keys) {
            if ($key -notin @('intent', 'action', 'Intent', 'Action')) {
                $providedParams[$key.ToLower()] = $Payload[$key]
            }
        }
        
        # Map legacy positional params if not already in payload
        if ($Param -and -not $providedParams.ContainsKey('param')) {
            $providedParams['param'] = $Param
        }
        if ($Param2 -and -not $providedParams.ContainsKey('param2')) {
            $providedParams['param2'] = $Param2
        }
        
        # ===== Validate parameters against metadata =====
        if ($meta -and $meta.Parameters) {
            $definedParamNames = @($meta.Parameters | ForEach-Object { $_.Name.ToLower() })
            
            # Also allow 'param' and 'param2' as legacy aliases for first/second defined params
            $legacyMapping = @{}
            if ($definedParamNames.Count -ge 1) {
                $legacyMapping['param'] = $definedParamNames[0]
            }
            if ($definedParamNames.Count -ge 2) {
                $legacyMapping['param2'] = $definedParamNames[1]
            }
            
            # Normalize legacy params to real param names
            foreach ($legacy in @('param', 'param2')) {
                if ($providedParams.ContainsKey($legacy) -and $legacyMapping.ContainsKey($legacy)) {
                    $realName = $legacyMapping[$legacy]
                    if (-not $providedParams.ContainsKey($realName)) {
                        $providedParams[$realName] = $providedParams[$legacy]
                    }
                    $providedParams.Remove($legacy)
                }
            }
            
            # Check for unknown parameters
            $allowedKeys = $definedParamNames + @('param', 'param2')
            $unknownParams = @($providedParams.Keys | Where-Object { $_ -notin $allowedKeys })
            
            if ($unknownParams.Count -gt 0) {
                Write-Host "[Intent-$intentId] REJECTED: Unknown parameters: $($unknownParams -join ', ')" -ForegroundColor Red
                return @{
                    Success  = $false
                    Output   = "Unknown parameters for '$Intent': $($unknownParams -join ', '). Allowed: $($definedParamNames -join ', ')"
                    Error    = $true
                    IntentId = $intentId
                    Reason   = "UnknownParameters"
                }
            }
            
            # Check required parameters
            $missingParams = @()
            foreach ($paramDef in $meta.Parameters) {
                if ($paramDef.Required) {
                    $paramName = $paramDef.Name.ToLower()
                    if (-not $providedParams.ContainsKey($paramName) -or 
                        [string]::IsNullOrWhiteSpace($providedParams[$paramName])) {
                        $missingParams += $paramDef.Name
                    }
                }
            }
            
            if ($missingParams.Count -gt 0) {
                Write-Host "[Intent-$intentId] REJECTED: Missing required parameters: $($missingParams -join ', ')" -ForegroundColor Red
                return @{
                    Success  = $false
                    Output   = "Missing required parameters for '$Intent': $($missingParams -join ', ')"
                    Error    = $true
                    IntentId = $intentId
                    Reason   = "MissingParameters"
                }
            }
        }
        
        # ===== Safety tier enforcement =====
        if ($meta -and $meta.Safety -eq 'RequiresConfirmation') {
            if ($AutoConfirm -and -not $Force) {
                Write-Host "[Intent-$intentId] BLOCKED: '$Intent' requires confirmation (Safety: RequiresConfirmation)" -ForegroundColor Red
                return @{
                    Success  = $false
                    Output   = "Intent '$Intent' requires explicit confirmation. Use -Force to override."
                    Error    = $true
                    IntentId = $intentId
                    Reason   = "SafetyBlock"
                    Safety   = 'RequiresConfirmation'
                }
            }
            if (-not $Force) {
                $AutoConfirm = $false
            }
        }
        
        # ===== Show confirmation prompt =====
        if (-not $AutoConfirm -and -not $Force) {
            Write-Host "`nIntent Action: $Intent" -ForegroundColor Yellow
            foreach ($key in $providedParams.Keys) {
                Write-Host "  $key : $($providedParams[$key])" -ForegroundColor Gray
            }
            
            $response = Read-Host "Proceed? (y/n)"
            if ($response -notin @('y', 'yes', 'Y', 'YES')) {
                Write-Host "[Intent-$intentId] Cancelled by user" -ForegroundColor Yellow
                return @{
                    Success  = $false
                    Output   = "Cancelled by user"
                    Error    = $false
                    IntentId = $intentId
                    Reason   = "UserCancelled"
                }
            }
        }
        
        # ===== Build positional arguments for scriptblock =====
        $positionalArgs = @()
        if ($meta -and $meta.Parameters) {
            foreach ($paramDef in $meta.Parameters) {
                $paramName = $paramDef.Name.ToLower()
                if ($providedParams.ContainsKey($paramName)) {
                    $positionalArgs += $providedParams[$paramName]
                }
                else {
                    $positionalArgs += $null
                }
            }
        }
        else {
            # No metadata, fall back to legacy positional
            if ($providedParams.ContainsKey('param')) { $positionalArgs += $providedParams['param'] }
            elseif ($Param) { $positionalArgs += $Param }
            
            if ($providedParams.ContainsKey('param2')) { $positionalArgs += $providedParams['param2'] }
            elseif ($Param2) { $positionalArgs += $Param2 }
        }
        
        # ===== Execute =====
        Write-Host "[Intent-$intentId] Executing: $Intent" -ForegroundColor Cyan
        $startTime = Get-Date
        
        $scriptBlock = $global:IntentAliases[$Intent]
        $result = & $scriptBlock @positionalArgs
        
        $executionTime = ((Get-Date) - $startTime).TotalSeconds
        
        # ===== Propagate actual success/failure =====
        # Handle case where result might be wrapped in array
        $actualResult = $result
        if ($result -is [array] -and $result.Count -eq 1) {
            $actualResult = $result[0]
        }
        
        # Determine success - try multiple approaches for PS5.1/PS7 compatibility
        $success = $false
        $hasError = $false
        
        if ($null -ne $actualResult) {
            # Method 1: Direct property access (works for most cases)
            try {
                if ($null -ne $actualResult.Success) {
                    $success = [bool]$actualResult.Success
                }
                if ($null -ne $actualResult.Error) {
                    $hasError = [bool]$actualResult.Error
                }
            }
            catch {
                # Method 2: Hashtable key access
                if ($actualResult -is [hashtable]) {
                    if ($actualResult.ContainsKey('Success')) {
                        $success = [bool]$actualResult['Success']
                    }
                    if ($actualResult.ContainsKey('Error')) {
                        $hasError = [bool]$actualResult['Error']
                    }
                }
            }
        }
        
        # Update result reference for return
        $result = $actualResult
        
        $statusColor = if ($success) { 'Green' } else { 'Red' }
        $statusText = if ($success) { 'Completed' } else { 'Failed' }
        Write-Host "[Intent-$intentId] $statusText ($([math]::Round($executionTime, 2))s)" -ForegroundColor $statusColor
        
        # Toast notification for meaningful intents (>1s or always-notify categories)
        if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
            $alwaysNotify = @('document', 'git', 'workflow', 'filesystem')
            $intentCategory = if ($meta) { $meta.Category } else { '' }
            if ($executionTime -gt 1.0 -or $intentCategory -in $alwaysNotify) {
                $toastMsg = if ($result.Output) { $result.Output } else { "Intent: $Intent" }
                if ($toastMsg.Length -gt 80) { $toastMsg = $toastMsg.Substring(0, 80) + '...' }
                if ($success) {
                    Send-ShелixToast -Title $Intent -Message $toastMsg -Type Success
                }
                else {
                    Send-ShелixToast -Title "$Intent failed" -Message $toastMsg -Type Error
                }
            }
        }
        
        return @{
            Success       = $success
            Output        = $result.Output
            IntentId      = $intentId
            ExecutionTime = $executionTime
            Result        = $result
            Error         = $hasError
        }
    }
    catch {
        Write-Host "[Intent-$intentId] Exception: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success   = $false
            Output    = "Exception: $($_.Exception.Message)"
            Error     = $true
            IntentId  = $intentId
            Reason    = "Exception"
            Exception = $_.Exception.Message
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
    param([Parameter(Mandatory = $true)][string]$JsonPayload)
    
    try {
        $payload = $JsonPayload | ConvertFrom-Json
        Invoke-IntentAction -Intent $payload.intent -Param $payload.param -Param2 $payload.param2 -AutoConfirm
    }
    catch {
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
    param([Parameter(Mandatory = $true)][string]$Name)
    
    if ($global:IntentAliases.ContainsKey($Name)) {
        Write-Host "`nIntent: $Name" -ForegroundColor Cyan
        Write-Host "Status: Available" -ForegroundColor Green
        Write-Host "Type: Script Block" -ForegroundColor Gray
        Write-Host ""
    }
    else {
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
        }
        else {
            Write-Host "Unknown category: $Category" -ForegroundColor Red
            Write-Host "Available categories: $($global:IntentCategories.Keys -join ', ')" -ForegroundColor Yellow
            return
        }
    }
    else {
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
            }
            elseif ($global:IntentAliases.ContainsKey($intentName)) {
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
    param([Parameter(Mandatory = $true)][string]$Name)
    
    if (-not $global:IntentAliases.ContainsKey($Name)) {
        Write-Host "Intent '$Name' not found" -ForegroundColor Red
        Write-Host "Available intents: $($global:IntentAliases.Keys -join ', ')" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n===== Intent: $Name =====" -ForegroundColor Cyan

    # Source attribution: plugin or core?
    $source = "core"
    if ($global:LoadedPlugins) {
        foreach ($pName in $global:LoadedPlugins.Keys) {
            if ($global:LoadedPlugins[$pName].Intents -contains $Name) {
                $source = "plugin: $pName"
                break
            }
        }
    }
    Write-Host "Source: $source" -ForegroundColor DarkCyan

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
        }
        else {
            Write-Host "`nParameters: None" -ForegroundColor Gray
        }
        
        # Check if it's a workflow
        if ($meta.Category -eq 'workflow') {
            Write-Host "`nType: Composite/Workflow Intent" -ForegroundColor Magenta
            Write-Host "  This intent chains multiple actions together." -ForegroundColor Gray
        }
    }
    else {
        Write-Host "Status: Available (no metadata)" -ForegroundColor Yellow
    }
    
    Write-Host "`nExample:" -ForegroundColor Yellow
    if ($global:IntentMetadata.ContainsKey($Name) -and $global:IntentMetadata[$Name].Parameters.Count -gt 0) {
        $exampleParams = $global:IntentMetadata[$Name].Parameters | ForEach-Object { "`"$($_.Name)`":`"example`"" }
        Write-Host "  {`"intent`":`"$Name`",$($exampleParams -join ',')}" -ForegroundColor Gray
    }
    else {
        Write-Host "  {`"intent`":`"$Name`"}" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# Alias for quick testing
Set-Alias -Name intent -Value Test-Intent -Force
Set-Alias -Name intent-help -Value Show-IntentHelp -Force

# ===== Multi-Step Workflows =====
# Yes, I wrote this at 3am. No, I don't remember why it works.
$global:Workflows = @{
    "research_and_document" = @{
        Name        = "Research and Document"
        Description = "Research a topic, create a document with findings"
        Steps       = @(
            @{ Intent = "web_search"; ParamMap = @{ query = "topic" } }
            @{ Intent = "create_docx"; ParamMap = @{ name = "topic" }; Transform = { param($topic) "$topic - Research Notes" } }
        )
    }
    "daily_standup"         = @{
        Name        = "Daily Standup"
        Description = "Show calendar and git status for standup"
        Steps       = @(
            @{ Intent = "calendar_today" }
            @{ Intent = "git_status" }
        )
    }
    "project_setup"         = @{
        Name        = "Project Setup"
        Description = "Create folder, initialize git, open in editor"
        Steps       = @(
            @{ Intent = "create_folder"; ParamMap = @{ path = "project" } }
            @{ Intent = "git_init"; ParamMap = @{ path = "project" } }
        )
    }
}

function Invoke-Workflow {
    # This function is smarter than me on most days
    <#
    .SYNOPSIS
    Execute a multi-step workflow by name
    
    .EXAMPLE
    Invoke-Workflow -Name "daily_standup"
    Invoke-Workflow -Name "research_and_document" -Params @{ topic = "PowerShell MCP" }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [hashtable]$Params = @{}
    )
    
    if (-not $global:Workflows.ContainsKey($Name)) {
        Write-Host "Unknown workflow: $Name" -ForegroundColor Red
        Write-Host "Available workflows: $($global:Workflows.Keys -join ', ')" -ForegroundColor Yellow
        return @{ Success = $false; Error = "Unknown workflow" }
    }
    
    $workflow = $global:Workflows[$Name]
    Write-Host "`n===== Workflow: $($workflow.Name) =====" -ForegroundColor Cyan
    Write-Host $workflow.Description -ForegroundColor Gray
    Write-Host ""
    
    $results = @()
    $stepNum = 1
    
    foreach ($step in $workflow.Steps) {
        Write-Host "[$stepNum/$($workflow.Steps.Count)] Running: $($step.Intent)" -ForegroundColor Yellow
        
        # Build parameters for this step as a hashtable for proper multi-arg support
        $stepPayload = @{ intent = $step.Intent }
        if ($step.ParamMap) {
            foreach ($key in $step.ParamMap.Keys) {
                $sourceParam = $step.ParamMap[$key]
                if ($Params.ContainsKey($sourceParam)) {
                    $value = $Params[$sourceParam]
                    # Apply transform if exists
                    if ($step.Transform) {
                        $value = & $step.Transform $value
                    }
                    # Use the target param name (key), not source
                    $stepPayload[$key] = $value
                }
            }
        }
        
        # Execute the intent with full payload for multi-arg support
        try {
            $result = Invoke-IntentAction -Intent $step.Intent -Payload $stepPayload -AutoConfirm
            
            if ($result.Success) {
                Write-Host "  [OK] $($result.Output)" -ForegroundColor Green
            }
            else {
                Write-Host "  [FAIL] $($result.Output)" -ForegroundColor Red
            }
            $results += $result
        }
        catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
            $results += @{ Success = $false; Error = $_.Exception.Message }
        }
        
        $stepNum++
    }
    
    Write-Host "`n===== Workflow Complete =====" -ForegroundColor Cyan
    
    # Toast on workflow completion
    if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
        $allOk = ($results | Where-Object { -not $_.Success }).Count -eq 0
        if ($allOk) {
            Send-ShелixToast -Title "Workflow complete" -Message $WorkflowName -Type Success
        }
        else {
            $failCount = ($results | Where-Object { -not $_.Success }).Count
            Send-ShелixToast -Title "Workflow finished with errors" -Message "$WorkflowName — $failCount step(s) failed" -Type Warning
        }
    }
    
    return @{
        Success = ($results | Where-Object { -not $_.Success }).Count -eq 0
        Results = $results
    }
}

function Get-Workflows {
    <#
    .SYNOPSIS
    List available workflows
    #>
    Write-Host "`n===== Available Workflows =====" -ForegroundColor Cyan
    foreach ($name in $global:Workflows.Keys | Sort-Object) {
        $wf = $global:Workflows[$name]
        Write-Host "`n$name" -ForegroundColor Yellow
        Write-Host "  $($wf.Description)" -ForegroundColor Gray
        Write-Host "  Steps: $($wf.Steps.Count)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

Set-Alias workflow Invoke-Workflow -Force
Set-Alias workflows Get-Workflows -Force

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

Write-Host "Shelix loaded. Run 'intent-help' for usage." -ForegroundColor Green
