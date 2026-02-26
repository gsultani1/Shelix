# Contributing to BildsyPS

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Issues
- Use GitHub Issues to report bugs or request features
- Include your PowerShell version (`$PSVersionTable.PSVersion`)
- Include error messages and steps to reproduce
- Specify which AI provider you're using (Ollama, Anthropic, OpenAI, etc.)

### Submitting Changes
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test on PowerShell 7.0+ (`Invoke-Pester ./Tests -Output Detailed`)
5. Commit with clear messages (`git commit -m "Add: new intent for X"`)
6. Push to your fork (`git push origin feature/my-feature`)
7. Open a Pull Request

## Code Style

### PowerShell Guidelines
- Use approved PowerShell verbs (`Get-`, `Set-`, `New-`, `Invoke-`, etc.)
- Use PascalCase for function names and parameters
- Use `$camelCase` for local variables
- Target PowerShell 7.0+ (the minimum supported version)

### Example Function
```powershell
function Get-ExampleData {
    <#
    .SYNOPSIS
    Brief description of what the function does
    
    .PARAMETER Name
    Description of the parameter
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    # Implementation
}
```

### Intent Guidelines
When adding new intents to `IntentRegistry.ps1` / `IntentActions.ps1`:
- Return a hashtable with `Success`, `Output`, and optionally `Error`
- Validate required parameters early
- Handle errors gracefully
- Keep intents focused on a single task

```powershell
"my_intent" = {
    param($requiredParam)
    if (-not $requiredParam) {
        return @{ Success = $false; Output = "Error: requiredParam is required"; Error = $true }
    }
    # Do work...
    @{ Success = $true; Output = "Result here" }
}
```

## Project Structure

```
├── Microsoft.PowerShell_profile.ps1  # Main entry point (~150 lines)
├── ChatConfig.json                   # User configuration (not tracked)
├── BildsyPS.psm1 / BildsyPS.psd1    # Module loader + manifest
├── Modules/                          # 43 focused modules
│   ├── ConfigLoader.ps1              # .env and config loading
│   ├── PlatformUtils.ps1             # Cross-platform helpers
│   ├── SecurityUtils.ps1             # Path/URL security
│   ├── SecretScanner.ps1             # API key / credential leak detection
│   ├── CommandValidation.ps1         # Command whitelist & safety levels
│   ├── SystemUtilities.ps1           # sudo, ports, uptime, PATH
│   ├── ArchiveUtils.ps1              # zip, unzip
│   ├── DockerTools.ps1               # Docker shortcuts
│   ├── DevTools.ps1                  # IDE launchers, dev checks
│   ├── NaturalLanguage.ps1           # NL to command translation
│   ├── ResponseParser.ps1            # Parse AI responses, format markdown
│   ├── DocumentTools.ps1             # OpenXML document creation
│   ├── SafetySystem.ps1              # AI execution safety + secret scanning
│   ├── TerminalTools.ps1             # bat, glow, broot, fzf
│   ├── NavigationUtils.ps1           # Navigation & git shortcuts
│   ├── PackageManager.ps1            # Tool installation
│   ├── WebTools.ps1                  # Web search APIs
│   ├── ProductivityTools.ps1         # Clipboard, Git, Calendar
│   ├── MCPClient.ps1                 # MCP protocol client
│   ├── BrowserAwareness.ps1          # Browser tab URL + content reading
│   ├── VisionTools.ps1               # Screenshot capture + vision model analysis
│   ├── OCRTools.ps1                  # Tesseract OCR + pdftotext integration
│   ├── CodeArtifacts.ps1             # AI code save + execute + tracking
│   ├── AppBuilder.ps1                # Prompt-to-executable pipeline
│   ├── FolderContext.ps1             # Folder awareness for AI context
│   ├── FzfIntegration.ps1            # Fuzzy finder integration
│   ├── PersistentAliases.ps1         # User-defined aliases
│   ├── ToastNotifications.ps1        # BurntToast/.NET notifications
│   ├── ProfileHelp.ps1               # Help, tips, system prompt
│   ├── ChatStorage.ps1               # SQLite persistence + FTS5 full-text search
│   ├── ChatSession.ps1               # LLM chat loop + session management
│   ├── ChatProviders.ps1             # AI provider implementations
│   ├── AgentHeartbeat.ps1            # Cron-triggered background agent tasks
│   ├── UserSkills.ps1                # JSON user-defined intent loader
│   ├── PluginLoader.ps1              # Plugin system (deps, config, hooks, tests)
│   ├── IntentAliasSystem.ps1         # Intent system orchestrator
│   ├── IntentRegistry.ps1            # Intent metadata + category definitions
│   ├── IntentActions.ps1             # Core intent scriptblocks
│   ├── IntentActionsSystem.ps1       # System/filesystem/workflow scriptblocks
│   ├── WorkflowEngine.ps1            # Multi-step workflow engine
│   ├── IntentRouter.ps1              # Intent router, help, tab completion
│   ├── AgentTools.ps1                # Agent tool registry (17 built-in tools)
│   └── AgentLoop.ps1                 # Autonomous agent engine (ReAct + tools + memory)
├── Plugins/
│   ├── _Example.ps1                  # Reference plugin template
│   ├── _Pomodoro.ps1                 # Pomodoro timer plugin
│   └── _QuickNotes.ps1              # Note-taking plugin
├── Tests/                            # 17 Pester test files, 368 tests
│   ├── AgentHeartbeat.Tests.ps1
│   ├── AgentLoop.Tests.ps1
│   ├── AppBuilder.Tests.ps1
│   ├── ChatStorage.Tests.ps1
│   ├── CodeArtifacts.Tests.ps1
│   ├── ConfigLoader.Tests.ps1
│   ├── IntentRouting.Tests.ps1
│   ├── NaturalLanguage.Tests.ps1
│   ├── PluginLoader.Tests.ps1
│   ├── ResponseParser.Tests.ps1
│   ├── SafetySystem.Tests.ps1
│   ├── SecretScanner.Tests.ps1
│   ├── SpawnAgent.Tests.ps1
│   ├── TabCompletion.Tests.ps1
│   ├── UserSkills.Tests.ps1
│   ├── VisionTools.Tests.ps1
│   └── WorkflowEngine.Tests.ps1
```

