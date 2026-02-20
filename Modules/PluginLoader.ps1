# ============= PluginLoader.ps1 — Drop-in Plugin System =============
# Scans Plugins/ for .ps1 files that export $PluginIntents (and optionally
# $PluginMetadata, $PluginWorkflows, $PluginCategories) and merges them
# into the global intent registries.
#
# Must be loaded AFTER IntentAliasSystem.ps1 so the registries exist.

$global:PluginsPath = "$global:BildsyPSHome\plugins"
$global:PluginConfigPath = "$global:BildsyPSHome\plugins\Config"
$global:BundledPluginsPath = "$PSScriptRoot\..\Plugins"
$global:LoadedPlugins = [ordered]@{}
$global:PluginHelpers = @{}
$global:PluginSettings = @{}
if (-not $global:BildsyPSVersion) { $global:BildsyPSVersion = '0.9.0' }

function Resolve-PluginLoadOrder {
    <#
    .SYNOPSIS
    Topological sort of plugin files based on $PluginInfo.Dependencies declared
    inside each file. Plugins without dependencies come first. Circular deps
    and missing deps are detected and those plugins are excluded with warnings.
    #>
    param([System.IO.FileInfo[]]$Files)

    # Quick-scan each file for a Dependencies line without full dot-source
    $depMap = @{}
    foreach ($f in $Files) {
        $deps = @()
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match "Dependencies\s*=\s*@\(([^)]*)\)") {
            $raw = $Matches[1]
            $deps = @($raw -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ })
        }
        $depMap[$f.BaseName] = @{ File = $f; Dependencies = $deps }
    }

    $sorted = [System.Collections.ArrayList]::new()
    $visited = @{}
    $inStack = @{}
    $warnings = @()

    function Visit($name) {
        if ($inStack[$name]) {
            $script:warnings += "Circular dependency detected involving '$name' — skipping"
            return $false
        }
        if ($visited[$name]) { return $true }
        $inStack[$name] = $true

        if ($depMap.ContainsKey($name)) {
            foreach ($dep in $depMap[$name].Dependencies) {
                # core: prefix means a core module, not a plugin
                if ($dep -like 'core:*') { continue }
                if (-not $depMap.ContainsKey($dep)) {
                    $script:warnings += "$name — dependency '$dep' not found among active plugins, skipping"
                    $inStack[$name] = $false
                    return $false
                }
                if (-not (Visit $dep)) {
                    $inStack[$name] = $false
                    return $false
                }
            }
        }

        $inStack[$name] = $false
        $visited[$name] = $true
        if ($depMap.ContainsKey($name)) {
            $sorted.Add($depMap[$name].File) | Out-Null
        }
        return $true
    }

    foreach ($name in $depMap.Keys) {
        if (-not $visited[$name]) {
            Visit $name | Out-Null
        }
    }

    return @{ Sorted = @($sorted); Warnings = @($warnings) }
}

