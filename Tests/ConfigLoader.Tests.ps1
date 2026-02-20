BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1" -Minimal
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'ConfigLoader — Offline' {

    Context 'Import-EnvFile' {
        It 'Returns empty hashtable when file does not exist' {
            $result = Import-EnvFile -Path "$global:BildsyPSHome\config\nonexistent.env"
            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 0
        }

        It 'Parses KEY=VALUE pairs' {
            $envFile = "$global:BildsyPSHome\config\test.env"
            Set-Content -Path $envFile -Value "API_KEY=abc123`nDB_HOST=localhost"
            $result = Import-EnvFile -Path $envFile
            $result['API_KEY'] | Should -Be 'abc123'
            $result['DB_HOST'] | Should -Be 'localhost'
        }

        It 'Strips double quotes from values' {
            $envFile = "$global:BildsyPSHome\config\test-quotes.env"
            Set-Content -Path $envFile -Value 'MY_SECRET="hello world"'
            $result = Import-EnvFile -Path $envFile
            $result['MY_SECRET'] | Should -Be 'hello world'
        }

        It 'Strips single quotes from values' {
            $envFile = "$global:BildsyPSHome\config\test-sq.env"
            Set-Content -Path $envFile -Value "TOKEN='sk-12345'"
            $result = Import-EnvFile -Path $envFile
            $result['TOKEN'] | Should -Be 'sk-12345'
        }

        It 'Skips comments and empty lines' {
            $envFile = "$global:BildsyPSHome\config\test-comments.env"
            Set-Content -Path $envFile -Value "# This is a comment`n`nVALID_KEY=value"
            $result = Import-EnvFile -Path $envFile
            $result.Count | Should -Be 1
            $result['VALID_KEY'] | Should -Be 'value'
        }

        It 'Skips the literal placeholder value your-*' {
            $envFile = "$global:BildsyPSHome\config\test-placeholder.env"
            Set-Content -Path $envFile -Value "API_KEY=your-*`nREAL_KEY=abc"
            $result = Import-EnvFile -Path $envFile
            $result.ContainsKey('API_KEY') | Should -BeFalse
            $result['REAL_KEY'] | Should -Be 'abc'
        }

        It 'Sets environment variables for parsed keys' {
            $envFile = "$global:BildsyPSHome\config\test-envvar.env"
            $uniqueKey = "BILDSYPS_TEST_$(Get-Random)"
            Set-Content -Path $envFile -Value "$uniqueKey=testvalue"
            Import-EnvFile -Path $envFile
            [Environment]::GetEnvironmentVariable($uniqueKey) | Should -Be 'testvalue'
            [Environment]::SetEnvironmentVariable($uniqueKey, $null, 'Process')
        }

        It 'Handles single-line .env file without char coercion' {
            $envFile = "$global:BildsyPSHome\config\test-single.env"
            Set-Content -Path $envFile -Value "ONLY_KEY=onlyvalue"
            $result = Import-EnvFile -Path $envFile
            $result['ONLY_KEY'] | Should -Be 'onlyvalue'
        }
    }

    Context 'Get-ConfigValue' {
        BeforeAll {
            $global:LoadedConfig = @{ 'EXISTING_KEY' = 'from_config' }
        }

        It 'Returns value from loaded config' {
            Get-ConfigValue -Key 'EXISTING_KEY' | Should -Be 'from_config'
        }

        It 'Falls back to environment variable' {
            $uniqueKey = "BILDSYPS_GETVAL_$(Get-Random)"
            [Environment]::SetEnvironmentVariable($uniqueKey, 'from_env', 'Process')
            Get-ConfigValue -Key $uniqueKey | Should -Be 'from_env'
            [Environment]::SetEnvironmentVariable($uniqueKey, $null, 'Process')
        }

        It 'Returns default when key not found anywhere' {
            Get-ConfigValue -Key 'NONEXISTENT_KEY_XYZ' -Default 'fallback' | Should -Be 'fallback'
        }

        It 'Returns null when key not found and no default' {
            Get-ConfigValue -Key 'NONEXISTENT_KEY_XYZ' | Should -BeNullOrEmpty
        }
    }

    Context 'Set-ConfigValue' {
        It 'Creates .env file and writes key' {
            $envFile = "$global:BildsyPSHome\config\set-test.env"
            $global:EnvFilePath = $envFile
            Set-ConfigValue -Key 'NEW_KEY' -Value 'new_value'
            Test-Path $envFile | Should -BeTrue
            $content = Get-Content $envFile -Raw
            $content | Should -Match 'NEW_KEY=new_value'
        }

        It 'Updates existing key in .env file' {
            $envFile = "$global:BildsyPSHome\config\set-update.env"
            Set-Content -Path $envFile -Value "MYKEY=old"
            $global:EnvFilePath = $envFile
            Set-ConfigValue -Key 'MYKEY' -Value 'new'
            $content = Get-Content $envFile -Raw
            $content | Should -Match 'MYKEY=new'
            $content | Should -Not -Match 'MYKEY=old'
        }

        It 'Handles single-line .env file update without crash' {
            $envFile = "$global:BildsyPSHome\config\set-single.env"
            Set-Content -Path $envFile -Value "SOLO=original"
            $global:EnvFilePath = $envFile
            { Set-ConfigValue -Key 'SOLO' -Value 'updated' } | Should -Not -Throw
            $content = Get-Content $envFile -Raw
            $content | Should -Match 'SOLO=updated'
        }

        It 'Updates in-memory config and environment variable' {
            $envFile = "$global:BildsyPSHome\config\set-mem.env"
            $global:EnvFilePath = $envFile
            Set-ConfigValue -Key 'MEM_KEY' -Value 'mem_val'
            $global:LoadedConfig['MEM_KEY'] | Should -Be 'mem_val'
            [Environment]::GetEnvironmentVariable('MEM_KEY') | Should -Be 'mem_val'
            [Environment]::SetEnvironmentVariable('MEM_KEY', $null, 'Process')
        }
    }
}
