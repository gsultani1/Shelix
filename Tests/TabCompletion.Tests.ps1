# ===== TabCompletion.Tests.ps1 =====
# Validates that all Register-ArgumentCompleter calls are wired up correctly.
# Uses [System.Management.Automation.CommandCompletion]::CompleteInput to invoke completers.

BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"

    # Load additional modules not covered by bootstrap
    . "$global:ModulesPath\MCPClient.ps1"
    . "$global:ModulesPath\PersistentAliases.ps1"
    . "$global:ModulesPath\NavigationUtils.ps1"

    # UserSkills loads after IntentAliasSystem (already loaded by bootstrap)
    . "$global:ModulesPath\UserSkills.ps1"

    # ChatSession depends on ChatStorage (loaded by bootstrap)
    . "$global:ModulesPath\ChatSession.ps1"

    # Helper: invoke tab completion on a partial command string and return results
    function Get-TabCompletionResults {
        param([string]$InputScript, [int]$CursorIndex = $InputScript.Length)
        $result = [System.Management.Automation.CommandCompletion]::CompleteInput(
            $InputScript, $CursorIndex, $null
        )
        return $result.CompletionMatches
    }
}

AfterAll {
    Remove-TestTempRoot
}

# =============================================================================
# ChatProviders.ps1 completers
# =============================================================================
Describe 'Tab Completion — ChatProviders' {

    It 'Set-DefaultChatProvider -Provider completes provider names' {
        $results = Get-TabCompletionResults 'Set-DefaultChatProvider -Provider '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'ollama'
        $results.CompletionText | Should -Contain 'anthropic'
    }

    It 'Get-ChatModels -Provider completes provider names' {
        $results = Get-TabCompletionResults 'Get-ChatModels -Provider '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'ollama'
    }

    It 'Test-ChatProvider -Provider completes provider names' {
        $results = Get-TabCompletionResults 'Test-ChatProvider -Provider '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'ollama'
    }

    It 'Filters by prefix' {
        $results = Get-TabCompletionResults 'Set-DefaultChatProvider -Provider ol'
        $results.Count | Should -Be 1
        $results[0].CompletionText | Should -Be 'ollama'
    }
}

# =============================================================================
# ChatSession.ps1 completers
# =============================================================================
Describe 'Tab Completion — ChatSession' {

    Context 'Provider completers' {
        It 'Start-ChatSession -Provider completes provider names' {
            $results = Get-TabCompletionResults 'Start-ChatSession -Provider '
            $results.Count | Should -BeGreaterThan 0
            $results.CompletionText | Should -Contain 'ollama'
        }

        It 'chat -Provider completes provider names' {
            $results = Get-TabCompletionResults 'chat -Provider '
            $results.Count | Should -BeGreaterThan 0
            $results.CompletionText | Should -Contain 'anthropic'
        }
    }

    Context 'Session name completers' {
        BeforeAll {
            # Seed a session into the JSON index so the completer has data
            $script:testSessionName = "test-session-$(Get-Random)"
            $global:ChatSessionHistory = @(
                @{ role = 'user'; content = 'hello' }
                @{ role = 'assistant'; content = 'hi' }
            )
            $global:ChatSessionName = $script:testSessionName
            Save-Chat -Name $script:testSessionName
        }

        It 'Resume-Chat -Name completes session names' {
            $results = Get-TabCompletionResults 'Resume-Chat -Name '
            $results.Count | Should -BeGreaterThan 0
            $names = $results | ForEach-Object { $_.CompletionText.Trim("'") }
            $names | Should -Contain $script:testSessionName
        }

        It 'Remove-ChatSession -Name completes session names' {
            $results = Get-TabCompletionResults 'Remove-ChatSession -Name '
            $results.Count | Should -BeGreaterThan 0
        }

        It 'Export-ChatSession -Name completes session names' {
            $results = Get-TabCompletionResults 'Export-ChatSession -Name '
            $results.Count | Should -BeGreaterThan 0
        }
    }
}

# =============================================================================
# UserSkills.ps1 completers
# =============================================================================
Describe 'Tab Completion — UserSkills' {

    BeforeAll {
        # Seed a skill
        $global:LoadedUserSkills['test_skill'] = @{ Name = 'test_skill'; Description = 'A test skill' }
    }

    It 'Invoke-UserSkill -Name completes skill names' {
        $results = Get-TabCompletionResults 'Invoke-UserSkill -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'test_skill'
    }

    It 'Remove-UserSkill -Name completes skill names' {
        $results = Get-TabCompletionResults 'Remove-UserSkill -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'test_skill'
    }

    It 'Filters by prefix' {
        $results = Get-TabCompletionResults 'Invoke-UserSkill -Name test_'
        $results.Count | Should -Be 1
        $results[0].CompletionText | Should -Be 'test_skill'
    }

    AfterAll {
        $global:LoadedUserSkills.Remove('test_skill')
    }
}

