# ============= _Example.ps1 — Sample BildsyPS Plugin =============
# Drop .ps1 files into the Plugins/ folder to register new intents
# without modifying core code.
#
# Convention (in order of evaluation):
#   1. $PluginInfo       — version, author, description, deps, version compat  (optional)
#   2. $PluginCategories — new category definitions                            (optional)
#   3. $PluginConfig     — per-plugin settings with defaults                   (optional)
#   4. $PluginMetadata   — intent metadata per intent                          (recommended)
#   5. $PluginIntents    — hashtable of intent scriptblocks                    (REQUIRED)
#   6. $PluginWorkflows  — multi-step workflow definitions                     (optional)
#   7. $PluginFunctions  — helper functions shared with other plugins          (optional)
#   8. $PluginHooks      — lifecycle callbacks (OnLoad, OnUnload)              (optional)
#   9. $PluginTests      — self-test scriptblocks                              (optional)
#
# The plugin loader merges these into the global registries automatically.
# Rename this file (remove the leading underscore) to activate it.
# Or run:  Enable-BildsyPSPlugin 'Example'
#
# ── Quick reference ──
#   plugins                      — list active & disabled plugins
#   new-plugin 'Name'            — scaffold a new plugin from template
#   Enable-BildsyPSPlugin 'Name'   — activate a _Name.ps1 file
#   Disable-BildsyPSPlugin 'Name'  — deactivate and unload
#   reload-plugins               — reload all active plugins
#   Get-IntentInfo 'intent_name' — inspect any intent (shows source: plugin)
#   test-plugin -Name 'Example'  — run plugin self-tests
#   plugin-config 'Example'      — view plugin configuration
#   watch-plugins                — auto-reload on file change
#
# ── Intent scriptblock contract ──
#   Each scriptblock receives named parameters and must return:
#   @{ Success = $true/$false; Output = "user-facing message" }
#
# ── Safety tiers ──
#   Omit the Safety key for normal intents. Set Safety = 'RequiresConfirmation'
#   on anything destructive — the router will prompt the user before executing.
# ================================================================

# ── Plugin metadata (shown by 'plugins' command) ──
$PluginInfo = @{
    Version          = '2.0.0'
    Author           = 'BildsyPS'
    Description      = 'Demo plugin — showcases every plugin convention'
    # Dependencies   = @('OtherPlugin')        # declare plugin dependencies
    # MinBildsyPSVersion = '0.9.0'               # minimum BildsyPS version required
    # MaxBildsyPSVersion = '99.0.0'              # maximum BildsyPS version supported
}

# ── New categories (optional — you can also reuse existing ones) ──
$PluginCategories = @{
    'example' = @{
        Name        = 'Example Plugins'
        Description = 'Demo intents from the plugin system'
    }
}

# ── Per-plugin configuration (optional — persisted to Plugins/Config/Example.json) ──
# Each key is a setting name. Default is used unless the user overrides it with Set-PluginConfig.
# Access at runtime via: $global:PluginSettings['Example']['greeting_prefix']
$PluginConfig = @{
    'greeting_prefix' = @{
        Default     = 'Hello'
        Description = 'Prefix used in the hello_world intent'
    }
    'coin_sides' = @{
        Default     = 2
        Description = 'Number of sides on the coin (2 = normal, 3 = includes Edge)'
    }
}

# ── Intent metadata (recommended — drives help, validation, and AI prompt) ──
$PluginMetadata = @{
    'hello_world' = @{
        Category    = 'example'
        Description = 'Say hello — proof the plugin system works'
        Parameters  = @(
            @{ Name = 'name'; Required = $false; Description = 'Who to greet (default: World)' }
        )
    }
    'coin_flip' = @{
        Category    = 'example'
        Description = 'Flip a coin — heads or tails'
        Parameters  = @()
    }
    'word_count' = @{
        Category    = 'example'
        Description = 'Count words in a string'
        Parameters  = @(
            @{ Name = 'text'; Required = $true; Description = 'Text to count words in' }
        )
    }
}

# ── Intent implementations (REQUIRED — at least one entry) ──
$PluginIntents = @{
    'hello_world' = {
        param($name)
        if (-not $name) { $name = 'World' }
        $prefix = if ($global:PluginSettings['Example']) { $global:PluginSettings['Example']['greeting_prefix'] } else { 'Hello' }
        @{ Success = $true; Output = "$prefix, $name! Plugin system is working." }
    }
    'coin_flip' = {
        $sides = if ($global:PluginSettings['Example']) { $global:PluginSettings['Example']['coin_sides'] } else { 2 }
        $roll = Get-Random -Minimum 0 -Maximum $sides
        $side = switch ($roll) { 0 { 'Heads' } 1 { 'Tails' } default { 'Edge!' } }
        @{ Success = $true; Output = $side }
    }
    'word_count' = {
        param($text)
        if (-not $text) {
            return @{ Success = $false; Output = "Error: 'text' parameter is required."; Error = $true }
        }
        $count = ($text -split '\s+' | Where-Object { $_ }).Count
        @{ Success = $true; Output = "$count word(s)" }
    }
}

# ── Workflows (optional — chains of existing intents) ──
$PluginWorkflows = @{
    'greet_and_flip' = @{
        Name        = 'Greet and Flip'
        Description = 'Say hello, then flip a coin (plugin workflow demo)'
        Steps       = @(
            @{ Intent = 'hello_world'; ParamMap = @{ name = 'name' } }
            @{ Intent = 'coin_flip' }
        )
    }
}

# ── Helper functions (optional — shared via $global:PluginHelpers['Example']['Reverse-String']) ──
$PluginFunctions = @{
    'Reverse-String' = {
        param([string]$Text)
        $chars = $Text.ToCharArray()
        [array]::Reverse($chars)
        return -join $chars
    }
}

# ── Lifecycle hooks (optional — called by the loader on load/unload) ──
$PluginHooks = @{
    OnLoad = {
        # Runs after all merges are complete. Good for initializing state.
        $global:_ExamplePluginLoadedAt = Get-Date
    }
    OnUnload = {
        # Runs before registry removal. Good for cleanup.
        Remove-Variable -Name '_ExamplePluginLoadedAt' -Scope Global -ErrorAction SilentlyContinue
    }
}

# ── Self-tests (optional — run with: Test-BildsyPSPlugin -Name 'Example') ──
$PluginTests = @{
    'hello_world returns success' = {
        $r = & $global:IntentAliases['hello_world'] 'Test'
        @{ Success = $r.Success; Output = $r.Output }
    }
    'coin_flip returns valid side' = {
        $r = & $global:IntentAliases['coin_flip']
        $valid = $r.Output -in @('Heads', 'Tails', 'Edge!')
        @{ Success = $valid; Output = "Got: $($r.Output)" }
    }
    'word_count requires text' = {
        $r = & $global:IntentAliases['word_count']
        @{ Success = ($r.Success -eq $false); Output = 'Correctly rejects empty input' }
    }
    'word_count counts correctly' = {
        $r = & $global:IntentAliases['word_count'] 'one two three'
        @{ Success = ($r.Output -eq '3 word(s)'); Output = $r.Output }
    }
    'helper function works' = {
        $reversed = & $global:PluginHelpers['Example']['Reverse-String'] 'abc'
        @{ Success = ($reversed -eq 'cba'); Output = "Reversed: $reversed" }
    }
}
