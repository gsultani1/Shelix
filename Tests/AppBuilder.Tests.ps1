BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"

    # Helper: build a file map quickly
    function New-FileMap {
        param([hashtable]$Map)
        return $Map
    }
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'AppBuilder — Offline' {

    # ── FRAMEWORK ROUTING ───────────────────────────────────
    Context 'Framework Routing (Get-BuildFramework)' {

        It 'Routes "<prompt>" to <expected>' -ForEach @(
            @{ prompt = 'a calculator';                          expected = 'powershell' }
            @{ prompt = 'a simple notepad app';                  expected = 'powershell' }
            @{ prompt = 'a file renamer tool';                   expected = 'powershell' }
            @{ prompt = 'a stopwatch with start and stop';       expected = 'powershell' }
            @{ prompt = 'a tkinter GUI for file management';     expected = 'python-tk' }
            @{ prompt = 'a python app that shows a timer';       expected = 'python-tk' }
            @{ prompt = 'a python GUI sprite editor';             expected = 'python-tk' }
            @{ prompt = 'a dashboard with charts and drag drop'; expected = 'python-web' }
            @{ prompt = 'a web app with REST API and login';       expected = 'python-web' }
            @{ prompt = 'a web app with login and database';     expected = 'python-web' }
        ) {
            Get-BuildFramework -Prompt $prompt | Should -Be $expected
        }

        It 'Explicit -Framework override wins regardless of keywords' -ForEach @(
            @{ prompt = 'a dashboard with charts'; framework = 'python-tk';  expected = 'python-tk' }
            @{ prompt = 'a python calculator';     framework = 'powershell'; expected = 'powershell' }
            @{ prompt = 'a tkinter app';           framework = 'python-web'; expected = 'python-web' }
        ) {
            Get-BuildFramework -Prompt $prompt -Framework $framework | Should -Be $expected
        }

        It 'Invalid -Framework falls through to keyword detection' {
            Get-BuildFramework -Prompt 'a calculator' -Framework 'invalid-framework' | Should -Be 'powershell'
        }

        It 'Empty prompt is rejected by Mandatory parameter' {
            { Get-BuildFramework -Prompt '' } | Should -Throw
        }

        It 'Prompt with no framework-specific keywords defaults to powershell' {
            Get-BuildFramework -Prompt 'an app' | Should -Be 'powershell'
        }

        It 'Is case-insensitive for keyword matching' {
            Get-BuildFramework -Prompt 'A TKINTER GUI APP' | Should -Be 'python-tk'
            Get-BuildFramework -Prompt 'A DASHBOARD WITH CHARTS' | Should -Be 'python-web'
        }

        It 'Handles competing keywords by selecting the dominant framework' {
            # "python" + "web" + "dashboard" should lean python-web even with "tkinter" absent
            $result = Get-BuildFramework -Prompt 'a python web dashboard with charts'
            $result | Should -Be 'python-web'
        }
    }

    # ── TOKEN BUDGET ────────────────────────────────────────
    Context 'Token Budget (Get-BuildMaxTokens)' {

        It 'Returns known output limit for gpt-4o' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'gpt-4o' |
                Should -Be 16384
        }

        It 'Returns 64000 for claude-sonnet-4-6' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'claude-sonnet-4-6' |
                Should -Be 64000
        }

        It 'Returns 128000 for claude-opus-4-6' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'claude-opus-4-6' |
                Should -Be 128000
        }

        It 'Returns default 8192 for unknown models' {
            Get-BuildMaxTokens -Framework 'python-web' -Model 'llama3' |
                Should -Be 8192
        }

        It 'Fuzzy matches model names containing known keys' {
            Get-BuildMaxTokens -Framework 'python-tk' -Model 'gpt-4o-2024-05-13' |
                Should -Be 16384
        }

        It 'Override returns the exact value requested' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'gpt-4o' -Override 32000 |
                Should -Be 32000
        }

        It 'Zero override falls back to model lookup' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'gpt-4o' -Override 0 |
                Should -Be 16384
        }

        It 'Negative override falls back to model lookup' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'gpt-4o' -Override -1 |
                Should -Be 16384
        }

        It 'Unknown model returns safe default' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'some-future-model' |
                Should -Be 8192
        }
    }

    # ── CODE VALIDATION ─────────────────────────────────────
    Context 'Code Validation (Test-GeneratedCode)' {

        Context 'PowerShell — Valid Code' {
            It 'Accepts syntactically correct PowerShell' {
                $files = New-FileMap @{ 'app.ps1' = 'Add-Type -AssemblyName System.Windows.Forms; Write-Host "hello"' }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success    | Should -BeTrue
                $result.Errors.Count | Should -Be 0
            }

            It 'Accepts multi-line PowerShell with functions' {
                $code = @'
function Get-Greeting { param($Name) return "Hello $Name" }
$form = New-Object System.Windows.Forms.Form
$form.Text = Get-Greeting -Name 'World'
'@
                $files = New-FileMap @{ 'app.ps1' = $code }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeTrue
            }
        }

        Context 'PowerShell — Syntax Errors' {
            It 'Catches unclosed braces' {
                $files = New-FileMap @{ 'app.ps1' = 'function Broken { Write-Host "missing close"' }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success          | Should -BeFalse
                $result.Errors.Count     | Should -BeGreaterThan 0
                $result.Errors[0]        | Should -Match 'Syntax error'
            }

            It 'Catches unclosed strings' {
                $files = New-FileMap @{ 'app.ps1' = 'Write-Host "never closed' }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeFalse
            }
        }

        Context 'PowerShell — Dangerous Patterns' {
            It 'Flags "<pattern>" as dangerous' -ForEach @(
                @{ pattern = 'Invoke-Expression'; code = 'Invoke-Expression "Get-Process"' }
                @{ pattern = 'iex';               code = '$cmd = "dir"; iex $cmd' }
                @{ pattern = 'Remove-Item.*-Recurse'; code = 'Remove-Item C:\ -Recurse -Force' }
                @{ pattern = 'Start-Process.*-Verb.*RunAs'; code = 'Start-Process cmd -Verb RunAs' }
            ) {
                $files = New-FileMap @{ 'app.ps1' = $code }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match $pattern
            }
        }

        Context 'Python — Dangerous Patterns' {
            It 'Flags "<pattern>" as dangerous' -ForEach @(
                @{ pattern = 'eval';       code = 'x = eval("2+2")';                    fw = 'python-tk' }
                @{ pattern = 'exec';       code = 'exec("import os")';                   fw = 'python-tk' }
                @{ pattern = 'os\.system'; code = 'import os; os.system("rm -rf /")';    fw = 'python-tk' }
                @{ pattern = 'subprocess'; code = 'import subprocess; subprocess.call(["rm"])'; fw = 'python-web' }
                @{ pattern = 'os\.popen';  code = 'import os; os.popen("ls")';           fw = 'python-tk' }
                @{ pattern = '__import__'; code = '__import__("os").system("ls")';        fw = 'python-web' }
            ) {
                $files = New-FileMap @{ 'app.py' = $code }
                $result = Test-GeneratedCode -Files $files -Framework $fw
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match $pattern
            }
        }

        Context 'Multi-File Validation' {
            It 'Fails if any file in a multi-file set has errors' {
                $files = New-FileMap @{
                    'app.ps1'    = 'Write-Host "fine"'
                    'helper.ps1' = 'Invoke-Expression "bad"'
                }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeFalse
            }

            It 'Passes when all files in a multi-file set are clean' {
                $files = New-FileMap @{
                    'app.ps1'    = 'Write-Host "main"'
                    'helper.ps1' = 'function Get-Data { return 42 }'
                }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeTrue
            }
        }

        Context 'Edge Cases' {
            It 'Handles empty code gracefully' {
                $files = New-FileMap @{ 'app.ps1' = '' }
                { Test-GeneratedCode -Files $files -Framework 'powershell' } | Should -Not -Throw
            }

            It 'Handles whitespace-only code gracefully' {
                $files = New-FileMap @{ 'app.ps1' = "   `n   `n   " }
                { Test-GeneratedCode -Files $files -Framework 'powershell' } | Should -Not -Throw
            }

            It 'Handles an empty file map gracefully' {
                $files = @{}
                { Test-GeneratedCode -Files $files -Framework 'powershell' } | Should -Not -Throw
            }
        }
    }

    # ── BRANDING INJECTION ──────────────────────────────────
    Context 'Branding Injection (Invoke-BildsyPSBranding)' {

        Context 'PowerShell Branding' {
            It 'Injects branding into a PowerShell file that lacks it' {
                $files = New-FileMap @{
                    'app.ps1' = @'
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
[System.Windows.Forms.Application]::Run($form)
'@
                }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'powershell'
                $result['app.ps1'] | Should -Match 'Built with BildsyPS'
            }

            It 'Does not double-inject when branding already exists' {
                $code = 'Add-Type -AssemblyName System.Windows.Forms; # Built with BildsyPS already here'
                $files = New-FileMap @{ 'app.ps1' = $code }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'powershell'
                [regex]::Matches($result['app.ps1'], 'Built with BildsyPS').Count | Should -Be 1
            }
        }

        Context 'Python-Web Branding' {
            It 'Injects footer into HTML file' {
                $files = New-FileMap @{ 'web/index.html' = '<html><body><h1>App</h1></body></html>' }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'python-web'
                $result['web/index.html'] | Should -Match 'Built with BildsyPS'
            }

            It 'Injects into HTML but not into Python server file' {
                $files = New-FileMap @{
                    'web/index.html' = '<html><body></body></html>'
                    'app.py'         = 'from flask import Flask; app = Flask(__name__)'
                }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'python-web'
                $result['web/index.html'] | Should -Match 'Built with BildsyPS'
            }
        }

        Context 'Python-Tk Branding' {
            It 'Injects about function into tkinter code' {
                $files = New-FileMap @{ 'app.py' = "import tkinter`nroot = tkinter.Tk()`nroot.mainloop()" }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'python-tk'
                $result['app.py'] | Should -Match 'Built with BildsyPS'
            }
        }

        Context 'NoBranding Flag' {
            It 'Skips injection entirely for PowerShell' {
                $files = New-FileMap @{ 'app.ps1' = 'Write-Host "no branding"' }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'powershell' -NoBranding
                $result['app.ps1'] | Should -Not -Match 'Built with BildsyPS'
            }

            It 'Skips injection entirely for python-web' {
                $files = New-FileMap @{ 'web/index.html' = '<html><body></body></html>' }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'python-web' -NoBranding
                $result['web/index.html'] | Should -Not -Match 'Built with BildsyPS'
            }

            It 'Skips injection entirely for python-tk' {
                $files = New-FileMap @{ 'app.py' = "import tkinter`nroot = tkinter.Tk()" }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'python-tk' -NoBranding
                $result['app.py'] | Should -Not -Match 'Built with BildsyPS'
            }
        }

        Context 'Edge Cases' {
            It 'Returns files unchanged when file map is empty' {
                $result = Invoke-BildsyPSBranding -Files @{} -Framework 'powershell'
                $result.Count | Should -Be 0
            }

            It 'Preserves all original files in the returned map' {
                $files = New-FileMap @{
                    'app.ps1'    = 'Write-Host "main"'
                    'helper.ps1' = 'function Help { return 1 }'
                }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'powershell'
                $result.Keys | Should -Contain 'app.ps1'
                $result.Keys | Should -Contain 'helper.ps1'
            }
        }
    }

    # ── BUILD TRACKING (SQLITE) ─────────────────────────────
    Context 'Build Tracking (SQLite)' {

        BeforeAll {
            $script:DbAvailable = [bool]$global:ChatDbReady
        }

        It 'Initialize-BuildsTable creates the table' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Initialize-BuildsTable | Should -BeTrue
        }

        It 'Save-BuildRecord persists all fields correctly' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildRecord -Name 'roundtrip-app' -Framework 'powershell' -Prompt 'a test app' `
                -Status 'completed' -ExePath 'C:\fake\roundtrip-app.exe' -SourceDir 'C:\fake\source' `
                -Provider 'ollama' -Model 'llama3' -Branded $true -BuildTime 5.2

            $conn = Get-ChatDbConnection
            $cmd  = $conn.CreateCommand()
            $cmd.CommandText = "SELECT name, framework, status, provider, model, branded, prompt FROM builds WHERE name = 'roundtrip-app'"
            $reader = $cmd.ExecuteReader()
            $reader.Read() | Should -BeTrue
            $reader['name']      | Should -Be 'roundtrip-app'
            $reader['framework'] | Should -Be 'powershell'
            $reader['status']    | Should -Be 'completed'
            $reader['provider']  | Should -Be 'ollama'
            $reader['model']     | Should -Be 'llama3'
            $reader['prompt']    | Should -Be 'a test app'
            $reader.Close(); $cmd.Dispose(); $conn.Close(); $conn.Dispose()
        }

        It 'Save-BuildRecord appends multiple records with the same name' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildRecord -Name 'multi-test' -Framework 'powershell' -Prompt 'v1' `
                -Status 'completed' -ExePath 'C:\v1.exe' -SourceDir 'C:\v1' `
                -Provider 'ollama' -Model 'llama3' -Branded $true -BuildTime 3.0

            Save-BuildRecord -Name 'multi-test' -Framework 'python-tk' -Prompt 'v2' `
                -Status 'completed' -ExePath 'C:\v2.exe' -SourceDir 'C:\v2' `
                -Provider 'ollama' -Model 'llama3' -Branded $false -BuildTime 4.0

            $conn = Get-ChatDbConnection
            $cmd  = $conn.CreateCommand()
            $cmd.CommandText = "SELECT COUNT(*) FROM builds WHERE name = 'multi-test'"
            $cmd.ExecuteScalar() | Should -BeGreaterOrEqual 2
            $cmd.Dispose(); $conn.Close(); $conn.Dispose()
        }

        It 'Get-AppBuilds returns saved records' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildRecord -Name 'list-test' -Framework 'powershell' -Prompt 'listing' `
                -Status 'completed' -ExePath 'C:\fake.exe' -SourceDir 'C:\fake' `
                -Provider 'ollama' -Model 'llama3' -Branded $true -BuildTime 1.0

            $builds = Get-AppBuilds
            $builds | Should -Not -BeNullOrEmpty
            ($builds | Where-Object { $_.name -eq 'list-test' }) | Should -Not -BeNullOrEmpty
        }

        It 'Remove-AppBuild clears the record from the database' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildRecord -Name 'delete-me' -Framework 'powershell' -Prompt 'delete test' `
                -Status 'completed' -ExePath 'C:\del.exe' -SourceDir 'C:\del' `
                -Provider 'ollama' -Model 'llama3' -Branded $true -BuildTime 1.0

            Remove-AppBuild -Name 'delete-me'

            $conn = Get-ChatDbConnection
            $cmd  = $conn.CreateCommand()
            $cmd.CommandText = "SELECT COUNT(*) FROM builds WHERE name = 'delete-me'"
            $cmd.ExecuteScalar() | Should -Be 0
            $cmd.Dispose(); $conn.Close(); $conn.Dispose()
        }

        It 'Remove-AppBuild does not throw for a nonexistent record' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            { Remove-AppBuild -Name 'never-existed' } | Should -Not -Throw
        }

        It 'Save-BuildRecord with failed status persists correctly' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildRecord -Name 'failed-build' -Framework 'powershell' -Prompt 'will fail' `
                -Status 'failed' -ExePath '' -SourceDir 'C:\failed' `
                -Provider 'ollama' -Model 'llama3' -Branded $false -BuildTime 0.5

            $conn = Get-ChatDbConnection
            $cmd  = $conn.CreateCommand()
            $cmd.CommandText = "SELECT status, exe_path FROM builds WHERE name = 'failed-build'"
            $reader = $cmd.ExecuteReader()
            $reader.Read() | Should -BeTrue
            $reader['status'] | Should -Be 'failed'
            $reader.Close(); $cmd.Dispose(); $conn.Close(); $conn.Dispose()
        }

        AfterAll {
            if ($script:DbAvailable) {
                foreach ($name in @('roundtrip-app', 'multi-test', 'list-test', 'delete-me', 'failed-build')) {
                    Remove-AppBuild -Name $name -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # ── BUILD FAILURE HANDLING (offline — no LLM needed) ────
    Context 'Build Failure Handling' {

        It 'Returns failure result for an empty prompt without throwing' {
            $result = New-AppBuild -Prompt '' -Framework 'powershell' -Name 'test-empty-prompt'
            $result.Success | Should -BeFalse
            $result.Output | Should -Match 'empty'
        }

        It 'Returns failure result for a whitespace-only prompt without throwing' {
            $result = New-AppBuild -Prompt '   ' -Framework 'powershell' -Name 'test-ws-prompt'
            $result.Success | Should -BeFalse
        }

        AfterAll {
            Remove-AppBuild -Name 'test-empty-prompt' -ErrorAction SilentlyContinue
            Remove-AppBuild -Name 'test-ws-prompt' -ErrorAction SilentlyContinue
        }
    }

    # ── NAME SANITIZATION ───────────────────────────────────
    Context 'Build Name Sanitization' {

        It 'Strips invalid filesystem characters from build names' {
            $result = Get-SafeBuildName -Name 'my<app>:v2'
            $result | Should -Not -Match '[<>:"/\\|?*]'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Trims leading and trailing whitespace' {
            $result = Get-SafeBuildName -Name '  spaced-app  '
            $result | Should -Be 'spaced-app'
        }

        It 'Handles empty name without throwing' {
            { Get-SafeBuildName -Name '' } | Should -Not -Throw
        }
    }
}

Describe 'AppBuilder — Live' -Tag 'Live' {

    BeforeAll {
        $script:LiveProvider = Find-ReachableProvider
        $script:HasProvider = [bool]$script:LiveProvider
        $script:HasPs2exe = $null -ne (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue) -or
                            $null -ne (Get-Module -ListAvailable -Name ps2exe)
        $script:CanBuild = $script:HasProvider -and $script:HasPs2exe
    }

    Context 'PowerShell Full Build Pipeline' {

        It 'New-AppBuild generates a .exe from a simple prompt' {
            if (-not $script:CanBuild) { Set-ItResult -Skipped -Because 'No LLM provider or ps2exe available'; return }
            $script:PsResult = New-AppBuild -Prompt 'a simple counter app with plus and minus buttons' `
                -Framework 'powershell' -Name 'test-ps-counter' -Provider $script:LiveProvider
            $script:PsResult.Success   | Should -BeTrue
            $script:PsResult.ExePath   | Should -Not -BeNullOrEmpty
            Test-Path $script:PsResult.ExePath | Should -BeTrue
            $script:PsResult.Framework | Should -Be 'powershell'
            $script:PsResult.AppName   | Should -Be 'test-ps-counter'
        }

        It 'Source contains BildsyPS branding' {
            if (-not $script:CanBuild) { Set-ItResult -Skipped -Because 'No LLM provider or ps2exe available'; return }
            $src = Join-Path $global:AppBuilderPath 'test-ps-counter\source\app.ps1'
            if (Test-Path $src) {
                Get-Content $src -Raw | Should -Match 'Built with BildsyPS'
            }
        }

        It 'Source passes code validation' {
            if (-not $script:CanBuild) { Set-ItResult -Skipped -Because 'No LLM provider or ps2exe available'; return }
            $src = Join-Path $global:AppBuilderPath 'test-ps-counter\source\app.ps1'
            if (Test-Path $src) {
                $code  = Get-Content $src -Raw
                $files = @{ 'app.ps1' = $code }
                $valid = Test-GeneratedCode -Files $files -Framework 'powershell'
                $valid.Success | Should -BeTrue
            }
        }

        It 'Build record exists in SQLite with completed status' {
            if (-not $script:CanBuild) { Set-ItResult -Skipped -Because 'No LLM provider or ps2exe available'; return }
            if (-not $global:ChatDbReady) { Set-ItResult -Skipped -Because 'SQLite not available' }
            $conn = Get-ChatDbConnection
            $cmd  = $conn.CreateCommand()
            $cmd.CommandText = "SELECT status FROM builds WHERE name = 'test-ps-counter' ORDER BY created_at DESC LIMIT 1"
            $cmd.ExecuteScalar() | Should -Be 'completed'
            $cmd.Dispose(); $conn.Close(); $conn.Dispose()
        }

        It 'Output directory structure is correct' {
            if (-not $script:CanBuild) { Set-ItResult -Skipped -Because 'No LLM provider or ps2exe available'; return }
            $base = Join-Path $global:AppBuilderPath 'test-ps-counter'
            Test-Path $base                         | Should -BeTrue
            Test-Path (Join-Path $base 'source')    | Should -BeTrue
        }

        AfterAll {
            if ($script:CanBuild) {
                Remove-AppBuild -Name 'test-ps-counter' -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Python-Tk Full Build Pipeline' {

        BeforeAll {
            $script:HasPyInstaller = $null -ne (Get-Command pyinstaller -ErrorAction SilentlyContinue)
            $script:CanBuildPy = $script:HasProvider -and $script:HasPyInstaller
        }

        It 'New-AppBuild generates an .exe from a python-tk prompt' {
            if (-not $script:CanBuildPy) { Set-ItResult -Skipped -Because 'No LLM provider or pyinstaller available'; return }
            $script:PyResult = New-AppBuild -Prompt 'a tkinter color picker tool' `
                -Framework 'python-tk' -Name 'test-py-color' -Provider $script:LiveProvider
            $script:PyResult.Success   | Should -BeTrue
            $script:PyResult.ExePath   | Should -Not -BeNullOrEmpty
            Test-Path $script:PyResult.ExePath | Should -BeTrue
            $script:PyResult.Framework | Should -Be 'python-tk'
        }

        It 'Source contains BildsyPS branding' {
            if (-not $script:CanBuildPy) { Set-ItResult -Skipped -Because 'No LLM provider or pyinstaller available'; return }
            $src = Join-Path $global:AppBuilderPath 'test-py-color\source\app.py'
            if (Test-Path $src) {
                Get-Content $src -Raw | Should -Match 'Built with BildsyPS'
            }
        }

        AfterAll {
            if ($script:CanBuildPy) {
                Remove-AppBuild -Name 'test-py-color' -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'NoBranding Live Build' {

        It 'Build with -NoBranding omits BildsyPS branding from source' {
            if (-not $script:CanBuild) { Set-ItResult -Skipped -Because 'No LLM provider or ps2exe available'; return }
            $result = New-AppBuild -Prompt 'a hello world window' `
                -Framework 'powershell' -Name 'test-nobrand' -NoBranding -Provider $script:LiveProvider
            $result.Success | Should -BeTrue
            $src = Join-Path $global:AppBuilderPath 'test-nobrand\source\app.ps1'
            if (Test-Path $src) {
                Get-Content $src -Raw | Should -Not -Match 'Built with BildsyPS'
            }
        }

        AfterAll {
            if ($script:CanBuild) {
                Remove-AppBuild -Name 'test-nobrand' -ErrorAction SilentlyContinue
            }
        }
    }

}
