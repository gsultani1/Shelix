# ===== SafetySystem.ps1 =====
# AI execution safety, rate limiting, audit trails, and undo capability

# ===== Session Tracking for Audit Trail =====
$global:SessionId = [guid]::NewGuid().ToString().Substring(0,12)
$global:SessionStartTime = Get-Date
$global:UserId = $env:USERNAME
$global:ComputerName = $env:COMPUTERNAME

# ===== Execution Logging =====
$global:AIExecutionLog = @()
$global:MaxExecutionsPerMessage = 3
$global:ExecutionLogPath = "$env:USERPROFILE\Documents\ChatLogs\AIExecutionLog.json"

# ===== Rate Limiting Configuration =====
$global:RateLimitWindow = 60  # seconds
$global:MaxExecutionsPerWindow = 10
$global:ExecutionTimestamps = @()

# ===== Undo/Rollback Tracking =====
$global:FileOperationHistory = @()
$global:MaxUndoHistory = 50

# ===== Command Safety Classifications =====
$global:CommandSafety = @{
    'ReadOnly' = @(
        # System Info
        'get-computerinfo', 'get-process', 'get-service', 'get-hotfix', 'get-eventlog',
        'get-wmiobject', 'get-ciminstance', 'get-date', 'get-uptime', 'get-timezone',
        # File System (read)
        'get-childitem', 'get-item', 'get-itemproperty', 'get-content', 'test-path',
        'resolve-path', 'get-location', 'get-psdrive', 'measure-object', 'select-string',
        'get-acl', 'get-filehash',
        # Network
        'test-netconnection', 'get-netadapter', 'get-netipaddress', 'get-netroute',
        'resolve-dnsname', 'test-connection', 'get-nettcpconnection',
        # Text Processing
        'convertto-json', 'convertfrom-json', 'convertto-csv', 'convertfrom-csv', 'convertto-xml',
        'format-table', 'format-list', 'sort-object', 'group-object', 'where-object', 'select-object',
        'out-string', 'convertto-html',
        # Math/Utility
        'measure-command', 'get-random', 'get-unique',
        # Environment
        'get-variable', 'get-alias', 'get-command', 'get-module', 'get-pssnapin',
        'get-executionpolicy', 'get-host', 'get-culture', 'get-history',
        # Help
        'get-help', 'get-member', 'compare-object',
        # Navigation (safe - just changes directory)
        'set-location', 'push-location', 'pop-location'
    )
    'SafeWrite' = @(
        # File creation/writing (non-destructive)
        'new-item', 'new-temporaryfile', 'out-file', 'export-csv', 'export-clixml',
        'add-content', 'set-content', 'tee-object',
        # Clipboard
        'set-clipboard', 'get-clipboard'
    )
    'RequiresConfirmation' = @(
        # File operations (potentially destructive)
        'copy-item', 'move-item', 'rename-item', 'remove-item',
        # Archives
        'compress-archive', 'expand-archive',
        # Execution
        'invoke-expression', 'invoke-command', 'start-process', 'start-job',
        # Environment modification
        'set-variable', 'set-item', 'set-itemproperty', 'clear-item', 'clear-content'
    )
}

