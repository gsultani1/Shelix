# ============= PluginLoader.ps1 — Drop-in Plugin System =============
# Scans Plugins/ for .ps1 files that export $PluginIntents (and optionally
# $PluginMetadata, $PluginWorkflows, $PluginCategories) and merges them
# into the global intent registries.
#
# Must be loaded AFTER IntentAliasSystem.ps1 so the registries exist.

$global:PluginsPath = "$PSScriptRoot\..\Plugins"
$global:LoadedPlugins = [ordered]@{}

function Import-ShelixPlugins {
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

    if (-not (Test-Path $global:PluginsPath)) {
        if (-not $Quiet) {
            Write-Host "Plugins directory not found — skipping plugin load." -ForegroundColor DarkGray
        }
        return
    }

    $pluginFiles = Get-ChildItem "$global:PluginsPath\*.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '_*' } |
        Sort-Object Name

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

    $loaded      = 0
    $skipped     = 0
    $intentCount = 0
    $warnings    = @()

    foreach ($file in $pluginFiles) {
        $pluginStart = Get-Date

        # Clear variables from previous iteration
        $PluginIntents    = $null
        $PluginMetadata   = $null
        $PluginWorkflows  = $null
        $PluginCategories = $null
        $PluginInfo       = $null

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

        # ── Validate scriptblock types ──
        $badIntents = @($PluginIntents.Keys | Where-Object { $PluginIntents[$_] -isnot [scriptblock] })
        if ($badIntents.Count -gt 0) {
            Write-Host "  [SKIP] $pluginName — non-scriptblock values for: $($badIntents -join ', ')" -ForegroundColor Red
            $skipped++
            continue
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
            if ($global:IntentAliases.ContainsKey($intentName)) {
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

        # ── 5. Track loaded plugin ──
        $pluginLoadMs = [math]::Round(((Get-Date) - $pluginStart).TotalMilliseconds)

        $global:LoadedPlugins[$pluginName] = @{
            File       = $file.FullName
            Intents    = $pluginIntentNames
            Workflows  = $pluginWorkflowNames
            Categories = $pluginCategoryNames
            LoadTimeMs = $pluginLoadMs
            Version    = if ($PluginInfo.Version) { $PluginInfo.Version } else { $null }
            Author     = if ($PluginInfo.Author) { $PluginInfo.Author } else { $null }
            Description = if ($PluginInfo.Description) { $PluginInfo.Description } else { $null }
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

function Unregister-ShelixPlugin {
    <#
    .SYNOPSIS
    Unload a plugin by removing its intents, metadata, workflows, and categories
    from the global registries.

    .PARAMETER Name
    The base name of the plugin (e.g. "MyPlugin" for MyPlugin.ps1).
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $global:LoadedPlugins.ContainsKey($Name)) {
        Write-Host "Plugin '$Name' is not loaded." -ForegroundColor Yellow
        return
    }

    $plugin = $global:LoadedPlugins[$Name]

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

function Enable-ShelixPlugin {
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
    Import-ShelixPlugins -Name $Name
    Write-Host "Plugin '$Name' enabled and loaded." -ForegroundColor Green
}

function Disable-ShelixPlugin {
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
    if ($global:LoadedPlugins.ContainsKey($Name)) {
        Unregister-ShelixPlugin -Name $Name
    }
    Rename-Item $enabledFile $disabledFile
    Write-Host "Plugin '$Name' disabled." -ForegroundColor Green
}

function Get-ShelixPlugins {
    <#
    .SYNOPSIS
    List all plugins — loaded, disabled, and their contributed intents.
    #>
    Write-Host "`n===== Shelix Plugins =====" -ForegroundColor Cyan

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
                Write-Host "    Intents:   $($plugin.Intents -join ', ')" -ForegroundColor DarkGray
            }
            if ($plugin.Workflows.Count -gt 0) {
                Write-Host "    Workflows: $($plugin.Workflows -join ', ')" -ForegroundColor DarkGray
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
            Write-Host "  (enable with: Enable-ShelixPlugin '$baseName')" -ForegroundColor DarkGray
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

function New-ShelixPlugin {
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
# ============= $safeName.ps1 — Shelix Plugin =============

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

# ===== Tab Completion =====
Register-ArgumentCompleter -CommandName Unregister-ShelixPlugin -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:LoadedPlugins.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Enable-ShelixPlugin -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-ChildItem "$global:PluginsPath\_*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.BaseName -replace '^_', ''
        if ($n -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($n, $n, 'ParameterValue', "Enable plugin $n")
        }
    }
}

Register-ArgumentCompleter -CommandName Disable-ShelixPlugin -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:LoadedPlugins.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Disable plugin $_")
    }
}

Register-ArgumentCompleter -CommandName Import-ShelixPlugins -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-ChildItem "$global:PluginsPath\*.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '_*' } | ForEach-Object {
        if ($_.BaseName -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($_.BaseName, $_.BaseName, 'ParameterValue', $_.BaseName)
        }
    }
}

# ===== Aliases =====
Set-Alias plugins   Get-ShelixPlugins       -Force
Set-Alias new-plugin New-ShelixPlugin        -Force

# Auto-load plugins on module import
Import-ShelixPlugins -Quiet
