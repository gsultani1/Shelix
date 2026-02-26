BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1" -Minimal
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'SecretScanner — Offline' {

    Context 'Invoke-SecretScan' {
        It 'Returns empty array for nonexistent files' {
            $result = Invoke-SecretScan -Paths @("$global:BildsyPSHome\nonexistent.txt")
            @($result).Count | Should -Be 0
        }

        It 'Detects Anthropic API key pattern' {
            $f = "$global:BildsyPSHome\config\test-secret.txt"
            Set-Content -Path $f -Value 'ANTHROPIC_API_KEY=sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAA'
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -BeGreaterThan 0
            $result[0].Pattern | Should -Be 'Anthropic API Key'
        }

        It 'Detects OpenAI API key pattern' {
            $f = "$global:BildsyPSHome\config\test-openai.txt"
            Set-Content -Path $f -Value 'OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz1234567890'
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -BeGreaterThan 0
            $result[0].Pattern | Should -Be 'OpenAI API Key'
        }

        It 'Detects generic secret assignment' {
            $f = "$global:BildsyPSHome\config\test-generic.txt"
            Set-Content -Path $f -Value 'password=SuperSecretPass1234'
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -BeGreaterThan 0
            $result[0].Pattern | Should -Be 'Generic Secret Assign'
        }

        It 'Skips generic pattern when keyword is embedded in a larger name' {
            $f = "$global:BildsyPSHome\config\test-embedded.txt"
            Set-Content -Path $f -Value "`$lblApiKey = New-Object System.Windows.Forms.Label`n`$tbPassword = New-Object System.Windows.Forms.TextBox"
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -Be 0
        }

        It 'Skips comment lines' {
            $f = "$global:BildsyPSHome\config\test-comment.txt"
            Set-Content -Path $f -Value '# OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz1234567890'
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -Be 0
        }

        It 'Returns correct file and line number' {
            $f = "$global:BildsyPSHome\config\test-line.txt"
            Set-Content -Path $f -Value "safe line`nANOTHER_KEY=sk-ant-api03-BBBBBBBBBBBBBBBBBBBBBB`nlast line"
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -BeGreaterThan 0
            $result[0].Line | Should -Be 2
            $result[0].FileName | Should -Be 'test-line.txt'
        }

        It 'Masks secrets in output' {
            $f = "$global:BildsyPSHome\config\test-mask.txt"
            Set-Content -Path $f -Value 'TOKEN=sk-ant-api03-CCCCCCCCCCCCCCCCCCCCCC'
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -BeGreaterThan 0
            $result[0].Masked | Should -Match '\*+'
        }

        It 'Handles single-line file without char coercion' {
            $f = "$global:BildsyPSHome\config\test-single-secret.txt"
            Set-Content -Path $f -Value 'MY_KEY=sk-ant-api03-DDDDDDDDDDDDDDDDDDDDDD'
            { Invoke-SecretScan -Paths @($f) } | Should -Not -Throw
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -BeGreaterThan 0
        }

        It 'Returns empty for clean file with no secrets' {
            $f = "$global:BildsyPSHome\config\test-clean.txt"
            Set-Content -Path $f -Value "FOO=bar`nBAZ=qux`n# just config"
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -Be 0
        }

        It 'Scans multiple files' {
            $f1 = "$global:BildsyPSHome\config\multi1.txt"
            $f2 = "$global:BildsyPSHome\config\multi2.txt"
            Set-Content -Path $f1 -Value 'clean=data'
            Set-Content -Path $f2 -Value 'TOKEN=sk-ant-api03-EEEEEEEEEEEEEEEEEEEEEE'
            $result = Invoke-SecretScan -Paths @($f1, $f2)
            @($result).Count | Should -Be 1
            $result[0].FileName | Should -Be 'multi2.txt'
        }

        It 'Does not flag DOM accessor patterns as secrets (getElementById, querySelector)' {
            $f = "$global:BildsyPSHome\config\test-dom.txt"
            Set-Content -Path $f -Value @(
                'const token = document.getElementById("auth-token-input");'
                'let secret = document.querySelector(".secret-panel");'
                'var apiKey = localStorage.getItem("cached_key");'
            )
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -Be 0
        }

        It 'Still detects real secrets even with DOM-like variable names' {
            $f = "$global:BildsyPSHome\config\test-real-secret.txt"
            Set-Content -Path $f -Value 'token = abc123def456xyz789'
            $result = Invoke-SecretScan -Paths @($f)
            @($result).Count | Should -BeGreaterThan 0
            $result[0].Pattern | Should -Be 'Generic Secret Assign'
        }
    }

    Context 'Invoke-SecretScan -ExcludePatterns' {
        It 'Excludes a named pattern from results' {
            $f = "$global:BildsyPSHome\config\test-exclude.txt"
            Set-Content -Path $f -Value 'password=SuperSecretPass1234'
            $result = Invoke-SecretScan -Paths @($f) -ExcludePatterns @('Generic Secret Assign')
            @($result).Count | Should -Be 0
        }

        It 'Still detects non-excluded patterns' {
            $f = "$global:BildsyPSHome\config\test-exclude2.txt"
            Set-Content -Path $f -Value 'KEY=sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAA'
            $result = Invoke-SecretScan -Paths @($f) -ExcludePatterns @('Generic Secret Assign')
            @($result).Count | Should -BeGreaterThan 0
            $result[0].Pattern | Should -Be 'Anthropic API Key'
        }

        It 'Supports excluding multiple patterns' {
            $f = "$global:BildsyPSHome\config\test-exclude3.txt"
            Set-Content -Path $f -Value "password=SuperSecretPass1234`nKEY=sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAA"
            $result = Invoke-SecretScan -Paths @($f) -ExcludePatterns @('Generic Secret Assign', 'Anthropic API Key')
            @($result).Count | Should -Be 0
        }
    }

    Context 'Show-SecretScanReport' {
        It 'Produces no output for empty findings' {
            { Show-SecretScanReport -Findings @() -GitignoreWarnings @() -Quiet } | Should -Not -Throw
        }
    }
}
