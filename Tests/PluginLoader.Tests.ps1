BeforeAll {
    . "$PSScriptRoot\_Bootstrap.ps1"
    # PluginLoader is loaded after IntentAliasSystem — load it now
    . "$global:ModulesPath\PluginLoader.ps1"
}

AfterAll {
    Remove-TestTempRoot
}

Describe 'PluginLoader — Offline' {

    BeforeAll {
        # Create a test plugin directory with a valid plugin
        $testPluginDir = "$global:BildsyPSHome\plugins"
        if (-not (Test-Path $testPluginDir)) {
            New-Item -ItemType Directory -Path $testPluginDir -Force | Out-Null
        }
        # Create Config dir for plugin settings
        $testPluginConfig = "$global:BildsyPSHome\plugins\Config"
        if (-not (Test-Path $testPluginConfig)) {
            New-Item -ItemType Directory -Path $testPluginConfig -Force | Out-Null
        }
    }

    Context 'Import-BildsyPSPlugins with valid plugin' {
        BeforeAll {
            # Write a minimal valid plugin
            $pluginCode = @'
$PluginInfo = @{
    Name        = 'TestPlugin'
    Description = 'A test plugin for Pester'
    Author      = 'Test'
    Version     = '1.0.0'
}
$PluginIntents = @{
    'test_plugin_greet' = { param($name) @{ Success = $true; Output = "Hello, $name!" } }
}
$PluginMetadata = @{
    'test_plugin_greet' = @{
        Category    = 'custom'
        Description = 'Greet someone'
        Parameters  = @(
            @{ Name = 'name'; Required = $true; Description = 'Name to greet' }
        )
        Safety      = 'Safe'
    }
}
'@
            Set-Content -Path "$global:PluginsPath\TestPlugin.ps1" -Value $pluginCode -Encoding UTF8
            # Clear any previous load state
            $global:LoadedPlugins = [ordered]@{}
            Import-BildsyPSPlugins -Quiet
        }

        AfterAll {
            # Clean up
            if ($global:LoadedPlugins.Contains('TestPlugin')) {
                Unregister-BildsyPSPlugin -Name 'TestPlugin'
            }
            Remove-Item "$global:PluginsPath\TestPlugin.ps1" -Force -ErrorAction SilentlyContinue
        }

        It 'Loads the plugin into LoadedPlugins' {
            $global:LoadedPlugins.Contains('TestPlugin') | Should -BeTrue
        }

        It 'Merges plugin intents into IntentAliases' {
            $global:IntentAliases.Contains('test_plugin_greet') | Should -BeTrue
        }

        It 'Merges plugin metadata into IntentMetadata' {
            $global:IntentMetadata.ContainsKey('test_plugin_greet') | Should -BeTrue
            $global:IntentMetadata['test_plugin_greet'].Description | Should -Be 'Greet someone'
        }

        It 'Plugin intent is callable via Invoke-IntentAction' {
            $result = Invoke-IntentAction -Intent 'test_plugin_greet' -Payload @{ name = 'Pester' } -Force
            $result.Success | Should -BeTrue
            $result.Output | Should -Match 'Hello.*Pester'
        }
    }

    Context 'Unregister-BildsyPSPlugin' {
        BeforeAll {
            $pluginCode = @'
$PluginIntents = @{
    'unreg_plugin_test' = { @{ Success = $true; Output = 'unreg test' } }
}
'@
            Set-Content -Path "$global:PluginsPath\UnregTest.ps1" -Value $pluginCode -Encoding UTF8
            $global:LoadedPlugins = [ordered]@{}
            Import-BildsyPSPlugins -Quiet
        }

        AfterAll {
            Remove-Item "$global:PluginsPath\UnregTest.ps1" -Force -ErrorAction SilentlyContinue
        }

        It 'Removes plugin intents from registries' {
            $global:LoadedPlugins.Contains('UnregTest') | Should -BeTrue
            $global:IntentAliases.Contains('unreg_plugin_test') | Should -BeTrue
            Unregister-BildsyPSPlugin -Name 'UnregTest'
            $global:LoadedPlugins.Contains('UnregTest') | Should -BeFalse
            $global:IntentAliases.Contains('unreg_plugin_test') | Should -BeFalse
        }

        It 'Handles unregistering a non-loaded plugin gracefully' {
            { Unregister-BildsyPSPlugin -Name 'NonExistentPlugin' } | Should -Not -Throw
        }
    }

    Context 'Plugin conflict detection' {
        BeforeAll {
            # Create plugin that tries to register an existing core intent
            $conflictCode = @'
$PluginIntents = @{
    'list_files' = { @{ Success = $true; Output = 'conflict' } }
}
'@
            Set-Content -Path "$global:PluginsPath\ConflictPlugin.ps1" -Value $conflictCode -Encoding UTF8
            $global:LoadedPlugins = [ordered]@{}
            Import-BildsyPSPlugins -Quiet
        }

        AfterAll {
            if ($global:LoadedPlugins.Contains('ConflictPlugin')) {
                Unregister-BildsyPSPlugin -Name 'ConflictPlugin'
            }
            Remove-Item "$global:PluginsPath\ConflictPlugin.ps1" -Force -ErrorAction SilentlyContinue
        }

        It 'Does not overwrite core intents with plugin intents' {
            # list_files is a core intent — it should not be replaced
            $result = Invoke-IntentAction -Intent 'list_files' -Force
            # If the conflict plugin overwrote it, Output would be 'conflict'
            $result.Output | Should -Not -Be 'conflict'
        }
    }

    Context 'Plugin validation' {
        It 'Skips files with no PluginIntents' {
            $badCode = '# This plugin has no $PluginIntents'
            Set-Content -Path "$global:PluginsPath\BadPlugin.ps1" -Value $badCode -Encoding UTF8
            $global:LoadedPlugins = [ordered]@{}
            Import-BildsyPSPlugins -Quiet
            $global:LoadedPlugins.Contains('BadPlugin') | Should -BeFalse
            Remove-Item "$global:PluginsPath\BadPlugin.ps1" -Force -ErrorAction SilentlyContinue
        }

        It 'Skips files starting with underscore' {
            $disabledCode = '$PluginIntents = @{ disabled_intent = { @{ Success = $true } } }'
            Set-Content -Path "$global:PluginsPath\_DisabledPlugin.ps1" -Value $disabledCode -Encoding UTF8
            $global:LoadedPlugins = [ordered]@{}
            Import-BildsyPSPlugins -Quiet
            $global:LoadedPlugins.Contains('_DisabledPlugin') | Should -BeFalse
            $global:IntentAliases.Contains('disabled_intent') | Should -BeFalse
            Remove-Item "$global:PluginsPath\_DisabledPlugin.ps1" -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Plugin configuration' {
        BeforeAll {
            $configPlugin = @'
$PluginIntents = @{
    'cfg_test_intent' = { @{ Success = $true; Output = 'cfg test' } }
}
$PluginConfig = @{
    'theme' = @{ Default = 'dark'; Description = 'Color theme' }
    'timeout' = @{ Default = 30; Description = 'Timeout seconds' }
}
'@
            Set-Content -Path "$global:PluginsPath\CfgPlugin.ps1" -Value $configPlugin -Encoding UTF8
            $global:LoadedPlugins = [ordered]@{}
            Import-BildsyPSPlugins -Quiet
        }

        AfterAll {
            if ($global:LoadedPlugins.Contains('CfgPlugin')) {
                Unregister-BildsyPSPlugin -Name 'CfgPlugin'
            }
            Remove-Item "$global:PluginsPath\CfgPlugin.ps1" -Force -ErrorAction SilentlyContinue
            Remove-Item "$global:PluginConfigPath\CfgPlugin.json" -Force -ErrorAction SilentlyContinue
        }

        It 'Loads default config values' {
            $val = Get-PluginConfig -Plugin 'CfgPlugin' -Key 'theme'
            $val | Should -Be 'dark'
        }

        It 'Set-PluginConfig persists to JSON file' {
            Set-PluginConfig -Plugin 'CfgPlugin' -Key 'theme' -Value 'light'
            $val = Get-PluginConfig -Plugin 'CfgPlugin' -Key 'theme'
            $val | Should -Be 'light'
            # Verify it wrote to disk
            $configFile = Join-Path $global:PluginConfigPath 'CfgPlugin.json'
            Test-Path $configFile | Should -BeTrue
        }
    }

    Context 'Version compatibility' {
        It 'Skips plugin requiring higher BildsyPS version' {
            $futurePlugin = @'
$PluginInfo = @{
    Name = 'FuturePlugin'
    MinBildsyPSVersion = '99.0.0'
}
$PluginIntents = @{
    'future_intent' = { @{ Success = $true } }
}
'@
            Set-Content -Path "$global:PluginsPath\FuturePlugin.ps1" -Value $futurePlugin -Encoding UTF8
            $global:LoadedPlugins = [ordered]@{}
            Import-BildsyPSPlugins -Quiet
            $global:LoadedPlugins.Contains('FuturePlugin') | Should -BeFalse
            $global:IntentAliases.Contains('future_intent') | Should -BeFalse
            Remove-Item "$global:PluginsPath\FuturePlugin.ps1" -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Get-BildsyPSPlugins' {
        It 'Does not throw' {
            { Get-BildsyPSPlugins } | Should -Not -Throw
        }
    }
}
