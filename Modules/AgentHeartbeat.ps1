# ===== AgentHeartbeat.ps1 =====
# Cron-triggered autonomous agent tasks via Windows Task Scheduler.
# The scheduled task polls every 15 minutes; this module evaluates which tasks are due.

$global:HeartbeatTasksPath = "$global:BildsyPSHome\config\agent-tasks.json"
$global:HeartbeatLogPath = "$global:BildsyPSHome\logs\heartbeat.log"
$global:HeartbeatDefaultInterval = 15  # minutes between polls

# ===== Task List Management =====

function Get-AgentTaskList {
    <#
    .SYNOPSIS
    Load and return all heartbeat tasks from the JSON task list.
    #>
    if (-not (Test-Path $global:HeartbeatTasksPath)) { return @() }
    try {
        $raw = Get-Content $global:HeartbeatTasksPath -Raw | ConvertFrom-Json
        if ($raw -is [array]) { return $raw } else { return @($raw) }
    }
    catch {
        Write-Host "HeartbeatError: Failed to parse agent-tasks.json -- $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Save-AgentTaskList {
    <#
    .SYNOPSIS
    Save the task list back to JSON.
    #>
    param([Parameter(Mandatory)][array]$Tasks)
    $dir = Split-Path $global:HeartbeatTasksPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Tasks | ConvertTo-Json -Depth 5 | Set-Content $global:HeartbeatTasksPath -Encoding UTF8
}

function Add-AgentTask {
    <#
    .SYNOPSIS
    Add a new task to the heartbeat task list.
    #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Task,
        [ValidateSet('daily','weekly','interval')][string]$Schedule = 'daily',
        [string]$Time = '08:00',
        [string]$Interval,
        [string]$Days
    )

    $tasks = @(Get-AgentTaskList)
    if ($tasks | Where-Object { $_.id -eq $Id }) {
        Write-Host "Task '$Id' already exists. Use Remove-AgentTask first." -ForegroundColor Yellow
        return
    }

    $newTask = [ordered]@{
        id         = $Id
        schedule   = $Schedule
        time       = $Time
        task       = $Task
        enabled    = $true
        lastRun    = $null
        lastResult = $null
    }
    if ($Interval) { $newTask.interval = $Interval }
    if ($Days) { $newTask.days = $Days }

    $tasks += [pscustomobject]$newTask
    Save-AgentTaskList -Tasks $tasks
    Write-Host "Added heartbeat task '$Id' ($Schedule at $Time)" -ForegroundColor Green
}

function Remove-AgentTask {
    <#
    .SYNOPSIS
    Remove a task from the heartbeat list by ID.
    #>
    param([Parameter(Mandatory)][string]$Id)
    $tasks = @(Get-AgentTaskList)
    $filtered = @($tasks | Where-Object { $_.id -ne $Id })
    if ($filtered.Count -eq $tasks.Count) {
        Write-Host "Task '$Id' not found." -ForegroundColor Yellow
        return
    }
    Save-AgentTaskList -Tasks $filtered
    Write-Host "Removed heartbeat task '$Id'" -ForegroundColor Green
}

function Enable-AgentTask {
    param([Parameter(Mandatory)][string]$Id)
    $tasks = @(Get-AgentTaskList)
    $target = $tasks | Where-Object { $_.id -eq $Id }
    if (-not $target) { Write-Host "Task '$Id' not found." -ForegroundColor Yellow; return }
    $target.enabled = $true
    Save-AgentTaskList -Tasks $tasks
    Write-Host "Enabled heartbeat task '$Id'" -ForegroundColor Green
}

function Disable-AgentTask {
    param([Parameter(Mandatory)][string]$Id)
    $tasks = @(Get-AgentTaskList)
    $target = $tasks | Where-Object { $_.id -eq $Id }
    if (-not $target) { Write-Host "Task '$Id' not found." -ForegroundColor Yellow; return }
    $target.enabled = $false
    Save-AgentTaskList -Tasks $tasks
    Write-Host "Disabled heartbeat task '$Id'" -ForegroundColor Green
}

