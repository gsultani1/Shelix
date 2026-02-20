# ===== AgentHeartbeat.Tests.ps1 =====
# Critical path 4: heartbeat evaluating and executing a scheduled task

BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"
    # Point heartbeat to temp paths
    $global:HeartbeatTasksPath = Join-Path $global:TestTempRoot 'config\agent-tasks.json'
    $global:HeartbeatLogPath = Join-Path $global:TestTempRoot 'logs\heartbeat.log'
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'AgentHeartbeat — Offline' {

    Context 'Task CRUD' {
        It 'Get-AgentTaskList returns empty array when no file exists' {
            if (Test-Path $global:HeartbeatTasksPath) { Remove-Item $global:HeartbeatTasksPath -Force }
            $tasks = Get-AgentTaskList
            $tasks.Count | Should -Be 0
        }

        It 'Add-AgentTask creates a task entry' {
            Add-AgentTask -Id 'test-daily' -Task 'summarize git changes' -Schedule 'daily' -Time '09:00'
            $tasks = Get-AgentTaskList
            $tasks.Count | Should -Be 1
            $tasks[0].id | Should -Be 'test-daily'
            $tasks[0].schedule | Should -Be 'daily'
            $tasks[0].time | Should -Be '09:00'
            $tasks[0].enabled | Should -BeTrue
            $tasks[0].lastRun | Should -BeNullOrEmpty
        }

        It 'Rejects duplicate task ID' {
            # Should warn but not crash
            Add-AgentTask -Id 'test-daily' -Task 'duplicate' -Schedule 'daily' -Time '10:00'
            $tasks = Get-AgentTaskList
            $tasks.Count | Should -Be 1
        }

        It 'Add-AgentTask adds a second task' {
            Add-AgentTask -Id 'test-interval' -Task 'check disk space' -Schedule 'interval' -Interval '30m'
            $tasks = Get-AgentTaskList
            $tasks.Count | Should -Be 2
        }

        It 'Disable-AgentTask sets enabled to false' {
            Disable-AgentTask -Id 'test-daily'
            $tasks = Get-AgentTaskList
            $target = $tasks | Where-Object { $_.id -eq 'test-daily' }
            $target.enabled | Should -BeFalse
        }

        It 'Enable-AgentTask sets enabled back to true' {
            Enable-AgentTask -Id 'test-daily'
            $tasks = Get-AgentTaskList
            $target = $tasks | Where-Object { $_.id -eq 'test-daily' }
            $target.enabled | Should -BeTrue
        }

        It 'Remove-AgentTask removes by ID' {
            Remove-AgentTask -Id 'test-interval'
            $tasks = Get-AgentTaskList
            $tasks.Count | Should -Be 1
            ($tasks | Where-Object { $_.id -eq 'test-interval' }) | Should -BeNullOrEmpty
        }

        It 'Show-AgentTaskList does not throw' {
            { Show-AgentTaskList } | Should -Not -Throw
        }
    }

    Context 'Test-TaskDue Schedule Logic' {
        It 'Daily task with null lastRun is due' {
            $task = [pscustomobject]@{ enabled = $true; schedule = 'daily'; time = '00:00'; lastRun = $null }
            Test-TaskDue -Task $task | Should -BeTrue
        }

        It 'Daily task run today is not due' {
            $task = [pscustomobject]@{ enabled = $true; schedule = 'daily'; time = '00:00'; lastRun = (Get-Date).ToString('o') }
            Test-TaskDue -Task $task | Should -BeFalse
        }

        It 'Daily task run yesterday with past target time is due' {
            $yesterday = (Get-Date).AddDays(-1).ToString('o')
            $task = [pscustomobject]@{ enabled = $true; schedule = 'daily'; time = '00:01'; lastRun = $yesterday }
            Test-TaskDue -Task $task | Should -BeTrue
        }

        It 'Interval task 30m with lastRun 45m ago is due' {
            $old = (Get-Date).AddMinutes(-45).ToString('o')
            $task = [pscustomobject]@{ enabled = $true; schedule = 'interval'; interval = '30m'; lastRun = $old }
            Test-TaskDue -Task $task | Should -BeTrue
        }

        It 'Interval task 30m with lastRun 10m ago is not due' {
            $recent = (Get-Date).AddMinutes(-10).ToString('o')
            $task = [pscustomobject]@{ enabled = $true; schedule = 'interval'; interval = '30m'; lastRun = $recent }
            Test-TaskDue -Task $task | Should -BeFalse
        }

        It 'Interval task with null lastRun is due' {
            $task = [pscustomobject]@{ enabled = $true; schedule = 'interval'; interval = '1h'; lastRun = $null }
            Test-TaskDue -Task $task | Should -BeTrue
        }

        It 'Weekly task on wrong day is not due (after first run)' {
            $today = (Get-Date).DayOfWeek.ToString().Substring(0, 3)
            # Pick a day that is NOT today
            $allDays = @('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
            $wrongDay = $allDays | Where-Object { $_ -ne $today } | Select-Object -First 1
            # Set lastRun to yesterday so the "never run" early-return doesn't trigger
            $yesterday = (Get-Date).AddDays(-1).ToString('o')
            $task = [pscustomobject]@{ enabled = $true; schedule = 'weekly'; time = '00:01'; days = $wrongDay; lastRun = $yesterday }
            Test-TaskDue -Task $task | Should -BeFalse
        }

        It 'Disabled task is never due' {
            $task = [pscustomobject]@{ enabled = $false; schedule = 'daily'; time = '00:00'; lastRun = $null }
            Test-TaskDue -Task $task | Should -BeFalse
        }
    }
}

Describe 'AgentHeartbeat — Live' -Tag 'Live' {

    Context 'Invoke-AgentHeartbeat' {
        BeforeAll {
            $script:HasProvider = $false
            if ($global:ChatProviders -and $global:DefaultChatProvider) {
                $cfg = $global:ChatProviders[$global:DefaultChatProvider]
                if ($cfg) { $script:HasProvider = $true }
            }
            # Reset task file for live test
            $global:HeartbeatTasksPath = Join-Path $global:TestTempRoot 'config\agent-tasks-live.json'
            $global:HeartbeatLogPath = Join-Path $global:TestTempRoot 'logs\heartbeat-live.log'
        }

        It 'Executes a forced heartbeat with a simple task' -Skip:(-not $script:HasProvider) {
            Add-AgentTask -Id 'live-math' -Task 'What is 2+2? Use the calculator tool.' -Schedule 'daily' -Time '00:00'
            $result = Invoke-AgentHeartbeat -Force
            $result.TasksChecked | Should -BeGreaterOrEqual 1
            $result.TasksRun | Should -BeGreaterOrEqual 1

            $tasks = Get-AgentTaskList
            $ran = $tasks | Where-Object { $_.id -eq 'live-math' }
            $ran.lastRun | Should -Not -BeNullOrEmpty
            $ran.lastResult | Should -Not -BeNullOrEmpty
        }

        It 'Heartbeat log file is written' -Skip:(-not $script:HasProvider) {
            Test-Path $global:HeartbeatLogPath | Should -BeTrue
            $content = Get-Content $global:HeartbeatLogPath -Raw
            $content | Should -Match 'Heartbeat check'
        }
    }
}

Describe 'AgentHeartbeat — Admin' -Tag 'Admin' {

    Context 'Scheduled Task Registration' {
        It 'Register-AgentHeartbeat creates a scheduled task' {
            $result = Register-AgentHeartbeat -IntervalMinutes 60
            $result.Success | Should -BeTrue
            $task = Get-ScheduledTask -TaskName 'Heartbeat' -TaskPath '\BildsyPS\' -ErrorAction SilentlyContinue
            $task | Should -Not -BeNullOrEmpty
        }

        It 'Unregister-AgentHeartbeat removes the scheduled task' {
            $result = Unregister-AgentHeartbeat
            $result.Success | Should -BeTrue
            $task = Get-ScheduledTask -TaskName 'Heartbeat' -TaskPath '\BildsyPS\' -ErrorAction SilentlyContinue
            $task | Should -BeNullOrEmpty
        }
    }
}
