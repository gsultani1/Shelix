BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1" -Minimal
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'SafetySystem — Offline' {

    Context 'Rate Limiting' {
        BeforeEach {
            $global:ExecutionTimestamps = @()
        }

        It 'Allows execution when under rate limit' {
            $result = Test-RateLimit
            $result.Allowed | Should -BeTrue
        }

        It 'Blocks execution when rate limit exceeded' {
            # Fill up the execution timestamps
            $now = Get-Date
            for ($i = 0; $i -lt $global:MaxExecutionsPerWindow; $i++) {
                $global:ExecutionTimestamps += $now.AddSeconds(-($i))
            }
            $result = Test-RateLimit
            $result.Allowed | Should -BeFalse
            $result.Message | Should -Match 'Rate limit'
            $result.WaitSeconds | Should -BeGreaterThan 0
        }

        It 'Clears expired timestamps outside the window' {
            $now = Get-Date
            # Add old timestamps outside the window
            $global:ExecutionTimestamps += $now.AddSeconds(-($global:RateLimitWindow + 10))
            $global:ExecutionTimestamps += $now.AddSeconds(-($global:RateLimitWindow + 20))
            $result = Test-RateLimit
            $result.Allowed | Should -BeTrue
            # Old timestamps should have been pruned
            $global:ExecutionTimestamps.Count | Should -BeLessOrEqual 0
        }

        It 'Add-ExecutionTimestamp increments the list' {
            $before = $global:ExecutionTimestamps.Count
            Add-ExecutionTimestamp
            $global:ExecutionTimestamps.Count | Should -Be ($before + 1)
        }
    }

    Context 'File Operation Tracking' {
        BeforeEach {
            $global:FileOperationHistory = @()
        }

        It 'Add-FileOperation records an entry' {
            $id = Add-FileOperation -Operation 'Create' -Path "$global:BildsyPSHome\test.txt" -ExecutionId 'test123'
            $id | Should -Not -BeNullOrEmpty
            $global:FileOperationHistory.Count | Should -Be 1
            $global:FileOperationHistory[0].Operation | Should -Be 'Create'
            $global:FileOperationHistory[0].Path | Should -Match 'test\.txt'
        }

        It 'Tracks session ID and user ID' {
            Add-FileOperation -Operation 'Create' -Path 'test.txt' -ExecutionId 'x'
            $global:FileOperationHistory[0].SessionId | Should -Be $global:SessionId
            $global:FileOperationHistory[0].UserId | Should -Be $env:USERNAME
        }

        It 'Enforces MaxUndoHistory limit' {
            for ($i = 0; $i -lt ($global:MaxUndoHistory + 10); $i++) {
                Add-FileOperation -Operation 'Create' -Path "file$i.txt" -ExecutionId "x$i"
            }
            $global:FileOperationHistory.Count | Should -BeLessOrEqual $global:MaxUndoHistory
        }
    }

    Context 'Undo-LastFileOperation' {
        It 'Undoes a Create operation by deleting the file' {
            $global:FileOperationHistory = @()
            $testFile = "$global:BildsyPSHome\undo-test.txt"
            Set-Content -Path $testFile -Value 'test'
            Add-FileOperation -Operation 'Create' -Path $testFile -ExecutionId 'undo1'
            $result = Undo-LastFileOperation
            Test-Path $testFile | Should -BeFalse
        }

        It 'Undoes a Delete operation by restoring from backup' {
            $global:FileOperationHistory = @()
            $original = "$global:BildsyPSHome\undo-del.txt"
            $backup = "$global:BildsyPSHome\undo-del.bak"
            Set-Content -Path $backup -Value 'original content'
            Add-FileOperation -Operation 'Delete' -Path $original -BackupPath $backup -ExecutionId 'undo2'
            Undo-LastFileOperation
            Test-Path $original | Should -BeTrue
            Get-Content $original -Raw | Should -Match 'original content'
        }

        It 'Reports no operations to undo when history is empty' {
            $global:FileOperationHistory = @()
            $result = Undo-LastFileOperation
            $result.Success | Should -BeFalse
        }
    }

    Context 'Session Info' {
        It 'Get-SessionInfo does not throw' {
            { Get-SessionInfo } | Should -Not -Throw
        }

        It 'Session globals are initialized' {
            $global:SessionId | Should -Not -BeNullOrEmpty
            $global:SessionStartTime | Should -Not -BeNullOrEmpty
            $global:UserId | Should -Be $env:USERNAME
        }
    }

    Context 'Get-FileOperationHistory' {
        It 'Does not throw with empty history' {
            $global:FileOperationHistory = @()
            { Get-FileOperationHistory } | Should -Not -Throw
        }

        It 'Does not throw with populated history' {
            $global:FileOperationHistory = @()
            Add-FileOperation -Operation 'Create' -Path 'test.txt' -ExecutionId 'hist1'
            { Get-FileOperationHistory } | Should -Not -Throw
        }
    }
}
