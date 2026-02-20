BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'ResponseParser — Offline' {

    Context 'Convert-JsonIntent' {
        It 'Passes through plain text unchanged' {
            $result = Convert-JsonIntent -text 'Hello, this is plain text.'
            $result | Should -Match 'Hello, this is plain text.'
        }

        It 'Detects and annotates valid PowerShell commands in code blocks' {
            $fence = '``' + '`'
            $text = "${fence}powershell`nGet-Date`n${fence}"
            $result = Convert-JsonIntent -text $text
            ($result -join "`n") | Should -Match 'Get-Date'
            ($result -join "`n") | Should -Match 'READONLY|ReadOnly|SystemInfo'
        }

        It 'Annotates unrecognized commands as not in safe list' {
            $fence = '``' + '`'
            $text = "${fence}powershell`nInvoke-WebRequest http://example.com`n${fence}"
            $result = Convert-JsonIntent -text $text
            ($result -join "`n") | Should -Match 'Not in safe actions'
        }

        It 'Parses inline JSON intent action' {
            $json = '{"intent": "list_files"}'
            $result = Convert-JsonIntent -text $json
            ($result -join "`n") | Should -Match 'Intent Action.*list_files'
        }

        It 'Respects MaxExecutionsPerMessage limit' {
            $savedMax = $global:MaxExecutionsPerMessage
            $global:MaxExecutionsPerMessage = 1
            # Two separate intent calls on separate lines
            $text = '{"intent": "list_files"}' + "`nsome text`n" + '{"intent": "clipboard_read"}'
            $result = Convert-JsonIntent -text $text
            $intentLines = @($result | Where-Object { $_ -match 'Intent Action' })
            $intentLines.Count | Should -Be 1
            $global:MaxExecutionsPerMessage = $savedMax
        }
    }

    Context 'Format-Markdown' {
        It 'Function exists' {
            Get-Command Format-Markdown -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Does not throw on plain text' {
            { Format-Markdown -Text 'Hello world' } | Should -Not -Throw
        }

        It 'Does not throw on markdown with headers' {
            { Format-Markdown -Text '# Title' } | Should -Not -Throw
        }
    }
}