## Testing

The project has a comprehensive Pester v5 test suite (368 tests, 0 failures). Before submitting a PR:

```powershell
# Run the full test suite
Invoke-Pester ./Tests -Output Detailed

# Run a specific test file
Invoke-Pester ./Tests/SecretScanner.Tests.ps1 -Output Detailed

# Quick smoke test — reload profile
. $PROFILE

# Test chat function
chat
```

When adding new functionality, add corresponding tests in `Tests/`. Follow the existing pattern of using `Describe`/`Context`/`It` blocks with mocked dependencies.

## Adding New Features

### New AI Provider
1. Add provider config to `$global:ChatProviders` in `ChatProviders.ps1`
2. Implement API handler if format differs from OpenAI/Anthropic
3. Add to README documentation
4. Test with `Test-ChatProvider <name>`

### New Intent (via JSON User Skill — easiest)
1. Copy `UserSkills.example.json` to `UserSkills.json`
2. Add a skill entry with `description`, `steps` (required), and optionally `parameters`, `triggers`, `confirm`, `category`
3. Steps can be `{"command": "..."}` for raw PowerShell or `{"intent": "..."}` for existing intents
4. Use `{paramName}` placeholders in commands/intent params for parameter substitution
5. Run `reload-skills` to load — skill intents appear in `intent-help`, AI chat, and tab-completion
6. Use `skills` to list, `new-skill` to create interactively, `Remove-UserSkill` to delete

### New Intent (via Plugin — recommended)
1. Run `new-plugin 'MyPlugin'` to scaffold, or create a `.ps1` file in `Plugins/`
2. Define `$PluginIntents` — a hashtable mapping intent names to scriptblocks (required)
3. Define `$PluginMetadata` — category, description, parameters (recommended)
4. Optionally define any of the following:
   - `$PluginInfo` — version, author, description, `Dependencies`, `MinBildsyPSVersion`, `MaxBildsyPSVersion`
   - `$PluginCategories` — new intent category definitions
   - `$PluginWorkflows` — multi-step workflow chains
   - `$PluginConfig` — per-plugin settings with defaults, persisted to `Plugins/Config/<name>.json`
   - `$PluginFunctions` — helper scriptblocks shared via `$global:PluginHelpers['Name']['FnName']`
   - `$PluginHooks` — `OnLoad`/`OnUnload` lifecycle callbacks
   - `$PluginTests` — self-test scriptblocks, run with `test-plugin -Name 'Name'`
5. Run `reload-plugins` to load — plugin intents appear in `intent-help`, AI chat, and tab-completion
6. Use `Enable-BildsyPSPlugin` / `Disable-BildsyPSPlugin` to toggle without deleting files
7. Use `watch-plugins` during development for automatic hot-reload on file save
8. See `Plugins/_Example.ps1` for the full template with all conventions

### New Intent (core)
1. Add metadata to `$global:IntentMetadata` in `IntentRegistry.ps1`
2. Add scriptblock to `$global:IntentAliases` in `IntentActions.ps1` (core) or `IntentActionsSystem.ps1` (system/filesystem)
3. Add category mapping in `$global:IntentCategories` in `IntentRegistry.ps1` if needed
4. The intent will auto-register in the LLM system prompt via `Get-SafeCommandsPrompt`
5. Document in README

### New Module
1. Create `Modules/YourModule.ps1`
2. Add dot-source to profile: `. "$global:ModulesPath\YourModule.ps1"`
3. Export any global variables or aliases

## Questions?

Open an issue or start a discussion on GitHub.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
