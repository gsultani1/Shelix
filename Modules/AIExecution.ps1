# ===== AIExecution.ps1 =====
# AI command execution gateway with safety validation, rate limiting, and logging

# ===== Execution Logging Configuration =====
$global:AIExecutionLog = @()
$global:MaxExecutionsPerMessage = 3
$global:ExecutionLogPath = "$env:USERPROFILE\Documents\ChatLogs\AIExecutionLog.json"

# ===== Session Tracking for Audit Trail =====
$global:SessionId = [guid]::NewGuid().ToString().Substring(0,12)
$global:SessionStartTime = Get-Date
$global:UserId = $env:USERNAME
$global:ComputerName = $env:COMPUTERNAME

# ===== Rate Limiting Configuration =====
$global:RateLimitWindow = 60  # seconds
$global:MaxExecutionsPerWindow = 10
$global:ExecutionTimestamps = @()

# ===== Undo/Rollback Tracking =====
$global:FileOperationHistory = @()
$global:MaxUndoHistory = 50

# ===== Rate Limiting Functions =====
function Test-RateLimit {
    <#
    .SYNOPSIS
    Check if execution is within rate limits
    #>
    $now = Get-Date
    $windowStart = $now.AddSeconds(-$global:RateLimitWindow)
    
    # Clean old timestamps
    $validTimestamps = New-Object System.Collections.ArrayList
    foreach ($ts in $global:ExecutionTimestamps) {
        if ($ts -gt $windowStart) {
            [void]$validTimestamps.Add($ts)
        }
    }
    $global:ExecutionTimestamps = @($validTimestamps)
    
    # Check if under limit
    if ($global:ExecutionTimestamps.Count -ge $global:MaxExecutionsPerWindow) {
        $sortedTs = $global:ExecutionTimestamps | Sort-Object
        $oldestInWindow = $sortedTs[0]
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

# ===== File Operation Tracking (Undo) =====
function Add-FileOperation {
    <#
    .SYNOPSIS
    Track a file operation for potential undo
    #>
    param(
        [string]$Operation,  # Create, Copy, Move, Delete
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
    
    # Trim history if too large
    if ($global:FileOperationHistory.Count -gt $global:MaxUndoHistory) {
        $global:FileOperationHistory = $global:FileOperationHistory[-$global:MaxUndoHistory..-1]
    }
    
    return $entry.Id
}

function Undo-LastFileOperation {
    <#
    .SYNOPSIS
    Undo the last file operation if possible
    #>
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
    <#
    .SYNOPSIS
    View recent file operations that can be undone
    #>
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

function Get-SessionInfo {
    <#
    .SYNOPSIS
    Display current session information for audit purposes
    #>
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

# ===== Main AI Execution Gateway =====
function Invoke-AIExec {
    <#
    .SYNOPSIS
    Universal AI command execution gateway with safety validation and logging
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [string]$RequestSource = "AI",
        [switch]$AutoConfirm,
        [switch]$DryRun
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $executionId = [guid]::NewGuid().ToString().Substring(0,8)
    
    # Log the attempt with full audit trail
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
        # Step 0: Check rate limit
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
        
        # Step 1: Validate command is in safe actions list
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
        
        # Step 2: Handle confirmation for non-read-only commands
        if ($validation.SafetyLevel -ne 'ReadOnly' -and -not $AutoConfirm -and -not $DryRun) {
            Write-Host "  [AIExec-$executionId] Command requires confirmation" -ForegroundColor Yellow
            $confirmed = Show-CommandConfirmation $Command $validation.SafetyLevel $validation.Description
            $logEntry.Confirmed = $confirmed
            
            if (-not $confirmed) {
                $logEntry.Status = "Cancelled"
                $logEntry.Error = "User cancelled execution"
                $global:AIExecutionLog += $logEntry
                
                Write-Host " [AIExec-$executionId] Execution cancelled by user" -ForegroundColor Yellow
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
        
        # Step 3: Execute command (or simulate for dry run)
        if ($DryRun) {
            Write-Host " [AIExec-$executionId] DRY RUN - Would execute: $Command" -ForegroundColor Magenta
            $logEntry.Status = "DryRun"
            $logEntry.Output = "Dry run completed - command would be executed"
            $global:AIExecutionLog += $logEntry
            
            return @{
                Success = $true
                Output = "DRY RUN: Command '$Command' would be executed"
                Error = $false
                ExecutionId = $executionId
                DryRun = $true
            }
        }
        
        Write-Host " [AIExec-$executionId] Executing command..." -ForegroundColor Cyan
        $startTime = Get-Date
        
        # Execute directly with error handling
        try {
            $output = Invoke-Expression $Command 2>&1 | Out-String
            $executionTime = ((Get-Date) - $startTime).TotalSeconds
            
            $logEntry.Status = "Success"
            $logEntry.Output = $output.Trim()
            $logEntry.ExecutionTime = $executionTime
            $global:AIExecutionLog += $logEntry
            
            # Record execution for rate limiting
            Add-ExecutionTimestamp
            
            Write-Host " [AIExec-$executionId] Command completed successfully ($([math]::Round($executionTime, 2))s)" -ForegroundColor Green
            
            return @{
                Success = $true
                Output = $output.Trim()
                Error = $false
                ExecutionId = $executionId
                ExecutionTime = $executionTime
            }
        }
        catch {
            $executionTime = ((Get-Date) - $startTime).TotalSeconds
            $errorMsg = $_.Exception.Message
            
            $logEntry.Status = "ExecutionError"
            $logEntry.Error = $errorMsg
            $logEntry.ExecutionTime = $executionTime
            $global:AIExecutionLog += $logEntry
            
            Write-Host " [AIExec-$executionId] Command error: $errorMsg" -ForegroundColor Red
            
            return @{
                Success = $false
                Output = "Error: $errorMsg"
                Error = $true
                ExecutionId = $executionId
            }
        }
        
    } catch {
        $logEntry.Status = "Error"
        $logEntry.Error = $_.Exception.Message
        if ($startTime) {
            $logEntry.ExecutionTime = ((Get-Date) - $startTime).TotalSeconds
        }
        $global:AIExecutionLog += $logEntry
        
        Write-Host " [AIExec-$executionId] Execution failed: $($_.Exception.Message)" -ForegroundColor Red
        
        return @{
            Success = $false
            Output = "Error: $($_.Exception.Message)"
            Error = $true
            ExecutionId = $executionId
        }
    } finally {
        # Save execution log to disk
        Save-AIExecutionLog
    }
}

function Save-AIExecutionLog {
    try {
        $logDir = Split-Path $global:ExecutionLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        # Keep only last 1000 entries to prevent log bloat
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
    <#
    .SYNOPSIS
    View AI execution log
    #>
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
        
        if ($_.Output -and $_.Output.Length -gt 0) {
            $truncatedOutput = if ($_.Output.Length -gt 100) { $_.Output.Substring(0, 100) + "..." } else { $_.Output }
            Write-Host "    Output: $truncatedOutput" -ForegroundColor DarkGray
        }
        
        if ($_.Error) {
            Write-Host "    Error: $($_.Error)" -ForegroundColor Red
        }
        
        if ($_.ExecutionTime -gt 0) {
            Write-Host "    Time: $([math]::Round($_.ExecutionTime, 2))s" -ForegroundColor DarkCyan
        }
        
        Write-Host ""
    }
}

# ===== Load existing execution log on startup =====
if (Test-Path $global:ExecutionLogPath) {
    try {
        $global:AIExecutionLog = Get-Content $global:ExecutionLogPath -Raw | ConvertFrom-Json
        if (-not $global:AIExecutionLog) { $global:AIExecutionLog = @() }
    } catch {
        $global:AIExecutionLog = @()
    }
}

# ===== Aliases =====
Set-Alias undo Undo-LastFileOperation -Force
Set-Alias file-history Get-FileOperationHistory -Force
Set-Alias session-info Get-SessionInfo -Force
Set-Alias ai-exec Invoke-AIExec -Force
Set-Alias exec-log Get-AIExecutionLog -Force

Write-Verbose "AIExecution loaded: Invoke-AIExec, Get-AIExecutionLog, Undo-LastFileOperation, Get-SessionInfo"