function Import-BildsyPSPlugins {
    <#
    .SYNOPSIS
    Load all .ps1 plugin files from the Plugins/ directory and merge their
    intents, metadata, workflows, and categories into the global registries.

    .DESCRIPTION
    Each plugin file is dot-sourced in its own child scope. The loader looks
    for well-known variables ($PluginIntents, $PluginMetadata, etc.) and
    merges them into the global registries. Conflicts are logged and skipped
    so a rogue plugin cannot silently overwrite core intents.

    Files starting with '_' are inactive (convention for examples/disabled).

    .PARAMETER Quiet
    Suppress summary output (used during profile startup).

    .PARAMETER Name
    Load only a specific plugin by base name (e.g. "MyPlugin" for MyPlugin.ps1).
    #>
    param(
        [switch]$Quiet,
        [string]$Name
    )

    # Collect plugins from both user dir (~/.bildsyps/plugins) and bundled dir (module Plugins/)
    $pluginFiles = @()
    $searchPaths = @($global:PluginsPath, $global:BundledPluginsPath) | Where-Object { $_ -and (Test-Path $_) }
    if ($searchPaths.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "Plugins directory not found -- skipping plugin load." -ForegroundColor DarkGray
        }
        return
    }
    $seen = @{}
    foreach ($sp in $searchPaths) {
        Get-ChildItem "$sp\*.ps1" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_*' } |
            ForEach-Object {
                # User plugins override bundled plugins with the same name
                if (-not $seen.ContainsKey($_.Name)) {
                    $seen[$_.Name] = $true
                    $pluginFiles += $_
                }
            }
    }
    $pluginFiles = $pluginFiles | Sort-Object Name

    if ($Name) {
        $pluginFiles = $pluginFiles | Where-Object { $_.BaseName -eq $Name }
        if ($pluginFiles.Count -eq 0) {
            Write-Host "Plugin '$Name' not found in $global:PluginsPath" -ForegroundColor Red
            return
        }
    }

    if ($pluginFiles.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "No active plugins found in Plugins/. Files starting with '_' are ignored." -ForegroundColor DarkGray
        }
        return
    }

    # ── Dependency-aware load ordering ──
    if (-not $Name -and $pluginFiles.Count -gt 1) {
        $depResult = Resolve-PluginLoadOrder -Files $pluginFiles
        if ($depResult.Sorted.Count -gt 0) {
            $pluginFiles = $depResult.Sorted
        }
        # Dep warnings are collected and shown with other warnings below
        $depWarnings = $depResult.Warnings
    }
    else {
        $depWarnings = @()
    }

    $loaded      = 0
    $skipped     = 0
    $intentCount = 0
    $warnings    = @($depWarnings)

    foreach ($file in $pluginFiles) {
        $pluginStart = Get-Date

        # Clear variables from previous iteration
        $PluginIntents    = $null
        $PluginMetadata   = $null
        $PluginWorkflows  = $null
        $PluginCategories = $null
        $PluginInfo       = $null
        $PluginConfig     = $null
        $PluginHooks      = $null
        $PluginTests      = $null
        $PluginFunctions  = $null

        try {
            . $file.FullName
        }
        catch {
            Write-Host "  [SKIP] $($file.Name) — load error: $($_.Exception.Message)" -ForegroundColor Red
            $skipped++
            continue
        }

        # ── Validate: $PluginIntents is required ──
        if (-not $PluginIntents -or $PluginIntents -isnot [hashtable] -or $PluginIntents.Count -eq 0) {
            Write-Host "  [SKIP] $($file.Name) — no `$PluginIntents hashtable found" -ForegroundColor Yellow
            $skipped++
            continue
        }

        $pluginName       = $file.BaseName
        $pluginIntentNames = @()
        $pluginWorkflowNames = @()
        $pluginCategoryNames = @()
        $pluginFunctionNames = @()
        $pluginTestNames = @()

        # ── Validate scriptblock types ──
        $badIntents = @($PluginIntents.Keys | Where-Object { $PluginIntents[$_] -isnot [scriptblock] })
        if ($badIntents.Count -gt 0) {
            Write-Host "  [SKIP] $pluginName — non-scriptblock values for: $($badIntents -join ', ')" -ForegroundColor Red
            $skipped++
            continue
        }

        # ── Version compatibility check ──
        if ($PluginInfo) {
            if ($PluginInfo.MinBildsyPSVersion) {
                if ([version]$global:BildsyPSVersion -lt [version]$PluginInfo.MinBildsyPSVersion) {
                    $warnings += "$pluginName — requires BildsyPS >= $($PluginInfo.MinBildsyPSVersion), current is $global:BildsyPSVersion, skipping"
                    $skipped++
                    continue
                }
            }
            if ($PluginInfo.MaxBildsyPSVersion) {
                if ([version]$global:BildsyPSVersion -gt [version]$PluginInfo.MaxBildsyPSVersion) {
                    $warnings += "$pluginName — requires BildsyPS <= $($PluginInfo.MaxBildsyPSVersion), current is $global:BildsyPSVersion, skipping"
                    $skipped++
                    continue
                }
            }
        }

        # ── 1. Merge categories (before metadata so category keys exist) ──
        if ($PluginCategories -and $PluginCategories -is [hashtable]) {
            foreach ($catKey in $PluginCategories.Keys) {
                if (-not $global:CategoryDefinitions.ContainsKey($catKey)) {
                    $global:CategoryDefinitions[$catKey] = $PluginCategories[$catKey]
                    $pluginCategoryNames += $catKey
                }
            }
        }

        # ── 2. Merge metadata with validation ──
        if ($PluginMetadata -and $PluginMetadata -is [hashtable]) {
            foreach ($intentName in $PluginMetadata.Keys) {
                if ($global:IntentMetadata.ContainsKey($intentName)) {
                    $warnings += "$pluginName — metadata '$intentName' already exists, skipping"
                }
                else {
                    $meta = $PluginMetadata[$intentName]
                    # Validate category reference
                    if ($meta.Category -and -not $global:CategoryDefinitions.ContainsKey($meta.Category)) {
                        $warnings += "$pluginName — intent '$intentName' references unknown category '$($meta.Category)'"
                    }
                    $global:IntentMetadata[$intentName] = $meta
                }
            }
        }

        # ── 3. Merge intents ──
        foreach ($intentName in $PluginIntents.Keys) {
            if ($global:IntentAliases.Contains($intentName)) {
                $warnings += "$pluginName — intent '$intentName' already registered, skipping"
            }
            else {
                $global:IntentAliases[$intentName] = $PluginIntents[$intentName]
                $pluginIntentNames += $intentName
                $intentCount++
            }
        }

        # ── 4. Merge workflows ──
        if ($PluginWorkflows -and $PluginWorkflows -is [hashtable]) {
            foreach ($wfName in $PluginWorkflows.Keys) {
                if ($global:Workflows.ContainsKey($wfName)) {
                    $warnings += "$pluginName — workflow '$wfName' already exists, skipping"
                }
                else {
                    $global:Workflows[$wfName] = $PluginWorkflows[$wfName]
                    $pluginWorkflowNames += $wfName
                }
            }
        }

        # ── 5. Load per-plugin configuration ──
        if ($PluginConfig -and $PluginConfig -is [hashtable]) {
            $configFile = Join-Path $global:PluginConfigPath "$pluginName.json"
            $mergedConfig = @{}
            # Start with plugin-declared defaults
            foreach ($ck in $PluginConfig.Keys) {
                $mergedConfig[$ck] = $PluginConfig[$ck].Default
            }
            # Overlay user overrides from JSON
            if (Test-Path $configFile) {
                try {
                    $userOverrides = Get-Content $configFile -Raw | ConvertFrom-Json
                    foreach ($prop in $userOverrides.PSObject.Properties) {
                        $mergedConfig[$prop.Name] = $prop.Value
                    }
                }
                catch {
                    $warnings += "$pluginName — config file parse error: $($_.Exception.Message)"
                }
            }
            $global:PluginSettings[$pluginName] = $mergedConfig
        }

        # ── 6. Register helper functions ──
        if ($PluginFunctions -and $PluginFunctions -is [hashtable]) {
            $global:PluginHelpers[$pluginName] = @{}
            foreach ($fnName in $PluginFunctions.Keys) {
                if ($PluginFunctions[$fnName] -is [scriptblock]) {
                    $global:PluginHelpers[$pluginName][$fnName] = $PluginFunctions[$fnName]
                    $pluginFunctionNames += $fnName
                }
                else {
                    $warnings += "$pluginName — helper '$fnName' is not a scriptblock, skipping"
                }
            }
        }

        # ── 7. Track loaded plugin ──
        $pluginLoadMs = [math]::Round(((Get-Date) - $pluginStart).TotalMilliseconds)

        $global:LoadedPlugins[$pluginName] = @{
            File        = $file.FullName
            Intents     = $pluginIntentNames
            Workflows   = $pluginWorkflowNames
            Categories  = $pluginCategoryNames
            Functions   = $pluginFunctionNames
            HasConfig   = ($null -ne $PluginConfig -and $PluginConfig -is [hashtable])
            HasHooks    = ($null -ne $PluginHooks -and $PluginHooks -is [hashtable])
            HasTests    = ($null -ne $PluginTests -and $PluginTests -is [hashtable])
            TestNames   = if ($PluginTests -and $PluginTests -is [hashtable]) { @($PluginTests.Keys) } else { @() }
            Tests       = if ($PluginTests -and $PluginTests -is [hashtable]) { $PluginTests } else { $null }
            Hooks       = if ($PluginHooks -and $PluginHooks -is [hashtable]) { $PluginHooks } else { $null }
            Dependencies = if ($PluginInfo.Dependencies) { @($PluginInfo.Dependencies) } else { @() }
            LoadTimeMs  = $pluginLoadMs
            Version     = if ($PluginInfo.Version) { $PluginInfo.Version } else { $null }
            Author      = if ($PluginInfo.Author) { $PluginInfo.Author } else { $null }
            Description = if ($PluginInfo.Description) { $PluginInfo.Description } else { $null }
        }

        # ── 8. Run OnLoad hook ──
        if ($PluginHooks -and $PluginHooks -is [hashtable] -and $PluginHooks.OnLoad -is [scriptblock]) {
            try {
                & $PluginHooks.OnLoad
            }
            catch {
                $warnings += "$pluginName — OnLoad hook error: $($_.Exception.Message)"
            }
        }

        $global:ProfileTimings["Plugin:$pluginName"] = $pluginLoadMs
        $loaded++
    }

    # ── 6. Rebuild IntentCategories to pick up new intents & categories ──
    foreach ($category in $global:CategoryDefinitions.Keys) {
        $global:IntentCategories[$category] = @{
            Name        = $global:CategoryDefinitions[$category].Name
            Description = $global:CategoryDefinitions[$category].Description
            Intents     = @($global:IntentMetadata.Keys | Where-Object {
                $global:IntentMetadata[$_].Category -eq $category
            } | Sort-Object)
        }
    }

    # ── 7. Output summary ──
    if (-not $Quiet) {
        foreach ($w in $warnings) {
            Write-Host "  [WARN] $w" -ForegroundColor Yellow
        }
        if ($loaded -gt 0 -or $skipped -gt 0) {
            Write-Host "Plugins: $loaded loaded ($intentCount intents)" -ForegroundColor DarkGray -NoNewline
            if ($skipped -gt 0) {
                Write-Host ", $skipped skipped" -ForegroundColor Yellow -NoNewline
            }
            Write-Host ""
        }
    }
}

