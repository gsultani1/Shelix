# PowerShell AI Profile Setup Guide

## Quick Start

### 1. Install Ollama (Local LLM - Recommended)

```powershell
# Install via winget
winget install Ollama.Ollama

# Or download from: https://ollama.com/download/windows
```

After installation, Ollama runs as a service. Pull a model:

```powershell
# Pull a model (choose one)
ollama pull llama3.2        # Default, good balance
ollama pull mistral         # Fast, good for coding
ollama pull codellama       # Specialized for code
ollama pull phi3            # Small and fast

# Verify it's running
ollama list
```

Ollama runs on `http://localhost:11434` - no API key needed.

---

### 2. Install Required PowerShell Modules

```powershell
# Required for AI execution (timeout protection)
Install-Module ThreadJob -Scope CurrentUser

# Optional but recommended
Install-Module PSReadLine -Scope CurrentUser -Force
Install-Module Terminal-Icons -Scope CurrentUser
Install-Module posh-git -Scope CurrentUser
```

---

### 3. Configure API Keys (for Cloud Providers)

Edit `ChatConfig.json` in your PowerShell profile directory:

```json
{
  "apiKeys": {
    "ANTHROPIC_API_KEY": "sk-ant-api03-your-key-here",
    "OPENAI_API_KEY": "sk-your-openai-key-here"
  }
}
```

**Or** set via terminal (persists across sessions):
```powershell
Set-ChatApiKey -Provider anthropic -ApiKey "sk-ant-api03-..."
Set-ChatApiKey -Provider openai -ApiKey "sk-..."
```

---

### 4. Install Terminal Tools (Optional but Recommended)

```powershell
# Syntax-highlighted file viewing
winget install sharkdp.bat

# Markdown rendering
winget install charmbracelet.glow

# File explorer
winget install Canop.broot

# Fuzzy finder
winget install fzf

# Fast search
winget install BurntSushi.ripgrep.MSVC

# Data viewer (requires Python)
pip install visidata
```

Check what's installed:
```powershell
tools
```

---

## Usage

### Start a Chat Session

```powershell
# Default (Ollama)
chat

# Specific providers
chat-ollama          # Local Ollama
chat-local           # Local LM Studio
chat-anthropic       # Claude API (needs key)

# With options
chat -Provider ollama -Model llama3.2 -Stream
```

### In-Chat Commands

| Command | Action |
|---------|--------|
| `exit` | End session |
| `clear` | Reset conversation |
| `save` | Save to JSON |
| `tokens` | Show token count |
| `switch <provider>` | Change provider |
| `model <name>` | Change model |

### AI Can Execute Commands

The AI can run PowerShell commands using:
- `EXECUTE: get-process`
- `{"action":"execute","command":"get-process"}`
- `{"intent":"open_word"}`

All executions are logged and require confirmation for non-read-only commands.

---

## File Structure

```
WindowsPowerShell/
├── Microsoft.PowerShell_profile.ps1  # Main profile (~150 lines)
├── ChatConfig.json                    # API keys & settings
├── NaturalLanguageMappings.json       # Command translations
├── UserAliases.ps1                    # Your custom aliases
└── Modules/                           # 24 focused modules
    ├── ConfigLoader.ps1               # Config & .env loading
    ├── CommandValidation.ps1          # Command whitelist
    ├── AIExecution.ps1                # AI command gateway
    ├── ChatSession.ps1                # Chat loop
    ├── ChatProviders.ps1              # LLM backends
    ├── IntentAliasSystem.ps1          # Intent actions
    ├── SystemUtilities.ps1            # sudo, ports, uptime
    ├── DockerTools.ps1                # Docker shortcuts
    ├── DevTools.ps1                   # IDE launchers
    └── ...                            # See README for full list
```

---

## Troubleshooting

### "Ollama not responding"
```powershell
# Check if Ollama is running
ollama list

# Restart Ollama service
Stop-Process -Name ollama -Force
ollama serve
```

### "API key not found"
1. Check `ChatConfig.json` has your key
2. Or run: `Set-ChatApiKey -Provider anthropic -ApiKey "your-key"`
3. Reload: `. $PROFILE`

### "Command not in safe actions list"
The AI can only run whitelisted commands. View them:
```powershell
actions
actions -Category FileOperations
```

### Profile won't load
```powershell
# Check for errors
powershell -NoProfile
. $PROFILE
```

---

## Package Manager

### Health Check
```powershell
health            # Check status of all tools
```

### Install Missing Tools
```powershell
install-tools              # Install all missing enabled tools
install-tools -Force       # Install without prompting
Install-Tool bat           # Install specific tool
```

### Configure Preferences
Edit `ToolPreferences.json` to:
- Enable/disable auto-install
- Choose which tool categories to enable
- Disable specific tools

### Migration Helpers
```powershell
bash-help         # Bash to PowerShell command guide
zsh-help          # Zsh/Oh-My-Zsh to PowerShell guide
```

---

## Quick Reference

```powershell
tips              # Show all commands
providers         # Show chat providers
intent-help       # Show AI intents
actions           # Show safe commands
tools             # Show terminal tools
health            # Tool health check
install-tools     # Install missing tools
bash-help         # Bash migration guide
zsh-help          # Zsh migration guide
session-info      # Show current session
profile-timing    # Show load performance
workflows         # List available workflows
```

---

## Development Notes

### Linter Warnings

You may see PSScriptAnalyzer warnings like:
```
The cmdlet 'chat-ollama' uses an unapproved verb.
```

**These are intentional.** PowerShell prefers formal `Verb-Noun` naming (like `Get-Process`), but these are convenience aliases designed for quick daily use, not formal cmdlets. They work correctly and can be safely ignored.

Affected functions: `chat-ollama`, `chat-anthropic`, `chat-local`, `chat-llm`, `profile-edit`, `pwd-full`, `pwd-short`
