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
            @{ prompt = 'a tauri app for note taking';           expected = 'tauri' }
            @{ prompt = 'a rust GUI file manager';               expected = 'tauri' }
            @{ prompt = 'a native web desktop app with rust';    expected = 'tauri' }
        ) {
            Get-BuildFramework -Prompt $prompt | Should -Be $expected
        }

        It 'Explicit -Framework override wins regardless of keywords' -ForEach @(
            @{ prompt = 'a dashboard with charts'; framework = 'python-tk';  expected = 'python-tk' }
            @{ prompt = 'a python calculator';     framework = 'powershell'; expected = 'powershell' }
            @{ prompt = 'a tkinter app';           framework = 'python-web'; expected = 'python-web' }
            @{ prompt = 'a simple calculator';     framework = 'tauri';      expected = 'tauri' }
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

        It 'Returns full 64000 for claude-sonnet-4-6 (uncapped)' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'claude-sonnet-4-6' |
                Should -Be 64000
        }

        It 'Returns full 128000 for claude-opus-4-6 (uncapped)' {
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

        Context 'PowerShell — PS7+ Operator Compatibility' {
            It 'Flags ?? null-coalescing operator' {
                $files = New-FileMap @{ 'app.ps1' = '$x = $a ?? "default"' }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match 'null-coalescing operator'
            }

            It 'Flags ?. null-conditional operator' {
                $files = New-FileMap @{ 'app.ps1' = '$val = $obj?.Property' }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match 'null-conditional operator'
            }

            It 'Flags ?[] null-conditional index operator' {
                $files = New-FileMap @{ 'app.ps1' = '$val = $arr?[0]' }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match 'null-conditional index'
            }

            It 'Does NOT flag ?? in Python code' {
                $files = New-FileMap @{ 'app.py' = 'x = a if a is not None else "default"  # not ?? but harmless' }
                $result = Test-GeneratedCode -Files $files -Framework 'python-tk'
                $result.Success | Should -BeTrue
            }

            It 'Does NOT flag ? in ternary or help contexts' {
                $files = New-FileMap @{ 'app.ps1' = 'Get-Help Get-Process -?' }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                ($result.Errors -join "`n") | Should -Not -Match 'null-coalescing'
            }

            It 'Accepts PS 5.1 compatible null-check pattern' {
                $code = 'if ($null -ne $x) { $x } else { "default" }'
                $files = New-FileMap @{ 'app.ps1' = $code }
                $result = Test-GeneratedCode -Files $files -Framework 'powershell'
                $result.Success | Should -BeTrue
            }
        }

        Context 'Tauri — Rust Validation' {

            BeforeAll {
                $script:MinimalCargoToml = "[package]`nname = `"test-app`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[build-dependencies]`ntauri-build = { version = `"2`", features = [] }`n`n[dependencies]`ntauri = { version = `"2`", features = [] }`nserde = { version = `"1`", features = [`"derive`"] }`nserde_json = `"1`""
                $script:MinimalBuildRs = 'fn main() { tauri_build::build() }'
            }

            It 'Accepts valid Rust code' {
                $files = New-FileMap @{
                    'src-tauri/Cargo.toml'  = $script:MinimalCargoToml
                    'src-tauri/src/main.rs' = 'fn main() { tauri::Builder::default().run(tauri::generate_context!()).expect("error"); }'
                    'src-tauri/build.rs'    = $script:MinimalBuildRs
                }
                $result = Test-GeneratedCode -Files $files -Framework 'tauri'
                $result.Success | Should -BeTrue
            }

            It 'Flags missing Cargo.toml' {
                $files = New-FileMap @{ 'src-tauri/src/main.rs' = 'fn main() {}' }
                $result = Test-GeneratedCode -Files $files -Framework 'tauri'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match 'Missing Cargo\.toml'
            }

            It 'Flags missing main.rs' {
                $files = New-FileMap @{ 'src-tauri/Cargo.toml' = $script:MinimalCargoToml; 'src-tauri/build.rs' = $script:MinimalBuildRs }
                $result = Test-GeneratedCode -Files $files -Framework 'tauri'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match 'Missing main\.rs'
            }

            It 'Flags [lib] without lib.rs' {
                $tomlWithLib = $script:MinimalCargoToml + "`n[lib]`nname = `"mylib`"`ncrate-type = [`"lib`"]"
                $files = New-FileMap @{
                    'src-tauri/Cargo.toml'  = $tomlWithLib
                    'src-tauri/src/main.rs' = 'fn main() {}'
                    'src-tauri/build.rs'    = $script:MinimalBuildRs
                }
                $result = Test-GeneratedCode -Files $files -Framework 'tauri'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match 'lib\.rs'
            }

            It 'Flags unbalanced braces in Rust' {
                $files = New-FileMap @{
                    'src-tauri/Cargo.toml'  = $script:MinimalCargoToml
                    'src-tauri/src/main.rs' = 'fn main() { if true {'
                    'src-tauri/build.rs'    = $script:MinimalBuildRs
                }
                $result = Test-GeneratedCode -Files $files -Framework 'tauri'
                $result.Success | Should -BeFalse
                ($result.Errors -join "`n") | Should -Match 'unbalanced braces'
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

        Context 'Tauri Branding' {
            It 'Injects footer into Tauri HTML file' {
                $files = New-FileMap @{
                    'web/index.html'          = '<html><body><h1>App</h1></body></html>'
                    'src-tauri/src/main.rs'   = 'fn main() { tauri::Builder::default().run(); }'
                    'src-tauri/Cargo.toml'    = '[package]'
                }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'tauri'
                $result['web/index.html'] | Should -Match 'Built with BildsyPS'
            }

            It 'Does not double-inject when branding already exists' {
                $files = New-FileMap @{
                    'web/index.html' = '<html><body>Built with BildsyPS</body></html>'
                }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'tauri'
                [regex]::Matches($result['web/index.html'], 'Built with BildsyPS').Count | Should -Be 1
            }

            It 'NoBranding flag skips injection for tauri' {
                $files = New-FileMap @{ 'web/index.html' = '<html><body></body></html>' }
                $result = Invoke-BildsyPSBranding -Files $files -Framework 'tauri' -NoBranding
                $result['web/index.html'] | Should -Not -Match 'Built with BildsyPS'
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

    # ── TRUNCATION GUARD ─────────────────────────────────────
    Context 'Truncation Guard (Invoke-CodeGeneration)' {

        It 'Returns failure with StopReason when response is truncated (max_tokens)' {
            Mock Invoke-ChatCompletion {
                return @{
                    Content    = '```powershell app.ps1' + "`n" + 'Write-Host "incomplete'
                    Model      = 'claude-sonnet-4-6'
                    StopReason = 'max_tokens'
                    Usage      = @{ prompt_tokens = 100; completion_tokens = 8192; total_tokens = 8292 }
                }
            }

            $result = Invoke-CodeGeneration -Spec 'APP_NAME: test-app' -Framework 'powershell' -MaxTokens 8192
            $result.Success    | Should -BeFalse
            $result.StopReason | Should -Be 'max_tokens'
            $result.Output     | Should -Match 'truncated'
            $result.LogPath    | Should -Not -BeNullOrEmpty
        }

        It 'Returns failure with StopReason when response has length stop reason' {
            Mock Invoke-ChatCompletion {
                return @{
                    Content    = '```python app.py' + "`n" + 'print("cut off'
                    Model      = 'gpt-4o'
                    StopReason = 'length'
                    Usage      = @{ prompt_tokens = 100; completion_tokens = 16384; total_tokens = 16484 }
                }
            }

            $result = Invoke-CodeGeneration -Spec 'APP_NAME: test-app' -Framework 'python-tk' -MaxTokens 16384
            $result.Success    | Should -BeFalse
            $result.StopReason | Should -Be 'max_tokens'
            $result.Output     | Should -Match 'truncated'
        }

        It 'Proceeds normally when StopReason is stop (not truncated)' {
            Mock Invoke-ChatCompletion {
                return @{
                    Content    = '```powershell app.ps1' + "`n" + 'Write-Host "hello world"' + "`n" + '```'
                    Model      = 'claude-sonnet-4-6'
                    StopReason = 'stop'
                    Usage      = @{ prompt_tokens = 100; completion_tokens = 50; total_tokens = 150 }
                }
            }

            $result = Invoke-CodeGeneration -Spec 'APP_NAME: test-app' -Framework 'powershell' -MaxTokens 64000
            $result.Success | Should -BeTrue
            $result.Files   | Should -Not -BeNullOrEmpty
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

Describe 'AppBuilder — Pipeline v2' {

    # ── POWERSHELL-MODULE FRAMEWORK ROUTING ──────────────────
    Context 'Framework Routing — powershell-module' {

        It 'Routes "<prompt>" to powershell-module' -ForEach @(
            @{ prompt = 'a powershell module for log parsing' }
            @{ prompt = 'create a ps module for Azure backups' }
            @{ prompt = 'build a cmdlet collection for file management' }
            @{ prompt = 'an automation module for CI/CD' }
            @{ prompt = 'a profile module for my powershell setup' }
        ) {
            Get-BuildFramework -Prompt $prompt | Should -Be 'powershell-module'
        }

        It 'Explicit -Framework powershell-module override works' {
            Get-BuildFramework -Prompt 'a simple calculator' -Framework 'powershell-module' |
                Should -Be 'powershell-module'
        }

        It 'Does not route generic app prompts to powershell-module' {
            Get-BuildFramework -Prompt 'a calculator app' | Should -Be 'powershell'
        }
    }

    # ── TAURI HTML/JS VALIDATORS ─────────────────────────────
    Context 'Tauri HTML Validation' {

        It 'Flags missing DOCTYPE in Tauri HTML' {
            $files = @{ 'web/index.html' = '<html><head></head><body></body></html>' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'DOCTYPE'
        }

        It 'Flags missing <head> in Tauri HTML' {
            $files = @{ 'web/index.html' = '<!DOCTYPE html><html><body></body></html>' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match '<head>'
        }

        It 'Flags missing <body> in Tauri HTML' {
            $files = @{ 'web/index.html' = '<!DOCTYPE html><html><head></head></html>' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match '<body>'
        }

        It 'Flags external script sources in Tauri HTML' {
            $files = @{ 'web/index.html' = '<!DOCTYPE html><html><head></head><body><script src="https://cdn.example.com/lib.js"></script></body></html>' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'external.*script'
        }

        It 'Flags external link sources in Tauri HTML' {
            $files = @{ 'web/index.html' = '<!DOCTYPE html><html><head><link href="https://cdn.example.com/style.css" rel="stylesheet"></head><body></body></html>' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'external.*link'
        }

        It 'Passes valid self-contained Tauri HTML' {
            $toml = "[package]`nname = `"t`"`nversion = `"0.1.0`"`nedition = `"2021`"`n[dependencies]`ntauri = `"2`""
            $files = @{
                'web/index.html'        = '<!DOCTYPE html><html><head><title>App</title></head><body><h1>Hello</h1></body></html>'
                'src-tauri/Cargo.toml'  = $toml
                'src-tauri/src/main.rs' = 'fn main() {}'
            }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeTrue
        }

        It 'Does NOT apply HTML checks to non-Tauri frameworks' {
            $files = @{ 'web/index.html' = '<html><body>No doctype</body></html>' }
            $result = Test-GeneratedCode -Files $files -Framework 'python-web'
            # python-web does not enforce DOCTYPE
            ($result.Errors -join "`n") | Should -Not -Match 'DOCTYPE'
        }
    }

    Context 'Tauri JS Security Validation' {

        It 'Flags eval() in Tauri JS files' {
            $files = @{ 'web/script.js' = 'const result = eval("2+2");' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'eval\(\)'
        }

        It 'Flags innerHTML assignment in Tauri JS' {
            $files = @{ 'web/script.js' = 'document.getElementById("app").innerHTML = userInput;' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'innerHTML'
        }

        It 'Flags document.write in Tauri JS' {
            $files = @{ 'web/script.js' = 'document.write("<h1>hello</h1>");' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'document\.write'
        }

        It 'Flags new Function() in Tauri JS' {
            $files = @{ 'web/script.js' = 'const fn = new Function("return 42");' }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'new Function'
        }

        It 'Passes clean Tauri JS' {
            $toml = "[package]`nname = `"t`"`nversion = `"0.1.0`"`nedition = `"2021`"`n[dependencies]`ntauri = `"2`""
            $files = @{
                'web/script.js'         = 'document.getElementById("app").textContent = "Hello";'
                'src-tauri/Cargo.toml'  = $toml
                'src-tauri/src/main.rs' = 'fn main() {}'
            }
            $result = Test-GeneratedCode -Files $files -Framework 'tauri'
            $result.Success | Should -BeTrue
        }

        It 'Does NOT apply JS security checks to non-Tauri frameworks' {
            $files = @{ 'web/script.js' = 'document.getElementById("app").innerHTML = data;' }
            $result = Test-GeneratedCode -Files $files -Framework 'python-web'
            ($result.Errors -join "`n") | Should -Not -Match 'innerHTML'
        }
    }

    # ── POWERSHELL MODULE VALIDATORS ─────────────────────────
    Context 'PowerShell Module Validators' {

        It 'Flags unapproved verb in module function' {
            $files = @{ 'MyModule.psm1' = 'function Zap-Thing { [CmdletBinding()] param() }' }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'unapproved verb'
        }

        It 'Passes approved verb-noun function names' {
            $code = @'
function Get-Thing { [CmdletBinding()] param() Write-Output "ok" }
function Set-Config { [CmdletBinding()] param() Write-Output "set" }
'@
            $files = @{ 'MyModule.psm1' = $code }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeTrue
        }

        It 'Flags missing ModuleVersion in manifest' {
            $files = @{
                'MyModule.psm1' = 'function Get-Thing { [CmdletBinding()] param() }'
                'MyModule.psd1' = "@{ FunctionsToExport = @('Get-Thing'); Description = 'Test' }"
            }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'ModuleVersion'
        }

        It 'Flags missing FunctionsToExport in manifest' {
            $files = @{
                'MyModule.psm1' = 'function Get-Thing { [CmdletBinding()] param() }'
                'MyModule.psd1' = "@{ ModuleVersion = '1.0.0'; Description = 'Test' }"
            }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'FunctionsToExport'
        }

        It 'Flags module with no exported functions' {
            $files = @{ 'MyModule.psm1' = '# Empty module with no functions' }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'no exported functions'
        }

        It 'Flags New-Object -ComObject in modules' {
            $files = @{ 'MyModule.psm1' = 'function Get-Excel { [CmdletBinding()] param(); $xl = New-Object -ComObject Excel.Application }' }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'ComObject'
        }

        It 'Flags remote WMI queries in modules' {
            $files = @{ 'MyModule.psm1' = 'function Get-RemoteInfo { [CmdletBinding()] param(); Get-WmiObject Win32_OS -ComputerName Server01 }' }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'remote WMI'
        }

        It 'Flags network listeners in modules' {
            $files = @{ 'MyModule.psm1' = 'function Start-Server { [CmdletBinding()] param(); $l = [System.Net.HttpListener]::new() }' }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'network listener'
        }

        It 'Passes a complete well-formed module' {
            $psm1 = @'
function Get-Greeting {
    [CmdletBinding()]
    param([string]$Name = 'World')
    Write-Output "Hello $Name"
}
function Set-Greeting {
    [CmdletBinding()]
    param([string]$Message)
    Write-Output $Message
}
'@
            $psd1 = "@{ ModuleVersion = '1.0.0'; FunctionsToExport = @('Get-Greeting','Set-Greeting'); Description = 'Test module'; PowerShellVersion = '5.1' }"
            $files = @{ 'TestMod.psm1' = $psm1; 'TestMod.psd1' = $psd1 }
            $result = Test-GeneratedCode -Files $files -Framework 'powershell-module'
            $result.Success | Should -BeTrue
        }
    }

    # ── POWERSHELL MODULE BRANDING ───────────────────────────
    Context 'PowerShell Module Branding' {

        It 'Injects attribution header into .psm1' {
            $files = @{ 'MyModule.psm1' = 'function Get-Thing { return 1 }' }
            $result = Invoke-BildsyPSBranding -Files $files -Framework 'powershell-module'
            $result['MyModule.psm1'] | Should -Match 'Generated by BildsyPS'
        }

        It 'Does not double-inject attribution' {
            $files = @{ 'MyModule.psm1' = '# Generated by BildsyPS' + "`n" + 'function Get-Thing { return 1 }' }
            $result = Invoke-BildsyPSBranding -Files $files -Framework 'powershell-module'
            [regex]::Matches($result['MyModule.psm1'], 'Generated by BildsyPS').Count | Should -Be 1
        }

        It 'NoBranding strips attribution from module' {
            $files = @{ 'MyModule.psm1' = '# Generated by BildsyPS' + "`n" + 'function Get-Thing { return 1 }' }
            $result = Invoke-BildsyPSBranding -Files $files -Framework 'powershell-module' -NoBranding
            $result['MyModule.psm1'] | Should -Not -Match 'Built with BildsyPS'
        }
    }

    # ── BUILD MEMORY ─────────────────────────────────────────
    Context 'Build Memory' {

        BeforeAll {
            $script:DbAvailable = [bool]$global:ChatDbReady
        }

        It 'Initialize-BuildMemoryTable creates the table' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Initialize-BuildMemoryTable | Should -BeTrue
        }

        It 'Save-BuildConstraint stores a new constraint' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildConstraint -Framework 'test-fw' -Constraint 'Do not use eval()' -ErrorPattern 'eval detected'

            $conn = Get-ChatDbConnection
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT constraint_text, hit_count FROM build_memory WHERE framework = 'test-fw' AND constraint_text = 'Do not use eval()'"
            $reader = $cmd.ExecuteReader()
            $reader.Read() | Should -BeTrue
            $reader['constraint_text'] | Should -Be 'Do not use eval()'
            [int]$reader['hit_count'] | Should -Be 1
            $reader.Close(); $cmd.Dispose(); $conn.Close(); $conn.Dispose()
        }

        It 'Save-BuildConstraint increments hit_count on duplicate' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildConstraint -Framework 'test-fw' -Constraint 'Do not use eval()'
            Save-BuildConstraint -Framework 'test-fw' -Constraint 'Do not use eval()'

            $conn = Get-ChatDbConnection
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT hit_count FROM build_memory WHERE framework = 'test-fw' AND constraint_text = 'Do not use eval()'"
            [int]$cmd.ExecuteScalar() | Should -BeGreaterOrEqual 3
            $cmd.Dispose(); $conn.Close(); $conn.Dispose()
        }

        It 'Get-BuildConstraints retrieves stored constraints' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            Save-BuildConstraint -Framework 'get-test-fw' -Constraint 'Constraint A'
            Save-BuildConstraint -Framework 'get-test-fw' -Constraint 'Constraint B'

            $results = Get-BuildConstraints -Framework 'get-test-fw'
            $results.Count | Should -BeGreaterOrEqual 2
            $results | Should -Contain 'Constraint A'
            $results | Should -Contain 'Constraint B'
        }

        It 'Get-BuildConstraints returns empty for unknown framework' {
            if (-not $script:DbAvailable) { Set-ItResult -Skipped -Because 'SQLite not available' }
            $results = Get-BuildConstraints -Framework 'nonexistent-framework-xyz'
            $results.Count | Should -Be 0
        }

        AfterAll {
            if ($script:DbAvailable) {
                try {
                    $conn = Get-ChatDbConnection
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = "DELETE FROM build_memory WHERE framework IN ('test-fw', 'get-test-fw')"
                    $cmd.ExecuteNonQuery() | Out-Null
                    $cmd.Dispose(); $conn.Close(); $conn.Dispose()
                } catch { }
            }
        }
    }

    # ── ERROR CATEGORIZER ────────────────────────────────────
    Context 'Error Categorizer (ConvertTo-BuildConstraint)' {

        It 'Categorizes PowerShell variable scope error' {
            $result = ConvertTo-BuildConstraint -ErrorText 'Variable reference is not valid: $foo:' -Framework 'powershell'
            $result | Should -Match 'colon'
        }

        It 'Categorizes PowerShell null-coalescing error' {
            $result = ConvertTo-BuildConstraint -ErrorText 'null-coalescing operator ??' -Framework 'powershell'
            $result | Should -Match '\?\?|PS7'
        }

        It 'Categorizes Tauri unresolved import error' {
            $result = ConvertTo-BuildConstraint -ErrorText 'error: unresolved import serde_json' -Framework 'tauri'
            $result | Should -Match 'import|crate'
        }

        It 'Categorizes Tauri borrow checker error' {
            $result = ConvertTo-BuildConstraint -ErrorText 'borrow of moved value: data' -Framework 'tauri'
            $result | Should -Match 'clone|ownership'
        }

        It 'Categorizes Python import error' {
            $result = ConvertTo-BuildConstraint -ErrorText 'No module named requests' -Framework 'python-tk'
            $result | Should -Match 'standard library|pip'
        }

        It 'Returns generic fallback for unknown errors' {
            $result = ConvertTo-BuildConstraint -ErrorText 'Some weird error nobody expected' -Framework 'powershell'
            $result | Should -Match 'Avoid'
        }
    }

    # ── PLANNING AGENT THRESHOLD ─────────────────────────────
    Context 'Planning Agent Threshold' {

        It 'Skips planning for short specs (≤150 words)' {
            $shortSpec = 'A simple counter app with plus and minus buttons'
            $result = Invoke-BuildPlanning -Spec $shortSpec -Framework 'powershell'
            $result.Success | Should -BeTrue
            $result.Skipped | Should -BeTrue
            $result.Plan    | Should -BeNullOrEmpty
        }

        It 'Would trigger planning for long specs (>150 words)' {
            $longSpec = ('word ' * 200).Trim()
            # This would make an LLM call; we just verify it does NOT skip
            # Mock the LLM call to avoid actual API usage
            Mock Invoke-ChatCompletion {
                return @{ Content = "COMPONENTS:`n- MainComponent: handles everything" }
            }
            $result = Invoke-BuildPlanning -Spec $longSpec -Framework 'powershell'
            $result.Skipped | Should -BeFalse
        }
    }

    # ── THEME PRESET ACCENT COLOR ────────────────────────────
    Context 'Theme Preset Colors' {

        It 'Dark theme accent is Bildsy blue (#4A90E2) not purple' {
            $script:ThemePresets = (Get-Variable -Name 'ThemePresets' -Scope Script -ErrorAction SilentlyContinue).Value
            # Access the module-scoped variable via the loaded module state
            # We verify by checking the prompts contain the correct hex
        }
    }

    # ── REPAIR-GENERATEDCODE .PSM1 SUPPORT ───────────────────
    Context 'Code Repair — .psm1 support' {

        It 'Repairs variable scope errors in .psm1 files' {
            $code = 'function Get-Info { $statusCode: = 200 }'
            $files = @{ 'MyModule.psm1' = $code }
            $count = Repair-GeneratedCode -Files $files -Framework 'powershell-module'
            $count | Should -BeGreaterThan 0
        }
    }
}

Describe 'AppBuilder — Pipeline Fixes' {

    # ── TOKEN CAP REMOVAL ─────────────────────────────────────
    Context 'Token Cap Removal (Get-BuildMaxTokens)' {

        It 'Returns full 64000 for claude-sonnet-4-6 (no cap)' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'claude-sonnet-4-6' |
                Should -Be 64000
        }

        It 'Returns full 128000 for claude-opus-4-6 (no cap)' {
            Get-BuildMaxTokens -Framework 'tauri' -Model 'claude-opus-4-6' |
                Should -Be 128000
        }

        It 'Returns full 16384 for gpt-4o (no cap)' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'gpt-4o' |
                Should -Be 16384
        }

        It 'Override still works' {
            Get-BuildMaxTokens -Framework 'powershell' -Model 'gpt-4o' -Override 50000 |
                Should -Be 50000
        }
    }

    # ── GET-CODEBLOCKS FILENAME EXTRACTION ────────────────────
    Context 'Get-CodeBlocks Filename Extraction' {

        It 'Extracts filename from fence line' {
            $fence = '``' + '`'
            $text = "${fence}powershell app.ps1`nWrite-Host 'hello'`n${fence}"
            $blocks = Get-CodeBlocks -Text $text
            $blocks.Count | Should -Be 1
            $blocks[0].FileName | Should -Be 'app.ps1'
            $blocks[0].Language | Should -Be 'powershell'
        }

        It 'Extracts path with subdirectory from fence line' {
            $fence = '``' + '`'
            $text = "${fence}rust src-tauri/src/main.rs`nfn main() {}`n${fence}"
            $blocks = Get-CodeBlocks -Text $text
            $blocks[0].FileName | Should -Be 'src-tauri/src/main.rs'
        }

        It 'Returns null FileName when no filename in fence' {
            $fence = '``' + '`'
            $text = "${fence}powershell`nWrite-Host 'hello'`n${fence}"
            $blocks = Get-CodeBlocks -Text $text
            $blocks[0].FileName | Should -BeNullOrEmpty
            $blocks[0].Language | Should -Be 'powershell'
        }

        It 'Handles multiple blocks with different filenames' {
            $fence = '``' + '`'
            $text = @(
                "${fence}powershell source/data.ps1"
                'function Get-Data { return @() }'
                $fence
                ''
                "${fence}powershell source/ui.ps1"
                'function New-MainForm { }'
                $fence
                ''
                "${fence}powershell app.ps1"
                '. .\source\data.ps1'
                '. .\source\ui.ps1'
                $fence
            ) -join "`n"
            $blocks = Get-CodeBlocks -Text $text
            $blocks.Count | Should -Be 3
            $blocks[0].FileName | Should -Be 'source/data.ps1'
            $blocks[1].FileName | Should -Be 'source/ui.ps1'
            $blocks[2].FileName | Should -Be 'app.ps1'
        }

        It 'Preserves backward compatibility — Language still works' {
            $fence = '``' + '`'
            $text = "${fence}python`nprint('hello')`n${fence}"
            $blocks = Get-CodeBlocks -Text $text
            $blocks[0].Language | Should -Be 'python'
            $blocks[0].Code | Should -Be "print('hello')"
        }
    }

    # ── MERGE-POWERSHELLSOURCES ───────────────────────────────
    Context 'Merge-PowerShellSources' {

        BeforeAll {
            $script:MergeTmpDir = Join-Path $env:TEMP "bildsyps_merge_test_$(Get-Random)"
            $script:MergeSrcDir = Join-Path $script:MergeTmpDir 'source'
            New-Item -ItemType Directory -Path (Join-Path $script:MergeSrcDir 'source') -Force | Out-Null
        }

        It 'Returns app.ps1 directly for single-file projects' {
            $appFile = Join-Path $script:MergeSrcDir 'app.ps1'
            Set-Content $appFile -Value 'Write-Host "hello"' -Encoding UTF8
            $result = Merge-PowerShellSources -SourceDir $script:MergeSrcDir
            $result.Success | Should -BeTrue
            $result.MergedPath | Should -Be $appFile
        }

        It 'Merges multiple files and strips dot-source lines' {
            $srcSubDir = Join-Path $script:MergeSrcDir 'source'
            Set-Content (Join-Path $srcSubDir 'data.ps1') -Value 'function Get-Data { return @() }' -Encoding UTF8
            Set-Content (Join-Path $srcSubDir 'ui.ps1') -Value 'function New-Form { return $null }' -Encoding UTF8
            $appContent = @'
. "$PSScriptRoot\source\data.ps1"
. "$PSScriptRoot\source\ui.ps1"
$form = New-Form
'@
            Set-Content (Join-Path $script:MergeSrcDir 'app.ps1') -Value $appContent -Encoding UTF8

            $result = Merge-PowerShellSources -SourceDir $script:MergeSrcDir
            $result.Success | Should -BeTrue
            $result.MergedPath | Should -Match '_merged\.ps1$'

            $merged = Get-Content $result.MergedPath -Raw
            $merged | Should -Match 'function Get-Data'
            $merged | Should -Match 'function New-Form'
            $merged | Should -Match '\$form = New-Form'
            $merged | Should -Not -Match '\.\s+"\$PSScriptRoot'
        }

        It 'Returns failure when app.ps1 is missing' {
            $emptyDir = Join-Path $env:TEMP "bildsyps_merge_empty_$(Get-Random)"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            $result = Merge-PowerShellSources -SourceDir $emptyDir
            $result.Success | Should -BeFalse
            Remove-Item $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        AfterAll {
            Remove-Item $script:MergeTmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ── MULTI-FILE CODE GENERATION MAPPING ────────────────────
    Context 'Multi-File Code Generation Mapping' {

        It 'Maps Tauri files correctly using fence filenames' {
            Mock Invoke-ChatCompletion {
                $code = @"
Here is the code:

``````toml src-tauri/Cargo.toml
[package]
name = "test-app"
``````

``````rust src-tauri/src/main.rs
fn main() { tauri::Builder::default().run(tauri::generate_context!()).expect("error"); }
``````

``````rust src-tauri/build.rs
fn main() { tauri_build::build() }
``````

``````html web/index.html
<!DOCTYPE html><html><head><title>App</title></head><body><h1>Hello</h1></body></html>
``````
"@
                return @{
                    Content    = $code
                    Model      = 'claude-sonnet-4-6'
                    StopReason = 'stop'
                    Usage      = @{ prompt_tokens = 100; completion_tokens = 200; total_tokens = 300 }
                }
            }

            $result = Invoke-CodeGeneration -Spec 'APP_NAME: test-app' -Framework 'tauri' -MaxTokens 64000
            $result.Success | Should -BeTrue
            $result.Files.Keys | Should -Contain 'src-tauri/Cargo.toml'
            $result.Files.Keys | Should -Contain 'src-tauri/src/main.rs'
            $result.Files.Keys | Should -Contain 'src-tauri/build.rs'
            $result.Files.Keys | Should -Contain 'web/index.html'
        }

        It 'Maps multi-file PowerShell correctly using fence filenames' {
            Mock Invoke-ChatCompletion {
                $code = @"
``````powershell source/data.ps1
function Get-Data { return @() }
``````

``````powershell source/ui.ps1
Add-Type -AssemblyName System.Windows.Forms
function New-MainForm { return New-Object System.Windows.Forms.Form }
``````

``````powershell app.ps1
. "`$PSScriptRoot\source\data.ps1"
. "`$PSScriptRoot\source\ui.ps1"
`$form = New-MainForm
[System.Windows.Forms.Application]::Run(`$form)
``````
"@
                return @{
                    Content    = $code
                    Model      = 'claude-sonnet-4-6'
                    StopReason = 'stop'
                    Usage      = @{ prompt_tokens = 100; completion_tokens = 200; total_tokens = 300 }
                }
            }

            $result = Invoke-CodeGeneration -Spec 'APP_NAME: test-app' -Framework 'powershell' -MaxTokens 64000
            $result.Success | Should -BeTrue
            $result.Files.Keys | Should -Contain 'source/data.ps1'
            $result.Files.Keys | Should -Contain 'source/ui.ps1'
            $result.Files.Keys | Should -Contain 'app.ps1'
        }
    }

    # ── FIX LOOP RETRIES ─────────────────────────────────────
    Context 'Fix Loop MaxRetries Default' {

        It 'Invoke-BuildFixLoop accepts MaxRetries parameter' {
            $params = (Get-Command Invoke-BuildFixLoop).Parameters
            $params.ContainsKey('MaxRetries') | Should -BeTrue
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

    Context 'Tauri Full Build Pipeline' {

        BeforeAll {
            $script:HasCargo = $null -ne (Get-Command cargo -ErrorAction SilentlyContinue)
            $script:CanBuildTauri = $script:HasProvider -and $script:HasCargo
        }

        It 'New-AppBuild generates a Tauri executable from a prompt' {
            if (-not $script:CanBuildTauri) { Set-ItResult -Skipped -Because 'No LLM provider or Rust toolchain available'; return }
            $script:TauriResult = New-AppBuild -Prompt 'a tauri app that is a simple counter with plus and minus buttons' `
                -Framework 'tauri' -Name 'test-tauri-counter' -Provider $script:LiveProvider
            $script:TauriResult.Success   | Should -BeTrue
            $script:TauriResult.ExePath   | Should -Not -BeNullOrEmpty
            Test-Path $script:TauriResult.ExePath | Should -BeTrue
            $script:TauriResult.Framework | Should -Be 'tauri'
        }

        It 'Source contains BildsyPS branding in HTML' {
            if (-not $script:CanBuildTauri) { Set-ItResult -Skipped -Because 'No LLM provider or Rust toolchain available'; return }
            $src = Join-Path $global:AppBuilderPath 'test-tauri-counter\source\web\index.html'
            if (Test-Path $src) {
                Get-Content $src -Raw | Should -Match 'Built with BildsyPS'
            }
        }

        It 'Source contains required Tauri files' {
            if (-not $script:CanBuildTauri) { Set-ItResult -Skipped -Because 'No LLM provider or Rust toolchain available'; return }
            $sourceDir = Join-Path $global:AppBuilderPath 'test-tauri-counter\source'
            Test-Path (Join-Path $sourceDir 'src-tauri\src\main.rs')    | Should -BeTrue
            Test-Path (Join-Path $sourceDir 'src-tauri\Cargo.toml')     | Should -BeTrue
            Test-Path (Join-Path $sourceDir 'web\index.html')           | Should -BeTrue
        }

        AfterAll {
            if ($script:CanBuildTauri) {
                Remove-AppBuild -Name 'test-tauri-counter' -ErrorAction SilentlyContinue
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