# =============================================================================
# WorkflowEngine.ps1 completers
# =============================================================================
Describe 'Tab Completion — WorkflowEngine' {

    It 'Invoke-Workflow -Name completes workflow names' {
        $results = Get-TabCompletionResults 'Invoke-Workflow -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'daily_standup'
    }

    It 'Tooltip shows workflow description' {
        $results = Get-TabCompletionResults 'Invoke-Workflow -Name '
        $ds = $results | Where-Object { $_.CompletionText -eq 'daily_standup' }
        $ds.ToolTip | Should -Not -BeNullOrEmpty
    }

    It 'Filters by prefix' {
        $results = Get-TabCompletionResults 'Invoke-Workflow -Name daily'
        $results.Count | Should -Be 1
        $results[0].CompletionText | Should -Be 'daily_standup'
    }
}

# =============================================================================
# MCPClient.ps1 completers
# =============================================================================
Describe 'Tab Completion — MCPClient' {

    BeforeAll {
        # Seed a registered server
        $global:MCPServers['test-server'] = @{ Name = 'test-server'; Command = 'echo'; Args = @() }
        # Seed a connected server
        $global:MCPConnections['test-connected'] = @{ Process = $null; Tools = @() }
    }

    It 'Connect-MCPServer -Name completes registered server names' {
        $results = Get-TabCompletionResults 'Connect-MCPServer -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'test-server'
    }

    It 'Disconnect-MCPServer -Name completes connected server names' {
        $results = Get-TabCompletionResults 'Disconnect-MCPServer -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'test-connected'
    }

    It 'Get-MCPTools -Name completes connected server names' {
        $results = Get-TabCompletionResults 'Get-MCPTools -Name '
        $results.CompletionText | Should -Contain 'test-connected'
    }

    It 'Invoke-MCPTool -ServerName completes connected server names' {
        $results = Get-TabCompletionResults 'Invoke-MCPTool -ServerName '
        $results.CompletionText | Should -Contain 'test-connected'
    }

    AfterAll {
        $global:MCPServers.Remove('test-server')
        $global:MCPConnections.Remove('test-connected')
    }
}