function Unregister-BildsyPSPlugin {
    <#
    .SYNOPSIS
    Unload a plugin by removing its intents, metadata, workflows, and categories
    from the global registries.

    .PARAMETER Name
    The base name of the plugin (e.g. "MyPlugin" for MyPlugin.ps1).
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $global:LoadedPlugins.Contains($Name)) {
        Write-Host "Plugin '$Name' is not loaded." -ForegroundColor Yellow
        return
    }

    $plugin = $global:LoadedPlugins[$Name]

    # Run OnUnload hook before removing anything
    if ($plugin.Hooks -and $plugin.Hooks.OnUnload -is [scriptblock]) {
        try {
            & $plugin.Hooks.OnUnload
        }
        catch {
            Write-Host "  [WARN] $Name — OnUnload hook error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Remove intents
    foreach ($intentName in $plugin.Intents) {
        $global:IntentAliases.Remove($intentName)
        $global:IntentMetadata.Remove($intentName)
    }

    # Remove workflows
    foreach ($wfName in $plugin.Workflows) {
        $global:Workflows.Remove($wfName)
    }

    # Remove categories (only if the plugin added them and no other intents remain)
    foreach ($catKey in $plugin.Categories) {
        $remaining = @($global:IntentMetadata.Keys | Where-Object {
            $global:IntentMetadata[$_].Category -eq $catKey
        })
        if ($remaining.Count -eq 0) {
            $global:CategoryDefinitions.Remove($catKey)
            $global:IntentCategories.Remove($catKey)
        }
    }

    # Remove helper functions
    if ($global:PluginHelpers.ContainsKey($Name)) {
        $global:PluginHelpers.Remove($Name)
    }

    # Remove plugin settings
    if ($global:PluginSettings.ContainsKey($Name)) {
        $global:PluginSettings.Remove($Name)
    }

    $global:LoadedPlugins.Remove($Name)
    $global:ProfileTimings.Remove("Plugin:$Name")

    # Rebuild IntentCategories
    foreach ($category in $global:CategoryDefinitions.Keys) {
        $global:IntentCategories[$category] = @{
            Name        = $global:CategoryDefinitions[$category].Name
            Description = $global:CategoryDefinitions[$category].Description
            Intents     = @($global:IntentMetadata.Keys | Where-Object {
                $global:IntentMetadata[$_].Category -eq $category
            } | Sort-Object)
        }
    }

    Write-Host "Plugin '$Name' unloaded." -ForegroundColor Green
}

function Enable-BildsyPSPlugin {
    <#
    .SYNOPSIS
    Activate a disabled plugin by removing the '_' prefix from its filename,
    then loading it.

    .PARAMETER Name
    The base name without the underscore (e.g. "Example" for _Example.ps1).
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $disabledFile = Join-Path $global:PluginsPath "_$Name.ps1"
    $enabledFile  = Join-Path $global:PluginsPath "$Name.ps1"

    if (Test-Path $enabledFile) {
        Write-Host "Plugin '$Name' is already enabled." -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path $disabledFile)) {
        Write-Host "No disabled plugin '_$Name.ps1' found." -ForegroundColor Red
        return
    }

    Rename-Item $disabledFile $enabledFile
    Import-BildsyPSPlugins -Name $Name
    Write-Host "Plugin '$Name' enabled and loaded." -ForegroundColor Green
}