$global:Actions = @{
    'SystemInfo' = @{
        'get-computerinfo' = 'Get detailed computer information'
        'get-process' = 'List running processes'
        'get-service' = 'List system services'
        'get-hotfix' = 'List installed updates'
        'get-eventlog' = 'Read event logs (specify -LogName)'
        'get-wmiobject' = 'Query WMI objects (read-only)'
        'get-ciminstance' = 'Query CIM instances (read-only)'
        'get-date' = 'Get current date and time'
        'get-uptime' = 'Get system uptime'
        'get-timezone' = 'Get system timezone'
        'get-history' = 'Get command history'
    }
    'FileSystem' = @{
        'get-childitem' = 'List directory contents'
        'get-item' = 'Get file/directory information'
        'get-itemproperty' = 'Get file/directory properties'
        'get-content' = 'Read file contents'
        'test-path' = 'Test if path exists'
        'resolve-path' = 'Resolve path to absolute'
        'get-location' = 'Get current directory'
        'get-psdrive' = 'List available drives'
        'measure-object' = 'Measure file/object properties'
        'select-string' = 'Search text in files'
        'get-acl' = 'Get file/directory permissions'
        'get-filehash' = 'Calculate file hash'
    }
    'Navigation' = @{
        'set-location' = 'Change current directory'
        'push-location' = 'Push directory onto stack'
        'pop-location' = 'Pop directory from stack'
    }
    'FileOperations' = @{
        'new-item' = 'Create new file or directory'
        'copy-item' = 'Copy files or directories'
        'move-item' = 'Move files or directories'
        'rename-item' = 'Rename file or directory'
        'remove-item' = 'Delete file or directory (requires confirmation)'
        'add-content' = 'Append content to file'
        'set-content' = 'Write content to file'
        'clear-content' = 'Clear file contents'
    }
    'Network' = @{
        'test-netconnection' = 'Test network connectivity'
        'get-netadapter' = 'Get network adapters'
        'get-netipaddress' = 'Get IP addresses'
        'get-netroute' = 'Get routing table'
        'resolve-dnsname' = 'Resolve DNS names'
        'test-connection' = 'Ping hosts'
        'get-nettcpconnection' = 'Get TCP connections'
    }
    'TextProcessing' = @{
        'convertto-json' = 'Convert objects to JSON'
        'convertfrom-json' = 'Parse JSON to objects'
        'convertto-csv' = 'Convert objects to CSV'
        'convertfrom-csv' = 'Parse CSV to objects'
        'convertto-xml' = 'Convert objects to XML'
        'convertto-html' = 'Convert objects to HTML'
        'format-table' = 'Format output as table'
        'format-list' = 'Format output as list'
        'sort-object' = 'Sort objects'
        'group-object' = 'Group objects'
        'where-object' = 'Filter objects'
        'select-object' = 'Select object properties'
        'out-string' = 'Convert output to string'
        'get-unique' = 'Get unique items'
        'tee-object' = 'Split output to file and pipeline'
    }
    'Math' = @{
        'measure-command' = 'Measure command execution time'
        'get-random' = 'Generate random numbers'
        'get-date' = 'Date calculations'
    }
    'Environment' = @{
        'get-variable' = 'Get PowerShell variables'
        'set-variable' = 'Set PowerShell variable'
        'get-alias' = 'Get command aliases'
        'get-command' = 'Get available commands'
        'get-module' = 'Get loaded modules'
        'get-pssnapin' = 'Get PowerShell snap-ins'
        'get-executionpolicy' = 'Get execution policy'
        'get-host' = 'Get PowerShell host info'
        'get-culture' = 'Get system culture'
        'get-clipboard' = 'Get clipboard contents'
        'set-clipboard' = 'Set clipboard contents'
    }
    'Archives' = @{
        'compress-archive' = 'Create ZIP archives'
        'expand-archive' = 'Extract ZIP archives'
    }
    'Output' = @{
        'out-file' = 'Write to file'
        'export-csv' = 'Export to CSV file'
        'export-clixml' = 'Export to XML file'
        'new-temporaryfile' = 'Create temporary file'
    }
    'Registry' = @{
        'get-itemproperty' = 'Read registry values'
        'get-childitem' = 'List registry keys'
        'test-path' = 'Test registry path exists'
    }
    'PowerShell' = @{
        'get-help' = 'Get command help'
        'get-member' = 'Get object members'
        'measure-object' = 'Measure object properties'
        'compare-object' = 'Compare objects'
        'invoke-expression' = 'Execute PowerShell expressions (use carefully)'
        'invoke-command' = 'Execute commands (local only)'
    }
    'ApplicationLaunch' = @{
        'start-process' = 'Launch applications and executables'
    }
}

# ===== Rate Limiting Functions =====
function Test-RateLimit {
    $now = Get-Date
    $windowStart = $now.AddSeconds(-$global:RateLimitWindow)
    
    $global:ExecutionTimestamps = $global:ExecutionTimestamps | Where-Object { $_ -gt $windowStart }
    
    if ($global:ExecutionTimestamps.Count -ge $global:MaxExecutionsPerWindow) {
        $oldestInWindow = $global:ExecutionTimestamps | Sort-Object | Select-Object -First 1
        $waitTime = [math]::Ceiling(($oldestInWindow.AddSeconds($global:RateLimitWindow) - $now).TotalSeconds)
        return @{
            Allowed = $false
            Message = "Rate limit exceeded. $($global:ExecutionTimestamps.Count) executions in last $global:RateLimitWindow seconds. Wait $waitTime seconds."
            WaitSeconds = $waitTime
        }
    }
    
    return @{ Allowed = $true }
}

function Add-ExecutionTimestamp {
    $global:ExecutionTimestamps += Get-Date
}

