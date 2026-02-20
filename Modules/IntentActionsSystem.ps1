# ===== IntentActionsSystem.ps1 =====
# System-level, filesystem, composite, and workflow intent scriptblocks.
# Adds to $global:IntentAliases — loaded after IntentActions.ps1.

$global:IntentAliases += @{
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
    
    # ===== Agent =====
    "agent_task"                = {
        param($task)
        if (-not $task) {
            return @{ Success = $false; Output = "Error: task parameter required"; Error = $true }
        }
        if (Get-Command Invoke-AgentTask -ErrorAction SilentlyContinue) {
            $result = Invoke-AgentTask -Task $task -AutoConfirm
            return @{ Success = $result.Success; Output = $result.Summary }
        }
        else {
            return @{ Success = $false; Output = "Agent module not loaded"; Error = $true }
        }
    }
    
}

Write-Verbose "IntentActionsSystem loaded: apps, workflows, system, filesystem, agent intents added"