function Disable-BildsyPSPlugin {
    <#
    .SYNOPSIS
    Deactivate a plugin by adding a '_' prefix to its filename and unloading it.

    .PARAMETER Name
    The base name of the plugin (e.g. "MyPlugin" for MyPlugin.ps1).
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $enabledFile  = Join-Path $global:PluginsPath "$Name.ps1"
    $disabledFile = Join-Path $global:PluginsPath "_$Name.ps1"

    if (Test-Path $disabledFile) {
        Write-Host "Plugin '$Name' is already disabled." -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path $enabledFile)) {
        Write-Host "No active plugin '$Name.ps1' found." -ForegroundColor Red
        return
    }

    # Unload first, then rename
    if ($global:LoadedPlugins.Contains($Name)) {
        Unregister-BildsyPSPlugin -Name $Name
    }
    Rename-Item $enabledFile $disabledFile
    Write-Host "Plugin '$Name' disabled." -ForegroundColor Green
}

function Get-BildsyPSPlugins {
    <#
    .SYNOPSIS
    List all plugins — loaded, disabled, and their contributed intents.
    #>
    Write-Host "`n===== BildsyPS Plugins (v$global:BildsyPSVersion) =====" -ForegroundColor Cyan

    # Show loaded plugins
    if ($global:LoadedPlugins.Count -gt 0) {
        Write-Host "`nActive:" -ForegroundColor Green
        foreach ($name in $global:LoadedPlugins.Keys) {
            $plugin = $global:LoadedPlugins[$name]
            $versionStr = if ($plugin.Version) { " v$($plugin.Version)" } else { "" }
            $authorStr  = if ($plugin.Author) { " by $($plugin.Author)" } else { "" }
            Write-Host "  $name$versionStr$authorStr" -ForegroundColor Yellow -NoNewline
            Write-Host " ($($plugin.LoadTimeMs)ms)" -ForegroundColor DarkGray
            if ($plugin.Description) {
                Write-Host "    $($plugin.Description)" -ForegroundColor Gray
            }
            if ($plugin.Intents.Count -gt 0) {
                Write-Host "    Intents:    $($plugin.Intents -join ', ')" -ForegroundColor DarkGray
            }
            if ($plugin.Workflows.Count -gt 0) {
                Write-Host "    Workflows:  $($plugin.Workflows -join ', ')" -ForegroundColor DarkGray
            }
            if ($plugin.Functions.Count -gt 0) {
                Write-Host "    Helpers:    $($plugin.Functions -join ', ')" -ForegroundColor DarkGray
            }
            if ($plugin.Dependencies.Count -gt 0) {
                Write-Host "    Depends on: $($plugin.Dependencies -join ', ')" -ForegroundColor DarkGray
            }
            # Feature badges
            $badges = @()
            if ($plugin.HasConfig)  { $badges += 'config' }
            if ($plugin.HasHooks)   { $badges += 'hooks' }
            if ($plugin.HasTests)   { $badges += 'tests' }
            if ($badges.Count -gt 0) {
                Write-Host "    Features:   [$($badges -join '] [')]" -ForegroundColor DarkCyan
            }
        }
    }
    else {
        Write-Host "`nNo active plugins." -ForegroundColor DarkGray
    }

    # Show disabled plugins
    $disabledFiles = Get-ChildItem "$global:PluginsPath\*.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '_*' }

    if ($disabledFiles.Count -gt 0) {
        Write-Host "`nDisabled:" -ForegroundColor DarkGray
        foreach ($f in $disabledFiles) {
            $baseName = $f.BaseName -replace '^_', ''
            Write-Host "  $baseName" -ForegroundColor DarkGray -NoNewline
            Write-Host "  (enable with: Enable-BildsyPSPlugin '$baseName')" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
}

function Get-PluginIntentsPrompt {
    <#
    .SYNOPSIS
    Generate an AI system prompt section listing all plugin-contributed intents
    with their parameters, for inclusion in Get-SafeCommandsPrompt.
    #>
    if ($global:LoadedPlugins.Count -eq 0) { return "" }

    $sections = @()
    foreach ($pluginName in $global:LoadedPlugins.Keys) {
        $plugin = $global:LoadedPlugins[$pluginName]
        if ($plugin.Intents.Count -eq 0) { continue }

        $lines = @("PLUGIN — $($pluginName.ToUpper()):")
        foreach ($intentName in $plugin.Intents) {
            $example = @{ intent = $intentName }
            if ($global:IntentMetadata.ContainsKey($intentName)) {
                $meta = $global:IntentMetadata[$intentName]
                foreach ($p in $meta.Parameters) {
                    $example[$p.Name] = $p.Description
                }
            }
            $lines += ($example | ConvertTo-Json -Compress)
        }
        $sections += ($lines -join "`n")
    }

    if ($sections.Count -eq 0) { return "" }
    return ($sections -join "`n`n")
}

function New-BildsyPSPlugin {
    <#
    .SYNOPSIS
    Scaffold a new plugin file from the template.

    .PARAMETER Name
    The plugin name (used as filename and category key).

    .PARAMETER Description
    Short description of what the plugin does.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Description = "Custom plugin"
    )

    $safeName = $Name -replace '[^a-zA-Z0-9_-]', ''
    $filePath = Join-Path $global:PluginsPath "$safeName.ps1"

    if (Test-Path $filePath) {
        Write-Host "Plugin file already exists: $filePath" -ForegroundColor Yellow
        return
    }

    $categoryKey = $safeName.ToLower()

    $template = @"
# ============= $safeName.ps1 — BildsyPS Plugin =============

# Optional: plugin metadata shown by 'plugins' command
`$PluginInfo = @{
    Version     = '1.0.0'
    Author      = '$env:USERNAME'
    Description = '$Description'
}

`$PluginCategories = @{
    '$categoryKey' = @{ Name = '$Name'; Description = '$Description' }
}

`$PluginMetadata = @{
    '${categoryKey}_example' = @{
        Category    = '$categoryKey'
        Description = 'Example intent — replace with your own'
        Parameters  = @(
            @{ Name = 'input'; Required = `$false; Description = 'Input value' }
        )
    }
}