# ===== Command Validation =====
function Get-CommandSafetyLevel {
    param([string]$Command)
    $baseCommand = ($Command -split '\s+')[0].ToLower()
    
    foreach ($level in $global:CommandSafety.Keys) {
        if ($global:CommandSafety[$level] -contains $baseCommand) {
            return $level
        }
    }
    return 'Unknown'
}

function Test-PowerShellCommand {
    param([string]$Command)
    $baseCommand = ($Command -split '\s+')[0].ToLower()
    
    foreach ($category in $global:Actions.Keys) {
        if ($global:Actions[$category].ContainsKey($baseCommand)) {
            $safetyLevel = Get-CommandSafetyLevel $baseCommand
            return @{
                IsValid = $true
                Category = $category
                Description = $global:Actions[$category][$baseCommand]
                Command = $baseCommand
                SafetyLevel = $safetyLevel
            }
        }
    }
    
    return @{
        IsValid = $false
        Command = $baseCommand
        SafetyLevel = 'Unknown'
    }
}

function Show-CommandConfirmation {
    param([string]$Command, [string]$SafetyLevel, [string]$Description)
    
    switch ($SafetyLevel) {
        'SafeWrite' {
            Write-Host "`nSAFE WRITE OPERATION" -ForegroundColor Yellow
            Write-Host "Command: $Command" -ForegroundColor White
            Write-Host "Description: $Description" -ForegroundColor Gray
            
            do {
                $response = Read-Host "Proceed? (y/n)"
            } while ($response -notin @('y', 'n', 'yes', 'no'))
            
            return $response -in @('y', 'yes')
        }
        'RequiresConfirmation' {
            Write-Host "`nCONFIRMATION REQUIRED" -ForegroundColor Red
            Write-Host "Command: $Command" -ForegroundColor White
            Write-Host "Description: $Description" -ForegroundColor Gray
            Write-Host "This command can modify system state or execute code." -ForegroundColor Yellow
            
            do {
                $response = Read-Host "Are you sure you want to proceed? (yes/no)"
            } while ($response -notin @('yes', 'no'))
            
            return $response -eq 'yes'
        }
        default {
            return $true
        }
    }
}

# ===== File Operation Tracking (Undo) =====
function Add-FileOperation {
    param(
        [string]$Operation,
        [string]$Path,
        [string]$OriginalPath = $null,
        [string]$BackupPath = $null,
        [string]$ExecutionId
    )
    
    $entry = @{
        Id = [guid]::NewGuid().ToString().Substring(0,8)
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SessionId = $global:SessionId
        UserId = $global:UserId
        Operation = $Operation
        Path = $Path
        OriginalPath = $OriginalPath
        BackupPath = $BackupPath
        ExecutionId = $ExecutionId
        Undone = $false
    }
    
    $global:FileOperationHistory += $entry
    
    if ($global:FileOperationHistory.Count -gt $global:MaxUndoHistory) {
        $global:FileOperationHistory = $global:FileOperationHistory[-$global:MaxUndoHistory..-1]
    }
    
    return $entry.Id
}