function Show-AgentTaskList {
    <#
    .SYNOPSIS
    Display all heartbeat tasks with their status.
    #>
    $tasks = Get-AgentTaskList
    if ($tasks.Count -eq 0) {
        Write-Host "No heartbeat tasks configured." -ForegroundColor DarkGray
        Write-Host "  Use: Add-AgentTask -Id 'my-task' -Task 'description' -Schedule daily -Time '08:00'" -ForegroundColor DarkGray
        return
    }

    Write-Host "`n===== Agent Heartbeat Tasks =====" -ForegroundColor Cyan
    foreach ($t in $tasks) {
        $state = if ($t.enabled) { '[ON] ' } else { '[OFF]' }
        $stateColor = if ($t.enabled) { 'Green' } else { 'DarkGray' }
        $schedInfo = "$($t.schedule)"
        if ($t.time) { $schedInfo += " at $($t.time)" }
        if ($t.interval) { $schedInfo += " every $($t.interval)" }
        if ($t.days) { $schedInfo += " on $($t.days)" }
        $lastInfo = if ($t.lastRun) { "Last: $($t.lastRun)" } else { 'Never run' }

        Write-Host "  $state " -ForegroundColor $stateColor -NoNewline
        Write-Host "$($t.id) " -ForegroundColor Yellow -NoNewline
        Write-Host "-- $schedInfo" -ForegroundColor DarkGray
        Write-Host "        $($t.task)" -ForegroundColor Gray
        Write-Host "        $lastInfo" -ForegroundColor DarkGray
        if ($t.lastResult) {
            $resultPreview = "$($t.lastResult)"
            if ($resultPreview.Length -gt 80) { $resultPreview = $resultPreview.Substring(0, 80) + '...' }
            Write-Host "        Result: $resultPreview" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

# ===== Schedule Logic =====

function Test-TaskDue {
    <#
    .SYNOPSIS
    Determine if a task is due for execution based on its schedule and lastRun.
    #>
    param([Parameter(Mandatory)][psobject]$Task)

    if (-not $Task.enabled) { return $false }

    $now = Get-Date
    $lastRun = if ($Task.lastRun) { try { [datetime]::Parse($Task.lastRun) } catch { $null } } else { $null }

    switch ($Task.schedule) {
        'daily' {
            if (-not $lastRun) { return $true }
            $targetTime = [datetime]::Parse($Task.time)
            $todayTarget = $now.Date.Add($targetTime.TimeOfDay)
            # Due if: we haven't run today AND current time is past the target time
            return ($lastRun.Date -lt $now.Date -and $now -ge $todayTarget)
        }
        'weekly' {
            if (-not $lastRun) { return $true }
            $dayNames = if ($Task.days) { $Task.days -split ',' | ForEach-Object { $_.Trim() } } else { @('Monday') }
            $todayName = $now.DayOfWeek.ToString().Substring(0, 3)
            if ($todayName -notin $dayNames) { return $false }
            $targetTime = [datetime]::Parse($Task.time)
            $todayTarget = $now.Date.Add($targetTime.TimeOfDay)
            return ($lastRun.Date -lt $now.Date -and $now -ge $todayTarget)
        }
        'interval' {
            if (-not $lastRun) { return $true }
            $intervalStr = $Task.interval
            $timespan = $null
            if ($intervalStr -match '^(\d+)([hms])$') {
                $val = [int]$Matches[1]
                $unit = $Matches[2]
                if ($unit -eq 'h') { $timespan = New-TimeSpan -Hours $val }
                elseif ($unit -eq 'm') { $timespan = New-TimeSpan -Minutes $val }
                elseif ($unit -eq 's') { $timespan = New-TimeSpan -Seconds $val }
            }
            if (-not $timespan) { return $false }
            return (($now - $lastRun) -ge $timespan)
        }
        default { return $false }
    }
}

# ===== Heartbeat Execution =====

function Invoke-AgentHeartbeat {
    <#
    .SYNOPSIS
    Main heartbeat entry point. Load task list, run due tasks via Invoke-AgentTask, log results.
    Called by the scheduled task bootstrap script.
    #>
    param([switch]$Force)

    $tasks = @(Get-AgentTaskList)
    if ($tasks.Count -eq 0) { return }

    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Heartbeat check: $($tasks.Count) task(s)"
    $ran = 0

    foreach ($task in $tasks) {
        $isDue = if ($Force) { $task.enabled } else { Test-TaskDue -Task $task }
        if (-not $isDue) { continue }

        $logEntry += "`n  Running: $($task.id) -- $($task.task)"

        try {
            if (Get-Command Invoke-AgentTask -ErrorAction SilentlyContinue) {
                $result = Invoke-AgentTask -Task $task.task -MaxSteps 10
                $summary = if ($result.Summary) { $result.Summary } else { "Completed ($($result.StepCount) steps)" }
                $task.lastResult = $summary
            }
            else {
                $task.lastResult = "AgentLoop not available"
            }
        }
        catch {
            $task.lastResult = "Error: $($_.Exception.Message)"
        }

        $task.lastRun = (Get-Date -Format 'o')
        $logEntry += "`n    Result: $($task.lastResult)"
        $ran++
    }

    # Save updated task list with lastRun/lastResult
    if ($ran -gt 0) {
        Save-AgentTaskList -Tasks $tasks
    }

    $logEntry += "`n  Executed: $ran task(s)"

    # Append to log file
    $logDir = Split-Path $global:HeartbeatLogPath -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logEntry | Out-File $global:HeartbeatLogPath -Append -Encoding UTF8

    # Store in SQLite if available
    if ($global:ChatDbReady -and (Get-Command Get-ChatDbConnection -ErrorAction SilentlyContinue)) {
        try {
            $conn = Get-ChatDbConnection
            $cmd = $conn.CreateCommand()
            # Create heartbeat_runs table if not exists
            $cmd.CommandText = "CREATE TABLE IF NOT EXISTS heartbeat_runs (id INTEGER PRIMARY KEY AUTOINCREMENT, run_at TEXT NOT NULL DEFAULT (datetime('now')), tasks_checked INTEGER, tasks_run INTEGER, log TEXT)"
            $cmd.ExecuteNonQuery() | Out-Null
            $cmd.CommandText = "INSERT INTO heartbeat_runs (tasks_checked, tasks_run, log) VALUES (@checked, @ran, @log)"
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@checked", $tasks.Count)) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@ran", $ran)) | Out-Null
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@log", $logEntry)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
            $cmd.Dispose()
            $conn.Close()
            $conn.Dispose()
        }
        catch {
            # Non-fatal: log file is the primary record
        }
    }

    if ($ran -gt 0) {
        Write-Host "[Heartbeat] Executed $ran task(s)." -ForegroundColor Cyan
    }

    return @{ TasksChecked = $tasks.Count; TasksRun = $ran }
}

# ===== Scheduled Task Registration =====

function Register-AgentHeartbeat {
    <#
    .SYNOPSIS
    Register a Windows Scheduled Task that runs the heartbeat every N minutes.
    #>
    param(
        [int]$IntervalMinutes = $global:HeartbeatDefaultInterval
    )

    $pwshPath = (Get-Process -Id $PID).Path
    $modulesPath = $global:ModulesPath
    $bildsypsHome = $global:BildsyPSHome

    # Generate bootstrap script
    $scriptsDir = "$global:BildsyPSHome\data"
    if (-not (Test-Path $scriptsDir)) { New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null }
    $scriptPath = Join-Path $scriptsDir "heartbeat_bootstrap.ps1"

    $scriptContent = @"
# Auto-generated by BildsyPS Register-AgentHeartbeat -- do not edit
# Interval: ${IntervalMinutes}m | Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
`$ErrorActionPreference = 'Stop'
`$errorLog = '$bildsypsHome\logs\heartbeat_errors.log'
try {
    `$global:BildsyPSHome = '$bildsypsHome'
    `$global:ModulesPath = '$modulesPath'

    # Load core modules in dependency order
    `$coreModules = @(
        'ConfigLoader.ps1', 'PlatformUtils.ps1', 'SecurityUtils.ps1',
        'CommandValidation.ps1', 'SafetySystem.ps1', 'NaturalLanguage.ps1',
        'ResponseParser.ps1', 'ChatStorage.ps1'
    )
    foreach (`$mod in `$coreModules) {
        `$p = Join-Path `$global:ModulesPath `$mod
        if (Test-Path `$p) { . `$p }
    }

    # Load intent system + agent
    . (Join-Path `$global:ModulesPath 'IntentAliasSystem.ps1')
    . (Join-Path `$global:ModulesPath 'ChatProviders.ps1')

    # Load heartbeat module itself
    . (Join-Path `$global:ModulesPath 'AgentHeartbeat.ps1')

    Invoke-AgentHeartbeat
} catch {
    "[`$(Get-Date)] HEARTBEAT ERROR: `$(`$_.Exception.Message)" | Out-File `$errorLog -Append
    "`$(`$_.ScriptStackTrace)" | Out-File `$errorLog -Append
}
"@
    Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8

    # Create scheduled task
    try {
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
        $action = New-ScheduledTaskAction -Execute $pwshPath -Argument "-WindowStyle Hidden -NonInteractive -File `"$scriptPath`""
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName 'Heartbeat' -TaskPath '\BildsyPS' `
            -Trigger $trigger -Action $action -Settings $settings `
            -Description "BildsyPS agent heartbeat (every ${IntervalMinutes}m)" `
            -Force | Out-Null

        Write-Host "[Heartbeat] Registered scheduled task: \BildsyPS\Heartbeat (every ${IntervalMinutes}m)" -ForegroundColor Green
        Write-Host "  Bootstrap: $scriptPath" -ForegroundColor DarkGray
        return @{ Success = $true; Output = "Heartbeat registered (every ${IntervalMinutes}m)" }
    }
    catch {
        Write-Host "[Heartbeat] Failed to register task: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; Output = "Registration failed: $($_.Exception.Message)" }
    }
}

function Unregister-AgentHeartbeat {
    <#
    .SYNOPSIS
    Remove the heartbeat scheduled task.
    #>
    try {
        Unregister-ScheduledTask -TaskName 'Heartbeat' -TaskPath '\BildsyPS' -Confirm:$false -ErrorAction Stop
        Write-Host "[Heartbeat] Unregistered scheduled task." -ForegroundColor Green

        # Clean up bootstrap script
        $scriptPath = "$global:BildsyPSHome\data\heartbeat_bootstrap.ps1"
        if (Test-Path $scriptPath) { Remove-Item $scriptPath -Force }

        return @{ Success = $true; Output = "Heartbeat unregistered" }
    }
    catch {
        Write-Host "[Heartbeat] $($_.Exception.Message)" -ForegroundColor Yellow
        return @{ Success = $false; Output = $_.Exception.Message }
    }
}

function Get-HeartbeatStatus {
    <#
    .SYNOPSIS
    Show heartbeat scheduled task status and recent log entries.
    #>
    # Check if scheduled task exists
    try {
        $task = Get-ScheduledTask -TaskName 'Heartbeat' -TaskPath '\BildsyPS\' -ErrorAction Stop
        $taskInfo = Get-ScheduledTaskInfo -TaskName 'Heartbeat' -TaskPath '\BildsyPS\'
        Write-Host "`n===== Heartbeat Status =====" -ForegroundColor Cyan
        Write-Host "  Scheduled Task: Active" -ForegroundColor Green
        Write-Host "  State: $($task.State)" -ForegroundColor $(if ($task.State -eq 'Ready') { 'Green' } else { 'Yellow' })
        if ($taskInfo.LastRunTime -and $taskInfo.LastRunTime.Year -gt 2000) {
            Write-Host "  Last Run: $($taskInfo.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "`n===== Heartbeat Status =====" -ForegroundColor Cyan
        Write-Host "  Scheduled Task: Not registered" -ForegroundColor DarkGray
        Write-Host "  Use: Register-AgentHeartbeat to enable" -ForegroundColor DarkGray
    }

    # Show tasks
    Show-AgentTaskList

    # Show recent log
    if (Test-Path $global:HeartbeatLogPath) {
        $recentLog = Get-Content $global:HeartbeatLogPath -Tail 10 -ErrorAction SilentlyContinue
        if ($recentLog) {
            Write-Host "--- Recent Log ---" -ForegroundColor DarkGray
            $recentLog | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            Write-Host ""
        }
    }
}

# ===== Aliases =====
Set-Alias heartbeat Get-HeartbeatStatus -Force
Set-Alias heartbeat-tasks Show-AgentTaskList -Force

Write-Verbose "AgentHeartbeat loaded: Invoke-AgentHeartbeat, Register/Unregister-AgentHeartbeat, Add/Remove/Enable/Disable-AgentTask"