`$PluginIntents = @{
    '${categoryKey}_example' = {
        param(`$input)
        if (-not `$input) { `$input = 'default' }
        @{ Success = `$true; Output = "$safeName plugin: `$input" }
    }
}
"@

    $template | Set-Content -Path $filePath -Encoding UTF8
    Write-Host "Plugin created: $filePath" -ForegroundColor Green
    Write-Host "Edit the file, then run 'reload-plugins' to load it." -ForegroundColor DarkGray
}

# ===== Plugin Configuration =====

function Get-PluginConfig {
    <#
    .SYNOPSIS
    Get configuration values for a loaded plugin.

    .PARAMETER Plugin
    The plugin name.

    .PARAMETER Key
    Optional specific key to retrieve. Without this, returns the full config hashtable.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Plugin,
        [string]$Key
    )

    if (-not $global:PluginSettings.ContainsKey($Plugin)) {
        Write-Host "No configuration found for plugin '$Plugin'." -ForegroundColor Yellow
        Write-Host "Plugin may not define `$PluginConfig or may not be loaded." -ForegroundColor DarkGray
        return $null
    }

    $config = $global:PluginSettings[$Plugin]
    if ($Key) {
        if ($config.ContainsKey($Key)) {
            return $config[$Key]
        }
        else {
            Write-Host "Key '$Key' not found in $Plugin config. Available: $($config.Keys -join ', ')" -ForegroundColor Yellow
            return $null
        }
    }
    return $config
}

