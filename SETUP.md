# BildsyPS Setup Guide
> **v1.5.0** — 133 tests, 0 failures

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

### 5. App Builder Dependencies (Optional)

The App Builder compiles standalone `.exe` files (or module packages) from natural language prompts. Dependencies vary by build lane:

**PowerShell lane (default — recommended):**
```powershell
# Only dependency — compiles .ps1 to .exe
Install-Module ps2exe -Scope CurrentUser
```

**PowerShell Module lane — no extra dependencies:**
```powershell
# Generates a .psm1 + .psd1 module and packages it as a .zip
# No additional tools required
build powershell-module "a module for parsing log files"
```

**Python lanes (python-tk, python-web):**
```powershell
# Python 3.8+ required
python --version

# PyInstaller is installed automatically in a per-build venv
# For python-web lane, pywebview is also installed automatically
```

**Tauri lane:**
```powershell
# Rust toolchain required
winget install Rustlang.Rustup
rustup default stable

# Node.js required for Tauri CLI
winget install OpenJS.NodeJS

# Tauri CLI installed automatically during first build
```

---

### 6. Vision & OCR Dependencies (Optional)

```powershell
# Tesseract OCR — for image text extraction
winget install UB-Mannheim.TesseractOCR

# pdftotext — for PDF text extraction (part of Xpdf tools)
# Download from: https://www.xpdfreader.com/download.html
# Add to PATH after install

# Vision models work out of the box with Claude/GPT-4o (cloud)
# For local vision, pull a multimodal model:
ollama pull llava
ollama pull llama3.2-vision
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

# Anthropic models: claude-sonnet-4-6 (default), claude-opus-4-6, claude-haiku-4-5-20251001
chat -Provider anthropic -Model claude-opus-4-6
```

### In-Chat Commands

| Command | Action |
|---------|--------|
| `exit` | End session (auto-saves) |
| `clear` | Reset conversation (saves previous) |
| `save` / `save <name>` | Save session |
| `resume` / `resume <name>` | Load a saved session |
| `sessions` | Browse all saved sessions |
| `search <keyword>` | Search across sessions |
| `rename <name>` | Rename current session |
| `export` / `export <name>` | Export session to markdown |
| `budget` | Show token usage breakdown |
| `folder` | Inject current directory context |
| `folder --preview` | Show what the AI sees (without injecting) |
| `folder <path>` | Inject a specific directory |
| `switch` | Change AI provider |
| `model <name>` | Change model |
| `agent <task>` or `/agent <task>` | Run autonomous agent task |
| `/agent` | Interactive agent mode (follow-up tasks) |
| `/tools` | List agent tools |
| `/steps` | Show steps from last agent run |
| `/memory` | Show agent working memory |
| `/plan` | Show agent's last plan |
| `vision` / `vision <path>` | Analyze image or screenshot with vision AI |
| `vision --full` | Send at full resolution (skip auto-resize) |
| `build "prompt"` | Build a standalone .exe from a description |
| `builds` | List all previous builds |
| `rebuild <name> "changes"` | Modify and rebuild an existing app |
| `heartbeat start` | Start agent heartbeat (cron-triggered tasks) |
| `heartbeat stop` | Stop agent heartbeat |

### AI Can Execute Commands

The AI can run PowerShell commands using:
- `EXECUTE: get-process`
- `{"action":"execute","command":"get-process"}`
- `{"intent":"open_word"}`

All executions are logged and require confirmation for non-read-only commands.

### Autonomous Agent

The agent reasons, plans, and uses tools autonomously:

```powershell
# One-shot task
agent "check AAPL stock price and calculate 10% of it"

# Interactive mode — follow-up tasks with shared memory
agent -Interactive "research PowerShell automation"

# Pre-seed working memory
agent -Memory @{ budget = "5000" } "calculate 8% tax on the budget"

# Inspect last run
agent-steps    # Show what the agent did
agent-memory   # Show stored values
agent-plan     # Show the agent's plan
agent-tools    # List all available tools (17 built-in, incl. spawn_agent for sub-tasks)
```

---

## File Structure

