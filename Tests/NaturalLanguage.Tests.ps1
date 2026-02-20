BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'NaturalLanguage — Offline' {

    Context 'Convert-NaturalLanguageToCommand' {
        It 'Translates "list files" to Get-ChildItem' {
            $result = Convert-NaturalLanguageToCommand -InputText 'list files'
            $result | Should -Match 'EXECUTE.*Get-ChildItem'
        }

        It 'Translates "open notepad" to Start-Process notepad' {
            $result = Convert-NaturalLanguageToCommand -InputText 'open notepad'
            $result | Should -Match 'EXECUTE.*Start-Process notepad'
        }

        It 'Returns input unchanged when no mapping found' {
            $result = Convert-NaturalLanguageToCommand -InputText 'something completely unrecognized xyz123'
            $result | Should -Be 'something completely unrecognized xyz123'
        }

        It 'Is case-insensitive' {
            $result = Convert-NaturalLanguageToCommand -InputText 'LIST FILES'
            $result | Should -Match 'EXECUTE.*Get-ChildItem'
        }

        It 'Handles "show processes" mapping' {
            $result = Convert-NaturalLanguageToCommand -InputText 'show processes'
            $result | Should -Match 'EXECUTE.*Get-Process'
        }
    }

    Context 'Get-TokenEstimate' {
        It 'Returns a positive number' {
            $estimate = Get-TokenEstimate
            $estimate | Should -BeGreaterThan 0
        }

        It 'Returns default fallback of 4.0 when no mappings loaded' {
            $saved = $global:NLMappings
            $global:NLMappings = $null
            $estimate = Get-TokenEstimate
            $estimate | Should -Be 4.0
            $global:NLMappings = $saved
        }
    }

    Context 'Get-EstimatedTokenCount' {
        It 'Returns 0 for empty chat history' {
            $saved = $global:ChatSessionHistory
            $global:ChatSessionHistory = @()
            $count = Get-EstimatedTokenCount
            $count | Should -Be 0
            $global:ChatSessionHistory = $saved
        }

        It 'Returns positive count for non-empty history' {
            $saved = $global:ChatSessionHistory
            $global:ChatSessionHistory = @(
                @{ role = 'user'; content = 'Hello, how are you today?' }
                @{ role = 'assistant'; content = 'I am doing well, thank you for asking!' }
            )
            $count = Get-EstimatedTokenCount
            $count | Should -BeGreaterThan 0
            $global:ChatSessionHistory = $saved
        }
    }

    Context 'Import-NaturalLanguageMappings' {
        It 'Returns false when mappings file does not exist' {
            $saved = $global:NLMappingsPath
            $global:NLMappingsPath = "$global:BildsyPSHome\data\nonexistent.json"
            $result = Import-NaturalLanguageMappings
            $result | Should -BeFalse
            $global:NLMappingsPath = $saved
        }
    }
}