function Set-PluginConfig {
    <#
    .SYNOPSIS
    Set a configuration value for a plugin. Persists to Plugins/Config/<name>.json.

    .PARAMETER Plugin
    The plugin name.

    .PARAMETER Key
    The configuration key to set.

    .PARAMETER Value
    The value to set.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Plugin,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)]$Value
    )

    # Ensure Config directory exists
    if (-not (Test-Path $global:PluginConfigPath)) {
        New-Item -ItemType Directory -Path $global:PluginConfigPath -Force | Out-Null
    }

    $configFile = Join-Path $global:PluginConfigPath "$Plugin.json"

    # Load existing overrides
    $overrides = @{}
    if (Test-Path $configFile) {
        try {
            $existing = Get-Content $configFile -Raw | ConvertFrom-Json
            foreach ($prop in $existing.PSObject.Properties) {
                $overrides[$prop.Name] = $prop.Value
            }
        }
        catch { }
    }

    $overrides[$Key] = $Value
    $overrides | ConvertTo-Json -Depth 10 | Set-Content -Path $configFile -Encoding UTF8

    # Update in-memory settings
    if (-not $global:PluginSettings.ContainsKey($Plugin)) {
        $global:PluginSettings[$Plugin] = @{}
    }
    $global:PluginSettings[$Plugin][$Key] = $Value

    Write-Host "Set $Plugin.$Key = $Value" -ForegroundColor Green
}

function Reset-PluginConfig {
    <#
    .SYNOPSIS
    Reset a plugin's configuration to defaults by deleting its override file.

    .PARAMETER Plugin
    The plugin name.
    #>
    param([Parameter(Mandatory = $true)][string]$Plugin)

    $configFile = Join-Path $global:PluginConfigPath "$Plugin.json"
    if (Test-Path $configFile) {
        Remove-Item $configFile -Force
        Write-Host "Config for '$Plugin' reset to defaults." -ForegroundColor Green
    }
    else {
        Write-Host "No config overrides found for '$Plugin'." -ForegroundColor DarkGray
    }

    # Reload defaults from plugin if it's loaded
    if ($global:LoadedPlugins.Contains($Plugin)) {
        # Re-import just this plugin to pick up defaults
        $global:PluginSettings.Remove($Plugin)
        Import-BildsyPSPlugins -Name $Plugin -Quiet
        Write-Host "Defaults reloaded from plugin." -ForegroundColor DarkGray
    }
}

