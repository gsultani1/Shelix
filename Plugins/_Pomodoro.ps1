# ============= _Pomodoro.ps1 — BildsyPS Pomodoro Timer Plugin =============
# A productivity timer based on the Pomodoro Technique.
# Tracks work sessions and breaks using in-memory state.
#
# Enable with: Enable-BildsyPSPlugin 'Pomodoro'
# Configure:   Set-PluginConfig -Plugin Pomodoro -Key work_minutes -Value 30

$PluginInfo = @{
    Version          = '1.0.0'
    Author           = 'BildsyPS'
    Description      = 'Pomodoro technique timer — focus sessions with timed breaks'
    MinBildsyPSVersion = '0.9.0'
}

$PluginCategories = @{
    'productivity' = @{
        Name        = 'Productivity'
        Description = 'Focus timers and productivity tools'
    }
}

$PluginConfig = @{
    'work_minutes' = @{
        Default     = 25
        Description = 'Duration of a work session in minutes'
    }
    'break_minutes' = @{
        Default     = 5
        Description = 'Duration of a short break in minutes'
    }
    'long_break_minutes' = @{
        Default     = 15
        Description = 'Duration of a long break (every 4 sessions) in minutes'
    }
}

$PluginMetadata = @{
    'pomodoro_start' = @{
        Category    = 'productivity'
        Description = 'Start a new Pomodoro work session'
        Parameters  = @(
            @{ Name = 'label'; Required = $false; Description = 'What you are working on' }
        )
    }
    'pomodoro_status' = @{
        Category    = 'productivity'
        Description = 'Check current Pomodoro timer status'
        Parameters  = @()
    }
    'pomodoro_stop' = @{
        Category    = 'productivity'
        Description = 'Stop the current Pomodoro session'
        Parameters  = @()
    }
    'pomodoro_history' = @{
        Category    = 'productivity'
        Description = 'Show completed Pomodoro sessions today'
        Parameters  = @()
    }
}