# =============================================================================
# AppBuilder.ps1 completers
# =============================================================================
Describe 'Tab Completion — AppBuilder' {

    BeforeAll {
        # Seed a build directory
        $script:testBuildDir = Join-Path $global:AppBuilderPath 'test-app'
        New-Item -ItemType Directory -Path $script:testBuildDir -Force | Out-Null
    }

    It 'Remove-AppBuild -Name completes build names' {
        $results = Get-TabCompletionResults 'Remove-AppBuild -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'test-app'
    }

    It 'Update-AppBuild -Name completes build names' {
        $results = Get-TabCompletionResults 'Update-AppBuild -Name '
        $results.CompletionText | Should -Contain 'test-app'
    }

    It 'New-AppBuild -Framework completes framework names' {
        $results = Get-TabCompletionResults 'New-AppBuild -Framework '
        $results.Count | Should -Be 3
        $results.CompletionText | Should -Contain 'powershell'
        $results.CompletionText | Should -Contain 'python-tk'
        $results.CompletionText | Should -Contain 'python-web'
    }

    It 'Filters framework by prefix' {
        $results = Get-TabCompletionResults 'New-AppBuild -Framework py'
        $results.Count | Should -Be 2
    }

    AfterAll {
        if (Test-Path $script:testBuildDir) {
            Remove-Item $script:testBuildDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# =============================================================================
# AgentHeartbeat.ps1 completers
# =============================================================================
Describe 'Tab Completion — AgentHeartbeat' {

    BeforeAll {
        # Seed a task
        $global:HeartbeatTasksPath = Join-Path $global:TestTempRoot 'config\agent-tasks.json'
        Add-AgentTask -Id 'tab-test-task' -Task 'test task' -Schedule 'daily' -Time '08:00'
    }

    It 'Remove-AgentTask -Id completes task IDs' {
        $results = Get-TabCompletionResults 'Remove-AgentTask -Id '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'tab-test-task'
    }

    It 'Enable-AgentTask -Id completes task IDs' {
        $results = Get-TabCompletionResults 'Enable-AgentTask -Id '
        $results.CompletionText | Should -Contain 'tab-test-task'
    }

    It 'Disable-AgentTask -Id completes task IDs' {
        $results = Get-TabCompletionResults 'Disable-AgentTask -Id '
        $results.CompletionText | Should -Contain 'tab-test-task'
    }

    It 'Tooltip includes task description' {
        $results = Get-TabCompletionResults 'Remove-AgentTask -Id '
        $match = $results | Where-Object { $_.CompletionText -eq 'tab-test-task' }
        $match.ToolTip | Should -Match 'test task'
    }
}

# =============================================================================
# CodeArtifacts.ps1 completers
# =============================================================================
Describe 'Tab Completion — CodeArtifacts' {

    BeforeAll {
        # Seed an artifact file
        $script:testArtifact = Join-Path $global:ArtifactsPath 'test-artifact.py'
        New-Item -ItemType Directory -Path $global:ArtifactsPath -Force | Out-Null
        Set-Content $script:testArtifact -Value 'print("hello")' -Encoding UTF8
    }

    It 'Remove-Artifact -Name completes artifact file names' {
        $results = Get-TabCompletionResults 'Remove-Artifact -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'test-artifact.py'
    }

    AfterAll {
        if (Test-Path $script:testArtifact) {
            Remove-Item $script:testArtifact -Force -ErrorAction SilentlyContinue
        }
    }
}

# =============================================================================
# PersistentAliases.ps1 completers
# =============================================================================
Describe 'Tab Completion — PersistentAliases' {

    BeforeAll {
        # Seed a user aliases file
        $aliasContent = @"
Set-Alias myalias1 Get-Date -Force
Set-Alias myalias2 Get-Location -Force
"@
        Set-Content $global:UserAliasesPath -Value $aliasContent -Encoding UTF8
    }

    It 'Remove-PersistentAlias -Name completes alias names from file' {
        $results = Get-TabCompletionResults 'Remove-PersistentAlias -Name '
        $results.Count | Should -BeGreaterOrEqual 2
        $results.CompletionText | Should -Contain 'myalias1'
        $results.CompletionText | Should -Contain 'myalias2'
    }

    It 'Filters by prefix' {
        $results = Get-TabCompletionResults 'Remove-PersistentAlias -Name myalias1'
        $results.Count | Should -Be 1
        $results[0].CompletionText | Should -Be 'myalias1'
    }
}

# =============================================================================
# NavigationUtils.ps1 — git branch completers
# =============================================================================
Describe 'Tab Completion — NavigationUtils git branches' {

    BeforeAll {
        # Set up a temp git repo with a branch
        $script:gitTestDir = Join-Path $global:TestTempRoot 'git-test-repo'
        New-Item -ItemType Directory -Path $script:gitTestDir -Force | Out-Null
        Push-Location $script:gitTestDir
        git init --initial-branch=main 2>$null
        git config user.email "test@test.com"
        git config user.name "Test"
        Set-Content (Join-Path $script:gitTestDir 'file.txt') -Value 'test'
        git add -A
        git commit -m "init" 2>$null
        git branch feature-xyz
    }

    It 'gco -Branch completes branch names' {
        $results = Get-TabCompletionResults 'gco -Branch '
        $results.Count | Should -BeGreaterOrEqual 2
        $results.CompletionText | Should -Contain 'main'
        $results.CompletionText | Should -Contain 'feature-xyz'
    }

    It 'gmerge -Branch completes branch names' {
        $results = Get-TabCompletionResults 'gmerge -Branch '
        $results.CompletionText | Should -Contain 'main'
    }

    It 'grb -Branch completes branch names' {
        $results = Get-TabCompletionResults 'grb -Branch '
        $results.CompletionText | Should -Contain 'main'
    }

    It 'Filters by prefix' {
        $results = Get-TabCompletionResults 'gco -Branch feat'
        $results.Count | Should -Be 1
        $results[0].CompletionText | Should -Be 'feature-xyz'
    }

    AfterAll {
        Pop-Location
    }
}

# =============================================================================
# Pre-existing completers (regression)
# =============================================================================
Describe 'Tab Completion — Pre-existing (regression)' {

    It 'Invoke-IntentAction -Intent completes intent names' {
        $results = Get-TabCompletionResults 'Invoke-IntentAction -Intent '
        $results.Count | Should -BeGreaterThan 0
    }

    It 'Invoke-AgentTool -Name completes tool names' {
        $results = Get-TabCompletionResults 'Invoke-AgentTool -Name '
        $results.Count | Should -BeGreaterThan 0
        $results.CompletionText | Should -Contain 'calculator'
    }

    It 'Show-IntentHelp -Category completes category names' {
        $results = Get-TabCompletionResults 'Show-IntentHelp -Category '
        $results.Count | Should -BeGreaterThan 0
    }
}