# ===== Plugin Self-Test Framework =====

function Test-BildsyPSPlugin {
    <#
    .SYNOPSIS
    Run self-tests defined in a plugin's $PluginTests hashtable.

    .PARAMETER Name
    Plugin name to test. Use -All to test every loaded plugin.

    .PARAMETER All
    Test all loaded plugins that define $PluginTests.
    #>
    param(
        [string]$Name,
        [switch]$All
    )

    if (-not $All -and -not $Name) {
        Write-Host "Specify -Name <plugin> or -All" -ForegroundColor Yellow
        return
    }

    $targets = @()
    if ($All) {
        $targets = @($global:LoadedPlugins.Keys | Where-Object { $global:LoadedPlugins[$_].HasTests })
        if ($targets.Count -eq 0) {
            Write-Host "No loaded plugins define self-tests." -ForegroundColor DarkGray
            return
        }
    }
    else {
        if (-not $global:LoadedPlugins.Contains($Name)) {
            Write-Host "Plugin '$Name' is not loaded." -ForegroundColor Red
            return
        }
        if (-not $global:LoadedPlugins[$Name].HasTests) {
            Write-Host "Plugin '$Name' does not define self-tests." -ForegroundColor Yellow
            return
        }
        $targets = @($Name)
    }

    $totalPass = 0
    $totalFail = 0

    foreach ($pluginName in $targets) {
        $plugin = $global:LoadedPlugins[$pluginName]
        $tests = $plugin.Tests
        Write-Host "`n===== Testing: $pluginName =====" -ForegroundColor Cyan

        foreach ($testName in $tests.Keys) {
            $testBlock = $tests[$testName]
            if ($testBlock -isnot [scriptblock]) {
                Write-Host "  [SKIP] $testName — not a scriptblock" -ForegroundColor Yellow
                continue
            }
            try {
                $result = & $testBlock
                if ($result.Success) {
                    Write-Host "  [PASS] $testName" -ForegroundColor Green
                    if ($result.Output) {
                        Write-Host "         $($result.Output)" -ForegroundColor DarkGray
                    }
                    $totalPass++
                }
                else {
                    Write-Host "  [FAIL] $testName" -ForegroundColor Red
                    if ($result.Output) {
                        Write-Host "         $($result.Output)" -ForegroundColor Yellow
                    }
                    $totalFail++
                }
            }
            catch {
                Write-Host "  [FAIL] $testName — $($_.Exception.Message)" -ForegroundColor Red
                $totalFail++
            }
        }
    }

    Write-Host "`n─────────────────────────────" -ForegroundColor DarkGray
    $color = if ($totalFail -eq 0) { 'Green' } else { 'Red' }
    Write-Host "Results: $totalPass passed, $totalFail failed" -ForegroundColor $color
    Write-Host ""

    return @{ Passed = $totalPass; Failed = $totalFail; Success = ($totalFail -eq 0) }
}

# ===== Hot-Reload File Watcher =====

