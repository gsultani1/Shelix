# ===== IntentRegistry.ps1 =====
# Intent metadata, category definitions, and registry initialization.
# This file is loaded FIRST by IntentAliasSystem.ps1 — all other intent
# files depend on the globals defined here.

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
    'agent'      = @{ Name = 'Agent'; Description = 'Autonomous multi-step task execution' }
    'vision'     = @{ Name = 'Vision'; Description = 'Image analysis and screenshot capture' }
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
    'browser_tab'               = @{
        Category    = 'web'
        Description = 'Get the URL and title of the active browser tab'
        Parameters  = @()
    }
    'browser_content'           = @{
        Category    = 'web'
        Description = 'Fetch the page content from the active browser tab'
        Parameters  = @()
    }
    # Code Artifacts
    'save_code'                 = @{
        Category    = 'file'
        Description = 'Save AI-generated code to a file'
        Parameters  = @(
            @{ Name = 'code'; Required = $true; Description = 'The code to save' }
            @{ Name = 'filename'; Required = $false; Description = 'Output filename (auto-generated if omitted)' }
            @{ Name = 'language'; Required = $false; Description = 'Language hint (python, powershell, js, etc.)' }
        )
    }
    'run_code'                  = @{
        Category    = 'system'
        Description = 'Execute AI-generated code (saves to temp file and runs)'
        Safety      = 'RequiresConfirmation'
        Parameters  = @(
            @{ Name = 'code'; Required = $true; Description = 'The code to execute' }
            @{ Name = 'language'; Required = $true; Description = 'Language (powershell, python, js, bash, etc.)' }
            @{ Name = 'filename'; Required = $false; Description = 'Also save to this filename' }
        )
    }
    'list_artifacts'            = @{
        Category    = 'file'
        Description = 'List saved code artifacts'
        Parameters  = @()
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
        Description = 'List BildsyPS-managed scheduled workflows'
        Parameters  = @(
            @{ Name = 'filter'; Required = $false; Description = 'Filter by workflow name' }
        )
    }
    'list_workflows'            = @{ Category = 'workflow'; Description = 'List available workflows'; Parameters = @() }
    'agent_task'                = @{
        Category    = 'agent'
        Description = 'Run an autonomous agent to complete a multi-step task'
        Parameters  = @(
            @{ Name = 'task'; Required = $true; Description = 'Natural language task description' }
        )
    }
    
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
    'analyze_image'             = @{
        Category    = 'vision'
        Description = 'Analyze an image file using a vision-capable LLM'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Path to image file (png, jpg, gif, webp, bmp)' }
            @{ Name = 'prompt'; Required = $false; Description = 'What to ask about the image (default: describe it)' }
            @{ Name = 'full'; Required = $false; Description = 'Set to true to skip resize (for dense text/spreadsheets)' }
        )
    }
    'screenshot'                = @{
        Category    = 'vision'
        Description = 'Capture a screenshot and analyze it with a vision model'
        Parameters  = @(
            @{ Name = 'prompt'; Required = $false; Description = 'What to ask about the screen (default: describe it)' }
            @{ Name = 'full'; Required = $false; Description = 'Set to true to send at full resolution' }
        )
    }
    'ocr_file'                  = @{
        Category    = 'vision'
        Description = 'Extract text from an image or PDF using Tesseract OCR'
        Parameters  = @(
            @{ Name = 'path'; Required = $true; Description = 'Path to image or PDF file' }
            @{ Name = 'language'; Required = $false; Description = 'Tesseract language code (default: eng)' }
        )
    }
    'build_app'                 = @{
        Category    = 'productivity'
        Description = 'Build a standalone .exe from a natural language app description'
        Parameters  = @(
            @{ Name = 'prompt'; Required = $true; Description = 'Natural language description of the app' }
            @{ Name = 'framework'; Required = $false; Description = 'powershell (default), python-tk, python-web' }
            @{ Name = 'name'; Required = $false; Description = 'App name for the executable' }
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

Write-Verbose "IntentRegistry loaded: $($global:IntentMetadata.Count) intent definitions, $($global:CategoryDefinitions.Count) categories"