$PluginIntents = @{
    'pomodoro_start' = {
        param($label)
        if (-not $label) { $label = 'Focus session' }

        $cfg = $global:PluginSettings['Pomodoro']
        $workMin = if ($cfg) { $cfg['work_minutes'] } else { 25 }

        # Check if one is already running
        if ($global:_PomodoroState -and $global:_PomodoroState.Active) {
            $elapsed = [math]::Round(((Get-Date) - $global:_PomodoroState.StartedAt).TotalMinutes, 1)
            return @{
                Success = $false
                Output  = "A session is already running: '$($global:_PomodoroState.Label)' ($elapsed min elapsed). Stop it first."
                Error   = $true
            }
        }

        $global:_PomodoroState = @{
            Active    = $true
            Label     = $label
            StartedAt = Get-Date
            Duration  = $workMin
            Type      = 'work'
        }

        @{ Success = $true; Output = "Pomodoro started: '$label' ($workMin min). Stay focused!" }
    }

    'pomodoro_status' = {
        if (-not $global:_PomodoroState -or -not $global:_PomodoroState.Active) {
            return @{ Success = $true; Output = 'No active Pomodoro session. Start one with pomodoro_start.' }
        }

        $s = $global:_PomodoroState
        $elapsed = (Get-Date) - $s.StartedAt
        $remaining = $s.Duration - $elapsed.TotalMinutes

        if ($remaining -le 0) {
            # Session complete
            $s.Active = $false
            if (-not $global:_PomodoroHistory) { $global:_PomodoroHistory = @() }
            $global:_PomodoroHistory += @{
                Label      = $s.Label
                StartedAt  = $s.StartedAt
                Duration   = $s.Duration
                FinishedAt = Get-Date
            }

            $cfg = $global:PluginSettings['Pomodoro']
            $sessionsToday = @($global:_PomodoroHistory | Where-Object {
                $_.FinishedAt.Date -eq (Get-Date).Date
            }).Count
            $breakMin = if ($sessionsToday % 4 -eq 0) {
                if ($cfg) { $cfg['long_break_minutes'] } else { 15 }
            } else {
                if ($cfg) { $cfg['break_minutes'] } else { 5 }
            }
            $breakType = if ($sessionsToday % 4 -eq 0) { 'long break' } else { 'short break' }

            # Toast if available
            if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
                Send-ShелixToast -Title 'Pomodoro Complete' -Message "$($s.Label) — take a $breakType ($breakMin min)" -Type Success
            }

            return @{
                Success = $true
                Output  = "Session '$($s.Label)' complete! Sessions today: $sessionsToday. Take a $breakType ($breakMin min)."
            }
        }

        $remainStr = [math]::Round($remaining, 1)
        $elapsedStr = [math]::Round($elapsed.TotalMinutes, 1)
        @{ Success = $true; Output = "Working on '$($s.Label)' — $elapsedStr min elapsed, $remainStr min remaining." }
    }

    'pomodoro_stop' = {
        if (-not $global:_PomodoroState -or -not $global:_PomodoroState.Active) {
            return @{ Success = $true; Output = 'No active session to stop.' }
        }

        $s = $global:_PomodoroState
        $elapsed = [math]::Round(((Get-Date) - $s.StartedAt).TotalMinutes, 1)
        $s.Active = $false

        @{ Success = $true; Output = "Stopped '$($s.Label)' after $elapsed min." }
    }

    'pomodoro_history' = {
        if (-not $global:_PomodoroHistory -or $global:_PomodoroHistory.Count -eq 0) {
            return @{ Success = $true; Output = 'No completed sessions yet.' }
        }

        $today = @($global:_PomodoroHistory | Where-Object {
            $_.FinishedAt.Date -eq (Get-Date).Date
        })

        if ($today.Count -eq 0) {
            return @{ Success = $true; Output = 'No sessions completed today.' }
        }

        $totalMin = ($today | Measure-Object -Property Duration -Sum).Sum
        $lines = @("Today: $($today.Count) session(s), $totalMin min total")
        foreach ($s in $today) {
            $time = $s.StartedAt.ToString('HH:mm')
            $lines += "  $time — $($s.Label) ($($s.Duration) min)"
        }

        @{ Success = $true; Output = ($lines -join "`n") }
    }
}

$PluginFunctions = @{
    'Get-PomodoroState' = {
        return $global:_PomodoroState
    }
}

$PluginHooks = @{
    OnLoad = {
        if (-not $global:_PomodoroState) {
            $global:_PomodoroState = @{ Active = $false }
        }
        if (-not $global:_PomodoroHistory) {
            $global:_PomodoroHistory = @()
        }
    }
    OnUnload = {
        # Preserve history but clear active state
        if ($global:_PomodoroState) {
            $global:_PomodoroState.Active = $false
        }
    }
}

$PluginTests = @{
    'start creates active session' = {
        $oldState = $global:_PomodoroState
        $global:_PomodoroState = @{ Active = $false }
        $r = & $global:IntentAliases['pomodoro_start'] 'Test task'
        $isActive = $global:_PomodoroState.Active
        $global:_PomodoroState = $oldState
        @{ Success = ($r.Success -and $isActive); Output = $r.Output }
    }
    'status reports when idle' = {
        $oldState = $global:_PomodoroState
        $global:_PomodoroState = @{ Active = $false }
        $r = & $global:IntentAliases['pomodoro_status']
        $global:_PomodoroState = $oldState
        @{ Success = ($r.Output -like '*No active*'); Output = $r.Output }
    }
    'stop clears active session' = {
        $oldState = $global:_PomodoroState
        $global:_PomodoroState = @{ Active = $true; Label = 'Test'; StartedAt = (Get-Date); Duration = 25; Type = 'work' }
        $r = & $global:IntentAliases['pomodoro_stop']
        $stopped = -not $global:_PomodoroState.Active
        $global:_PomodoroState = $oldState
        @{ Success = ($r.Success -and $stopped); Output = $r.Output }
    }
}