function Watch-BildsyPSPlugins {
    <#
    .SYNOPSIS
    Start a FileSystemWatcher on the Plugins/ directory. When a .ps1 file is
    modified, it is automatically unregistered and re-imported.

    .DESCRIPTION
    The watcher runs as a registered event in the current session. It only
    triggers on .ps1 files that are active (no underscore prefix). Use
    Stop-WatchBildsyPSPlugins to tear it down.
    #>

    if ($global:_PluginWatcher) {
        Write-Host "Plugin watcher is already running. Use Stop-WatchBildsyPSPlugins to stop it." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $global:PluginsPath)) {
        Write-Host "Plugins directory not found." -ForegroundColor Red
        return
    }

    $watcher = [System.IO.FileSystemWatcher]::new($global:PluginsPath, '*.ps1')
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
    $watcher.EnableRaisingEvents = $true

    $action = {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($Event.SourceEventArgs.Name)
        $changeType = $Event.SourceEventArgs.ChangeType

        # Ignore disabled plugins (underscore prefix)
        if ($name -like '_*') { return }

        # Debounce: skip if last event was <500ms ago for same file
        $now = [datetime]::UtcNow
        if ($global:_PluginWatcherLastEvent -and
            $global:_PluginWatcherLastFile -eq $name -and
            ($now - $global:_PluginWatcherLastEvent).TotalMilliseconds -lt 500) {
            return
        }
        $global:_PluginWatcherLastEvent = $now
        $global:_PluginWatcherLastFile = $name

        Write-Host "`n[plugin-watch] Detected $changeType on $name.ps1" -ForegroundColor DarkCyan

        if ($changeType -eq 'Deleted') {
            if ($global:LoadedPlugins.Contains($name)) {
                Unregister-BildsyPSPlugin -Name $name
                Write-Host "[plugin-watch] Unloaded $name" -ForegroundColor Yellow
            }
        }
        else {
            # Changed or Created — reload
            if ($global:LoadedPlugins.Contains($name)) {
                Unregister-BildsyPSPlugin -Name $name
            }
            Import-BildsyPSPlugins -Name $name
            Write-Host "[plugin-watch] Reloaded $name" -ForegroundColor Green
        }
    }

    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action -SourceIdentifier 'BildsyPSPluginChanged' | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action -SourceIdentifier 'BildsyPSPluginCreated' | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $action -SourceIdentifier 'BildsyPSPluginDeleted' | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action -SourceIdentifier 'BildsyPSPluginRenamed' | Out-Null

    $global:_PluginWatcher = $watcher
    $global:_PluginWatcherLastEvent = $null
    $global:_PluginWatcherLastFile = $null

    Write-Host "Plugin watcher started on $global:PluginsPath" -ForegroundColor Green
    Write-Host "Edit any .ps1 in Plugins/ and it will auto-reload." -ForegroundColor DarkGray
    Write-Host "Stop with: Stop-WatchBildsyPSPlugins" -ForegroundColor DarkGray
}

function Stop-WatchBildsyPSPlugins {
    <#
    .SYNOPSIS
    Stop the plugin file watcher started by Watch-BildsyPSPlugins.
    #>
    if (-not $global:_PluginWatcher) {
        Write-Host "No plugin watcher is running." -ForegroundColor DarkGray
        return
    }

    # Unregister all events
    @('BildsyPSPluginChanged', 'BildsyPSPluginCreated', 'BildsyPSPluginDeleted', 'BildsyPSPluginRenamed') | ForEach-Object {
        Unregister-Event -SourceIdentifier $_ -ErrorAction SilentlyContinue
    }

    $global:_PluginWatcher.EnableRaisingEvents = $false
    $global:_PluginWatcher.Dispose()
    $global:_PluginWatcher = $null
    $global:_PluginWatcherLastEvent = $null
    $global:_PluginWatcherLastFile = $null

    Write-Host "Plugin watcher stopped." -ForegroundColor Green
}

# ===== Tab Completion =====
Register-ArgumentCompleter -CommandName Unregister-BildsyPSPlugin -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:LoadedPlugins.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Enable-BildsyPSPlugin -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-ChildItem "$global:PluginsPath\_*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.BaseName -replace '^_', ''
        if ($n -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($n, $n, 'ParameterValue', "Enable plugin $n")
        }
    }
}

Register-ArgumentCompleter -CommandName Disable-BildsyPSPlugin -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:LoadedPlugins.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Disable plugin $_")
    }
}

Register-ArgumentCompleter -CommandName Import-BildsyPSPlugins -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-ChildItem "$global:PluginsPath\*.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '_*' } | ForEach-Object {
        if ($_.BaseName -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($_.BaseName, $_.BaseName, 'ParameterValue', $_.BaseName)
        }
    }
}

Register-ArgumentCompleter -CommandName Test-BildsyPSPlugin -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:LoadedPlugins.Keys | Where-Object {
        $_ -like "$wordToComplete*" -and $global:LoadedPlugins[$_].HasTests
    } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Test plugin $_")
    }
}

Register-ArgumentCompleter -CommandName Get-PluginConfig -ParameterName Plugin -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:PluginSettings.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "$_ config")
    }
}

Register-ArgumentCompleter -CommandName Set-PluginConfig -ParameterName Plugin -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:PluginSettings.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "$_ config")
    }
}

Register-ArgumentCompleter -CommandName Reset-PluginConfig -ParameterName Plugin -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:PluginSettings.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Reset $_ config")
    }
}

# ===== Aliases =====
Set-Alias plugins       Get-BildsyPSPlugins       -Force
Set-Alias new-plugin    New-BildsyPSPlugin        -Force
Set-Alias test-plugin   Test-BildsyPSPlugin       -Force
Set-Alias watch-plugins Watch-BildsyPSPlugins     -Force
Set-Alias plugin-config Get-PluginConfig        -Force

# Auto-load plugins on module import
Import-BildsyPSPlugins -Quiet
