# ============= _Example.ps1 — Sample Shelix Plugin =============
# Drop .ps1 files into the Plugins/ folder to register new intents
# without modifying core code.
#
# Convention (in order of evaluation):
#   1. $PluginInfo       — version, author, description           (optional)
#   2. $PluginCategories — new category definitions                (optional)
#   3. $PluginMetadata   — intent metadata per intent              (recommended)
#   4. $PluginIntents    — hashtable of intent scriptblocks        (REQUIRED)
#   5. $PluginWorkflows  — multi-step workflow definitions         (optional)
#
# The plugin loader merges these into the global registries automatically.
# Rename this file (remove the leading underscore) to activate it.
# Or run:  Enable-ShelixPlugin 'Example'
#
# ── Quick reference ──
#   plugins                      — list active & disabled plugins
#   new-plugin 'Name'            — scaffold a new plugin from template
#   Enable-ShelixPlugin 'Name'   — activate a _Name.ps1 file
#   Disable-ShelixPlugin 'Name'  — deactivate and unload
#   reload-plugins               — reload all active plugins
#   Get-IntentInfo 'intent_name' — inspect any intent (shows source: plugin)
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
    Version     = '1.0.0'
    Author      = 'Shelix'
    Description = 'Demo plugin — showcases every plugin convention'
}

# ── New categories (optional — you can also reuse existing ones) ──
$PluginCategories = @{
    'example' = @{
        Name        = 'Example Plugins'
        Description = 'Demo intents from the plugin system'
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
        @{ Success = $true; Output = "Hello, $name! Plugin system is working." }
    }
    'coin_flip' = {
        $side = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { 'Heads' } else { 'Tails' }
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
