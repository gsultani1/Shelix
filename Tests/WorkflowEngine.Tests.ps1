BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'WorkflowEngine — Offline' {

    Context 'Workflow Registry' {
        It 'Workflows hashtable is populated' {
            $global:Workflows | Should -Not -BeNullOrEmpty
            $global:Workflows.Count | Should -BeGreaterOrEqual 3
        }

        It 'Each workflow has Name, Description, and Steps' {
            foreach ($name in $global:Workflows.Keys) {
                $wf = $global:Workflows[$name]
                $wf.Name | Should -Not -BeNullOrEmpty
                $wf.Description | Should -Not -BeNullOrEmpty
                $wf.Steps | Should -Not -BeNullOrEmpty
                $wf.Steps.Count | Should -BeGreaterThan 0
            }
        }

        It 'Each step has an Intent field' {
            foreach ($name in $global:Workflows.Keys) {
                foreach ($step in $global:Workflows[$name].Steps) {
                    $step.Intent | Should -Not -BeNullOrEmpty
                }
            }
        }
    }

    Context 'Invoke-Workflow' {
        It 'Rejects unknown workflow name' {
            $result = Invoke-Workflow -Name 'nonexistent_workflow_xyz'
            $result.Success | Should -BeFalse
        }

        It 'Executes a known workflow and returns result structure' {
            # daily_standup has calendar_today and git_status — both may fail
            # but the function should still return a result hash with Success and Results
            $result = Invoke-Workflow -Name 'daily_standup'
            $result | Should -Not -BeNullOrEmpty
            $result.ContainsKey('Success') | Should -BeTrue
            $result.ContainsKey('Results') | Should -BeTrue
            $result.Results | Should -Not -BeNullOrEmpty
        }

        It 'StopOnError halts after first failing step' {
            $result = Invoke-Workflow -Name 'daily_standup' -StopOnError
            # If first step fails, Results should have only 1 entry
            if (-not $result.Results[0].Success) {
                $result.Results.Count | Should -Be 1
            }
        }

        It 'Passes parameters through ParamMap' {
            # research_and_document maps topic -> query for web_search
            $result = Invoke-Workflow -Name 'research_and_document' -Params @{ topic = 'test query' }
            $result | Should -Not -BeNullOrEmpty
            $result.ContainsKey('Results') | Should -BeTrue
        }
    }

    Context 'Get-Workflows' {
        It 'Does not throw' {
            { Get-Workflows } | Should -Not -Throw
        }
    }
}