function Undo-LastFileOperation {
    param([int]$Count = 1)
    
    $undoable = $global:FileOperationHistory | Where-Object { -not $_.Undone } | Select-Object -Last $Count
    
    if ($undoable.Count -eq 0) {
        Write-Host "No operations to undo." -ForegroundColor Yellow
        return @{ Success = $false; Message = "No operations to undo" }
    }
    
    $results = @()
    foreach ($op in $undoable) {
        Write-Host "Undoing: $($op.Operation) - $($op.Path)" -ForegroundColor Cyan
        
        try {
            switch ($op.Operation) {
                'Create' {
                    if (Test-Path $op.Path) {
                        Remove-Item $op.Path -Force
                        Write-Host "  Deleted created file: $($op.Path)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    } else {
                        Write-Host "  File no longer exists: $($op.Path)" -ForegroundColor Yellow
                        $results += @{ Success = $false; Operation = $op; Message = "File not found" }
                    }
                }
                'Copy' {
                    if (Test-Path $op.Path) {
                        Remove-Item $op.Path -Force
                        Write-Host "  Deleted copied file: $($op.Path)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    }
                }
                'Move' {
                    if ((Test-Path $op.Path) -and $op.OriginalPath) {
                        Move-Item $op.Path $op.OriginalPath -Force
                        Write-Host "  Moved back to: $($op.OriginalPath)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    }
                }
                'Delete' {
                    if ($op.BackupPath -and (Test-Path $op.BackupPath)) {
                        Copy-Item $op.BackupPath $op.Path -Force
                        Write-Host "  Restored from backup: $($op.Path)" -ForegroundColor Green
                        $op.Undone = $true
                        $results += @{ Success = $true; Operation = $op }
                    } else {
                        Write-Host "  Cannot restore - no backup available" -ForegroundColor Red
                        $results += @{ Success = $false; Operation = $op; Message = "No backup" }
                    }
                }
                default {
                    Write-Host "  Unknown operation type: $($op.Operation)" -ForegroundColor Yellow
                    $results += @{ Success = $false; Operation = $op; Message = "Unknown operation" }
                }
            }
        } catch {
            Write-Host "  Undo failed: $($_.Exception.Message)" -ForegroundColor Red
            $results += @{ Success = $false; Operation = $op; Message = $_.Exception.Message }
        }
    }
    
    return $results
}

function Get-FileOperationHistory {
    param(
        [int]$Last = 10,
        [switch]$ShowAll
    )
    
    $ops = if ($ShowAll) { $global:FileOperationHistory } else { $global:FileOperationHistory | Select-Object -Last $Last }
    
    if ($ops.Count -eq 0) {
        Write-Host "No file operations recorded." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n===== File Operation History =====" -ForegroundColor Cyan
    foreach ($op in $ops) {
        $statusColor = if ($op.Undone) { 'DarkGray' } else { 'White' }
        $undoStatus = if ($op.Undone) { "[UNDONE]" } else { "" }
        Write-Host "[$($op.Timestamp)] $($op.Operation.PadRight(8)) $undoStatus" -ForegroundColor $statusColor -NoNewline
        Write-Host " $($op.Path)" -ForegroundColor Gray
    }
    Write-Host "=================================`n" -ForegroundColor Cyan
}

# ===== Session Info =====
function Get-SessionInfo {
    $duration = (Get-Date) - $global:SessionStartTime
    
    Write-Host "`n===== Session Information =====" -ForegroundColor Cyan
    Write-Host "  Session ID: $($global:SessionId)" -ForegroundColor White
    Write-Host "  User: $($global:UserId)@$($global:ComputerName)" -ForegroundColor White
    Write-Host "  Started: $($global:SessionStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Duration: $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor White
    Write-Host "  Executions this session: $($global:AIExecutionLog.Count)" -ForegroundColor White
    Write-Host "  File operations tracked: $($global:FileOperationHistory.Count)" -ForegroundColor White
    Write-Host "================================`n" -ForegroundColor Cyan
}

# ===== AI Execution Dispatcher =====
function Invoke-AIExec {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [string]$RequestSource = "AI",
        [switch]$AutoConfirm,
        [switch]$DryRun
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $executionId = [guid]::NewGuid().ToString().Substring(0,8)
    
    $logEntry = @{
        Id = $executionId
        Timestamp = $timestamp
        SessionId = $global:SessionId
        UserId = $global:UserId
        ComputerName = $global:ComputerName
        Source = $RequestSource
        Command = $Command
        Status = "Attempted"
        Output = ""
        Error = $null
        Confirmed = $false
        ExecutionTime = 0
    }
    
    try {
        # Rate limit check
        $rateCheck = Test-RateLimit
        if (-not $rateCheck.Allowed) {
            $logEntry.Status = "RateLimited"
            $logEntry.Error = $rateCheck.Message
            $global:AIExecutionLog += $logEntry
            
            Write-Host "[AIExec-$executionId] RATE LIMITED: $($rateCheck.Message)" -ForegroundColor Red
            return @{
                Success = $false
                Output = $rateCheck.Message
                Error = $true
                ExecutionId = $executionId
                RateLimited = $true
            }
        }
        
        # Validate command
        Write-Host "[AIExec-$executionId] Validating command: $Command" -ForegroundColor DarkCyan
        $validation = Test-PowerShellCommand $Command
        
        if (-not $validation.IsValid) {
            $logEntry.Status = "Rejected"
            $logEntry.Error = "Command not in safe actions list"
            $global:AIExecutionLog += $logEntry
            
            Write-Host "[AIExec-$executionId] REJECTED: Command '$Command' is not in the safe actions list" -ForegroundColor Red
            return @{
                Success = $false
                Output = "Command '$Command' is not in the safe actions list"
                Error = $true
                ExecutionId = $executionId
            }
        }
        
        Write-Host "[AIExec-$executionId] Command validated: $($validation.Category) - $($validation.SafetyLevel)" -ForegroundColor Green
        
        # Confirmation
        if ($validation.SafetyLevel -ne 'ReadOnly' -and -not $AutoConfirm -and -not $DryRun) {
            Write-Host "  [AIExec-$executionId] Command requires confirmation" -ForegroundColor Yellow
            $confirmed = Show-CommandConfirmation $Command $validation.SafetyLevel $validation.Description
            $logEntry.Confirmed = $confirmed
            
            if (-not $confirmed) {
                $logEntry.Status = "Cancelled"
                $logEntry.Error = "User cancelled execution"
                $global:AIExecutionLog += $logEntry
                
                Write-Host "[AIExec-$executionId] Execution cancelled by user" -ForegroundColor Yellow
                return @{
                    Success = $false
                    Output = "Command execution cancelled by user"
                    Error = $false
                    ExecutionId = $executionId
                }
            }
        } else {
            $logEntry.Confirmed = $true
        }
        
        # Dry run
        if ($DryRun) {
            Write-Host "[AIExec-$executionId] DRY RUN - Would execute: $Command" -ForegroundColor Magenta
            $logEntry.Status = "DryRun"
            $logEntry.Output = "Dry run completed"
            $global:AIExecutionLog += $logEntry
            
            return @{
                Success = $true
                Output = "DRY RUN: Command '$Command' would be executed"
                Error = $false
                ExecutionId = $executionId
                DryRun = $true
            }
        }
        
        # Execute
        Write-Host "[AIExec-$executionId] Executing command..." -ForegroundColor Cyan
        $startTime = Get-Date
        
        # Lazy-load ThreadJob on first use
        if (Get-Command Enable-ThreadJob -ErrorAction SilentlyContinue) {
            Enable-ThreadJob
        } elseif (-not (Get-Module ThreadJob)) {
            Import-Module ThreadJob -ErrorAction SilentlyContinue
        }
        
        $job = Start-ThreadJob -ScriptBlock { param($cmd) Invoke-Expression $cmd } -ArgumentList $Command
        $completed = Wait-Job $job -Timeout 30
        
        if ($completed) {
            $output = Receive-Job $job | Out-String
            $executionTime = ((Get-Date) - $startTime).TotalSeconds
            Remove-Job $job
            
            $logEntry.Status = "Success"
            $logEntry.Output = $output.Trim()
            $logEntry.ExecutionTime = $executionTime
            $global:AIExecutionLog += $logEntry
            
            Add-ExecutionTimestamp
            
            Write-Host "[AIExec-$executionId] Command completed ($([math]::Round($executionTime, 2))s)" -ForegroundColor Green
            
            return @{
                Success = $true
                Output = $output.Trim()
                Error = $false
                ExecutionId = $executionId
                ExecutionTime = $executionTime
            }
        } else {
            Stop-Job $job
            Remove-Job $job
            
            $logEntry.Status = "Timeout"
            $logEntry.Error = "Command execution timed out (30s limit)"
            $logEntry.ExecutionTime = 30
            $global:AIExecutionLog += $logEntry
            
            Write-Host "[AIExec-$executionId] Command timed out (30s limit)" -ForegroundColor Red
            
            return @{
                Success = $false
                Output = "Command execution timed out (30 second limit)"
                Error = $true
                ExecutionId = $executionId
            }
        }
        
    } catch {
        $logEntry.Status = "Error"
        $logEntry.Error = $_.Exception.Message
        $global:AIExecutionLog += $logEntry
        
        Write-Host "[AIExec-$executionId] Execution failed: $($_.Exception.Message)" -ForegroundColor Red
        
        return @{
            Success = $false
            Output = "Error: $($_.Exception.Message)"
            Error = $true
            ExecutionId = $executionId
        }
    } finally {
        Save-AIExecutionLog
    }
}

function Save-AIExecutionLog {
    try {
        $logDir = Split-Path $global:ExecutionLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        if ($global:AIExecutionLog.Count -gt 1000) {
            $global:AIExecutionLog = $global:AIExecutionLog[-1000..-1]
        }
        
        $jsonContent = $global:AIExecutionLog | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($global:ExecutionLogPath, $jsonContent, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Host "Warning: Failed to save execution log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-AIExecutionLog {
    param(
        [int]$Last = 10,
        [string]$Status = "",
        [switch]$ShowAll
    )
    
    $logs = $global:AIExecutionLog
    
    if ($Status) {
        $logs = $logs | Where-Object { $_.Status -eq $Status }
    }
    
    if (-not $ShowAll) {
        $logs = $logs | Select-Object -Last $Last
    }
    
    $logs | ForEach-Object {
        $statusColor = switch ($_.Status) {
            'Success' { 'Green' }
            'Error' { 'Red' }
            'Timeout' { 'Yellow' }
            'Rejected' { 'Red' }
            'Cancelled' { 'Yellow' }
            'DryRun' { 'Magenta' }
            default { 'Gray' }
        }
        
        Write-Host "[$($_.Timestamp)] [$($_.Id)] " -ForegroundColor Gray -NoNewline
        Write-Host $_.Status -ForegroundColor $statusColor -NoNewline
        Write-Host " - $($_.Command)" -ForegroundColor White
    }
}

# Load existing log on startup
if (Test-Path $global:ExecutionLogPath) {
    try {
        $global:AIExecutionLog = Get-Content $global:ExecutionLogPath -Raw | ConvertFrom-Json
        if (-not $global:AIExecutionLog) { $global:AIExecutionLog = @() }
    } catch {
        $global:AIExecutionLog = @()
    }
}

# ===== Safe Actions Helper =====
function Get-SafeActions {
    param(
        [string]$Category = '',
        [string]$Command = ''
    )
    
    if ($Command) {
        foreach ($cat in $global:Actions.Keys) {
            if ($global:Actions[$cat].ContainsKey($Command.ToLower())) {
                return @{
                    Category = $cat
                    Command = $Command.ToLower()
                    Description = $global:Actions[$cat][$Command.ToLower()]
                }
            }
        }
        Write-Host "Command '$Command' not found in safe actions" -ForegroundColor Yellow
        return $null
    }
    
    if ($Category) {
        if ($global:Actions.ContainsKey($Category)) {
            Write-Host "`n===== $Category Commands =====" -ForegroundColor Cyan
            $global:Actions[$Category].GetEnumerator() | Sort-Object Key | ForEach-Object {
                Write-Host "  $($_.Key)" -ForegroundColor Green -NoNewline
                Write-Host " - $($_.Value)" -ForegroundColor Gray
            }
            Write-Host ""
        } else {
            Write-Host "Category '$Category' not found" -ForegroundColor Red
        }
    } else {
        Write-Host "`n===== Safe Actions Categories =====" -ForegroundColor Cyan
        $global:Actions.Keys | Sort-Object | ForEach-Object {
            $count = $global:Actions[$_].Count
            Write-Host "  $_" -ForegroundColor Green -NoNewline
            Write-Host " ($count commands)" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

function Test-SafeAction {
    param([Parameter(Mandatory=$true)][string]$Command)
    
    $validation = Test-PowerShellCommand $Command
    if ($validation.IsValid) {
        Write-Host "'$Command' is a safe action ($($validation.SafetyLevel))" -ForegroundColor Green
        Write-Host "   Category: $($validation.Category)" -ForegroundColor Gray
        Write-Host "   Description: $($validation.Description)" -ForegroundColor Gray
        return $true
    } else {
        Write-Host "'$Command' is not in the safe actions list" -ForegroundColor Red
        return $false
    }
}

function Invoke-SafeAction {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [switch]$Force
    )
    
    $validation = Test-PowerShellCommand $Command
    
    if (-not $validation.IsValid) {
        Write-Host "Command '$Command' is not in the safe actions list" -ForegroundColor Red
        return $false
    }
    
    if (-not $Force -and $validation.SafetyLevel -ne 'ReadOnly') {
        $confirmed = Show-CommandConfirmation $Command $validation.SafetyLevel $validation.Description
        if (-not $confirmed) {
            Write-Host "Command execution cancelled." -ForegroundColor Yellow
            return $false
        }
    }
    
    try {
        Write-Host "Executing: $Command" -ForegroundColor Cyan
        Invoke-Expression $Command
        Write-Host "Command completed." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ===== Aliases =====
Set-Alias undo Undo-LastFileOperation -Force
Set-Alias file-history Get-FileOperationHistory -Force
Set-Alias session-info Get-SessionInfo -Force
Set-Alias actions Get-SafeActions -Force
Set-Alias safe-check Test-SafeAction -Force
Set-Alias safe-run Invoke-SafeAction -Force
Set-Alias ai-exec Invoke-AIExec -Force
Set-Alias exec-log Get-AIExecutionLog -Force
