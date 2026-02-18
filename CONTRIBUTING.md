# Contributing to Shelix

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
4. Test on PowerShell 5.1 (for Windows compatibility)
5. Commit with clear messages (`git commit -m "Add: new intent for X"`)
6. Push to your fork (`git push origin feature/my-feature`)
7. Open a Pull Request

## Code Style

### PowerShell Guidelines
- Use approved PowerShell verbs (`Get-`, `Set-`, `New-`, `Invoke-`, etc.)
- Use PascalCase for function names and parameters
- Use `$camelCase` for local variables
- Add comment-based help for public functions
- Maintain PowerShell 5.1 compatibility

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
When adding new intents to `IntentAliasSystem.ps1`:
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
├── Modules/                          # All functionality lives here
│   ├── ConfigLoader.ps1              # .env and config loading
│   ├── PlatformUtils.ps1             # Cross-platform helpers
│   ├── SecurityUtils.ps1             # Path/URL security
│   ├── CommandValidation.ps1         # Command whitelist & safety levels
│   ├── SystemUtilities.ps1           # sudo, ports, uptime, PATH
│   ├── ArchiveUtils.ps1              # zip, unzip
│   ├── DockerTools.ps1               # Docker shortcuts
│   ├── DevTools.ps1                  # IDE launchers, dev checks
│   ├── NaturalLanguage.ps1           # NL to command translation
│   ├── AIExecution.ps1               # AI command gateway, rate limiting
│   ├── ResponseParser.ps1            # Parse AI responses
│   ├── DocumentTools.ps1             # OpenXML document creation
│   ├── SafetySystem.ps1              # AI execution safety
│   ├── TerminalTools.ps1             # bat, glow, broot, fzf
│   ├── NavigationUtils.ps1           # Navigation & git shortcuts
│   ├── PackageManager.ps1            # Tool installation
│   ├── WebTools.ps1                  # Web search APIs
│   ├── ProductivityTools.ps1         # Clipboard, Git, Calendar
│   ├── MCPClient.ps1                 # MCP protocol client
│   ├── FzfIntegration.ps1            # Fuzzy finder
│   ├── PersistentAliases.ps1         # User-defined aliases
│   ├── ProfileHelp.ps1               # Help, tips, system prompt
│   ├── ChatSession.ps1               # LLM chat loop
│   ├── ChatProviders.ps1             # AI provider implementations
│   ├── IntentAliasSystem.ps1         # Intent routing and definitions
│   └── PluginLoader.ps1             # Drop-in plugin system
├── Plugins/
│   └── _Example.ps1                 # Sample plugin (underscore = inactive)
```

## Testing

Before submitting a PR:
1. Reload your profile: `. $PROFILE`
2. Test the chat function: `chat` or `chat-anthropic`
3. Test any new intents you've added
4. Verify existing functionality still works

## Adding New Features

### New AI Provider
1. Add provider config to `$global:ChatProviders` in `ChatProviders.ps1`
2. Implement API handler if format differs from OpenAI/Anthropic
3. Add to README documentation
4. Test with `Test-ChatProvider <name>`

### New Intent (via Plugin — recommended)
1. Run `new-plugin 'MyPlugin'` to scaffold, or create a `.ps1` file in `Plugins/`
2. Define `$PluginIntents` — a hashtable mapping intent names to scriptblocks (required)
3. Define `$PluginMetadata` — category, description, parameters (recommended)
4. Optionally define `$PluginInfo` (version/author), `$PluginCategories`, and `$PluginWorkflows`
5. Run `reload-plugins` to load — plugin intents appear in `intent-help`, AI chat, and tab-completion
6. Use `Enable-ShelixPlugin` / `Disable-ShelixPlugin` to toggle without deleting files
7. See `Plugins/_Example.ps1` for the full template with all conventions

### New Intent (core)
1. Add to `$global:IntentAliases` in `IntentAliasSystem.ps1`
2. Add metadata to `$global:IntentMetadata` if needed
3. Update system prompt in `Get-SafeCommandsPrompt` if AI should know about it
4. Document in README

### New Module
1. Create `Modules/YourModule.ps1`
2. Add dot-source to profile: `. "$global:ModulesPath\YourModule.ps1"`
3. Export any global variables or aliases

## Questions?

Open an issue or start a discussion on GitHub.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