```
BildsyPS/
├── Microsoft.PowerShell_profile.ps1  # Main profile (loads modules)
├── ChatConfig.json                    # API keys & settings
├── BildsyPS.psm1 / BildsyPS.psd1         # Module loader + manifest
├── NaturalLanguageMappings.json       # Command translations
├── UserSkills.json                    # Your custom intents (JSON)
├── UserAliases.ps1                    # Your custom aliases
├── Modules/                           # 40+ focused modules
│   ├── ChatProviders.ps1              # LLM backends (Ollama, Anthropic, OpenAI, LM Studio, llm CLI)
│   ├── ChatSession.ps1                # Chat loop + session management
│   ├── ChatStorage.ps1                # SQLite persistence + FTS5 full-text search
│   ├── AppBuilder.ps1                 # Prompt-to-executable pipeline (ps2exe, PyInstaller)
│   ├── VisionTools.ps1                # Screenshot capture + vision model analysis
│   ├── OCRTools.ps1                   # Tesseract OCR + pdftotext integration
│   ├── SecretScanner.ps1              # API key / credential leak detection
│   ├── AgentLoop.ps1                  # Autonomous agent (ReAct + 17 tools + memory + sub-agents)
│   ├── AgentHeartbeat.ps1             # Cron-triggered background tasks
│   ├── PluginLoader.ps1               # Plugin system (deps, config, hooks, tests)
│   ├── IntentAliasSystem.ps1          # Intent routing (80+ intents)
│   └── ...                            # See README for full list (43 modules total)
└── Plugins/                           # Drop-in plugin directory
    ├── _Example.ps1                   # Reference template
    ├── _Pomodoro.ps1                  # Timer plugin
    └── _QuickNotes.ps1                # Note-taking plugin
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

### Agent blocked on `RequiresConfirmation` intent
The agent will prompt for confirmation on sensitive intents (git push, process kill, etc.) even in autonomous mode. This is by design. Type `y` to allow or `n` to skip. Use `-Force` only if you want to bypass confirmation entirely.

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

## Tab Completion

All public functions have dynamic argument completers. Press **Tab** after any parameter to get live suggestions:

```powershell
Resume-Chat -Name <tab>              # lists saved sessions from SQLite
Remove-ChatSession -Name <tab>       # lists saved sessions
Export-ChatSession -Name <tab>       # lists saved sessions

Set-DefaultChatProvider -Provider <tab>   # lists configured providers
chat -Provider <tab>                      # lists configured providers

Invoke-UserSkill -Name <tab>         # lists loaded skills
Remove-UserSkill -Name <tab>         # lists loaded skills

Invoke-Workflow -Name <tab>          # lists workflows (tooltip = description)

Connect-MCPServer -Name <tab>        # lists registered MCP servers
Disconnect-MCPServer -Name <tab>     # lists connected MCP servers
Invoke-MCPTool -ServerName <tab>     # lists connected MCP servers

Remove-AppBuild -Name <tab>          # lists builds from filesystem
Update-AppBuild -Name <tab>          # lists builds from filesystem
New-AppBuild -Framework <tab>        # powershell / powershell-module / python-tk / python-web / tauri

Remove-AgentTask -Id <tab>           # lists heartbeat task IDs
Enable-AgentTask -Id <tab>           # lists heartbeat task IDs
Disable-AgentTask -Id <tab>          # lists heartbeat task IDs

Remove-PersistentAlias -Name <tab>   # lists aliases from UserAliases.ps1
Remove-Artifact -Name <tab>          # lists files in Artifacts/

gco -Branch <tab>                    # lists git branches
gmerge -Branch <tab>                 # lists git branches
grb -Branch <tab>                    # lists git branches
```

---

## Quick Reference

```powershell
# General
tips              # Show all commands
providers         # Show chat providers
intent-help       # Show AI intents
actions           # Show safe commands
tools             # Show terminal tools
health            # Tool health check
profile-timing    # Show load performance

# Plugins
plugins           # List active & disabled plugins
new-plugin 'Name' # Scaffold a new plugin
test-plugin -All  # Run plugin self-tests
watch-plugins     # Auto-reload on file save
plugin-config X   # View plugin configuration

# User Skills
skills            # List user-defined skills
new-skill 'Name'  # Create a skill interactively
reload-skills     # Reload from UserSkills.json
deploy_staging                          # invoke skill
deploy_staging main                     # with positional args
Invoke-UserSkill -Name 'deploy_staging' -Parameters @{ branch = 'main' }

# Agent
agent "task"      # Run autonomous agent task
agent -Interactive # Multi-turn agent session
agent-tools       # List agent tools
agent-steps       # Show last run steps
agent-memory      # Show working memory
agent-plan        # Show last plan

# Workflows
Invoke-Workflow -Name daily_standup              # Run workflow
Invoke-Workflow -Name daily_standup -StopOnError # Halt on first failure

# Workflows & Sessions
workflows         # List available workflows
session-info      # Show current session
sessions          # Browse saved sessions

# Vision & OCR
vision            # Capture screenshot and analyze
vision image.png  # Analyze a specific image
vision --full     # Send at full resolution
ocr image.png     # Extract text via Tesseract

# App Builder
build "a todo list app"              # Build .exe from prompt (PowerShell lane)
build python-tk "a calculator"       # Force Python-TK lane
build python-web "a markdown editor" # PyWebView + HTML/CSS/JS
build tauri "a native counter app"   # Rust + HTML/CSS/JS via Tauri
build powershell-module "a log parser module"  # .psm1/.psd1 zip package
build -tokens 32000 "complex app"    # Override token budget
builds                               # List all builds
rebuild my-app "add dark mode"       # Modify existing build

# Heartbeat
heartbeat start   # Start cron-triggered agent tasks
heartbeat stop    # Stop heartbeat
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

### `gm` renamed to `gmerge`

The `gm` git merge shortcut was renamed to `gmerge` because `gm` is a built-in PowerShell alias for `Get-Member`. The old name would silently shadow the built-in and prevent tab completion from working. Use `gmerge <branch>` going forward.
