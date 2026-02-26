<p align="center">
  <img src="assets/bildsy-logo.png" alt="BildsyPS Logo" width="200"/>
</p>

<h1 align="center">BildsyPS</h1>

> Your terminal, orchestrated. BildsyPS is an AI shell environment that understands your context — your files, your git state, your running processes — and acts on your behalf. Chat with Claude, GPT, or local LLMs. Execute commands, manage files, search the web, run autonomous agents, and connect to MCP servers. All from PowerShell, all local-first, nothing phoning home.

![PowerShell](https://img.shields.io/badge/PowerShell-7.0%2B-blue)
![Version](https://img.shields.io/badge/Version-1.5.0-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![AI](https://img.shields.io/badge/AI-Claude%20%7C%20GPT%20%7C%20Ollama-purple)

**Topics:** `bildsyps` `ai-assistant` `claude` `chatgpt` `ollama` `llm` `terminal` `mcp` `agent` `automation` `cli` `app-builder` `exe`

## Features

### 🤖 AI Chat Assistant
- **Multi-provider support**: Ollama, Anthropic Claude, OpenAI, LM Studio, + **llm CLI** (100+ plugins)
- **Command execution**: AI can run safe PowerShell commands on your behalf
- **Intent system**: 80+ natural language actions like "create a doc called Report"
- **Streaming responses**: Real-time output from AI providers
- **MCP Client**: Connect to external MCP servers for extended capabilities
- **Conversation persistence**: SQLite database with FTS5 full-text search across all sessions
- **Folder awareness**: AI sees your current directory, git status, and file structure
- **Token budget management**: Intelligently trims context to fit model limits, summarizes evicted messages
- **Secret scanner**: Detects exposed API keys, tokens, and credentials in files and staged git commits
- **Vision support**: Send screenshots and images to Claude/GPT-4o for analysis
- **OCR integration**: Tesseract OCR for images, pdftotext for PDFs, with vision API fallback
- **Tab completion**: Dynamic argument completers on all public functions — providers, session names, skill names, workflow names, build names, MCP servers, task IDs, artifact files, git branches

### 🧠 Autonomous Agent

Run multi-step tasks with a single command. The agent reasons, plans, uses tools, and adapts — no predefined workflow required.

```powershell
# One-shot task
agent "check AAPL and MSFT stock prices and calculate the difference"

# Interactive mode — follow-up tasks with shared memory
agent -Interactive "research PowerShell async patterns"

# Pre-seed working memory
agent -Memory @{ budget = "5000" } "calculate 8% tax on the budget"
```

**Built-in agent tools:**

| Tool | Description |
|------|-------------|
| `calculator` | Evaluate math expressions |
| `datetime` | Current time, date math, timezone conversion |
| `web_search` | Search the web |
| `fetch_url` | Fetch and extract web page content |
| `wikipedia` | Search Wikipedia |
| `stock_quote` | Live stock price via Yahoo Finance (no API key) |
| `json_parse` | Parse JSON, extract values by dot-path |
| `regex_match` | Test regex patterns, return matches |
| `read_file` | Read local text files |
| `shell` | Execute PowerShell (safety-gated) |
| `store` / `recall` | Working memory — save values between steps |
| `screenshot` | Capture and analyze the screen via vision model |
| `ocr` | Extract text from images and PDFs via Tesseract |
| `build_app` | Build a standalone .exe from a natural language prompt |
| `search_history` | Full-text search across past conversations |
| `spawn_agent` | Delegate sub-tasks to child agents (parallel or sequential, depth-limited) |

Plugins can register additional tools via `Register-AgentTool`.

### Hierarchical Agent Orchestration

Agents can spawn sub-agents for focused sub-tasks with depth-limited recursion (max depth 2):

```powershell
# The LLM can dynamically delegate during an agent run:
# Single sub-task
{"tool":"spawn_agent","task":"research PowerShell async patterns"}

# Parallel sub-tasks via thread jobs
{"tool":"spawn_agent","tasks":"[{\"task\":\"research X\"},{\"task\":\"research Y\"}]","parallel":"true"}
```

**Memory isolation:** depth 0-1 shares parent memory; depth 1-2 gets an isolated copy. Parallel jobs are fully isolated per thread with results merged on completion.

### 🏗️ App Builder — Prompt to .exe

Describe an app in plain English and get a compiled Windows executable.

```powershell
# Build a standalone .exe (defaults to PowerShell/WinForms lane)
build "a todo list app with categories and due dates"

# Force a specific framework
build python-tk "a calculator with scientific functions"
build python-web "a markdown editor with live preview"

# Override token budget for complex apps
build -tokens 32000 "a project management dashboard"

# Skip branding (future paid tier)
build -nobranding "a simple timer"

# List all builds
builds

# Modify an existing build with diff-based edits
rebuild my-todo-app "add a dark mode toggle"
```

**Five build lanes:**

| Lane | Output | Compiler | Dependencies |
|------|--------|----------|--------------|
| **powershell** (default) | `.exe` WinForms/WPF | ps2exe | ps2exe from PSGallery only |
| **powershell-module** | `.zip` module package | zip | None |
| **python-tk** | `.exe` Tkinter | PyInstaller | Python 3.8+ |
| **python-web** | `.exe` PyWebView + HTML/CSS/JS | PyInstaller | Python 3.8+ + pywebview |
| **tauri** | `.exe` Rust + HTML/CSS/JS | cargo | Rust toolchain + Node.js |

PowerShell is the default lane — no venv, no pip, no PyInstaller. Just a direct `.ps1` → `.exe` compilation. Token budget auto-detects from your model's context window with per-lane caps and floors. Every generated app includes "Built with BildsyPS" branding.

**Pipeline v2** — the generation pipeline now includes a planning agent (for complex specs), a fix loop with up to 2 auto-retries on validation failure, a review agent that checks generated code against the spec, and a build memory system that learns from past failures and injects constraints into future prompts.

### 🔧 Available Intents

| Category | Intents |
|----------|---------|
| **Documents** | `create_docx`, `create_xlsx` — Create and open Office documents |
| **Clipboard** | `clipboard_read`, `clipboard_write`, `clipboard_format_json`, `clipboard_case` |
| **Files** | `read_file`, `file_stats`, `save_code`, `list_artifacts` — Files and code artifacts |
| **Git** | `git_status`, `git_log`, `git_commit`, `git_push`, `git_pull`, `git_diff` |
| **Calendar** | `calendar_today`, `calendar_week`, `calendar_create` (Outlook) |
| **Web** | `web_search`, `wikipedia`, `fetch_url`, `search_web`, `browser_tab`, `browser_content` |
| **Apps** | `open_word`, `open_excel`, `open_notepad`, `open_folder`, `open_terminal` |
| **MCP** | `mcp_servers`, `mcp_connect`, `mcp_tools`, `mcp_call` |
| **Workflows** | `run_workflow`, `list_workflows`, `schedule_workflow`, `list_scheduled_workflows`, `remove_scheduled_workflow` |
| **System** | `service_restart`, `system_info`, `network_status`, `process_list`, `process_kill`, `run_code` |
| **Vision** | `analyze_image`, `screenshot`, `ocr_file` — Image analysis, screen capture, OCR |
| **Productivity** | `build_app` — Build a standalone .exe from a natural language prompt |
| **Agent** | `agent_task` — Delegate a multi-step task to the autonomous agent |

### 🧩 Plugin Architecture

Drop `.ps1` files into `Plugins/` to add new intents without touching core code:

```powershell
plugins                        # List active & disabled plugins
Enable-BildsyPSPlugin 'Example'  # Activate a plugin
new-plugin 'MyPlugin'          # Scaffold from template
test-plugin -All               # Run plugin self-tests
watch-plugins                  # Auto-reload on file save
plugin-config Pomodoro          # View plugin configuration
```

**Plugin features:** dependency resolution, per-plugin config (`Plugins/Config/*.json`), lifecycle hooks (`OnLoad`/`OnUnload`), self-test framework, helper function sharing, version compatibility checks, hot-reload file watcher.

See `Plugins/_Example.ps1` for the full template.

### 🎯 Custom User Skills

Define your own intents via JSON — no PowerShell required. Skills are auto-created from the example template on first run.

```json
{
  "skills": {
    "deploy_staging": {
      "description": "Pull latest and show status",
      "triggers": ["deploy staging", "push to staging"],
      "parameters": [{"name": "branch", "default": "main"}],
      "confirm": true,
      "steps": [
        {"command": "git checkout {branch}"},
        {"command": "git pull origin {branch}"},
        {"intent": "git_status"}
      ]
    }
  }
}
```

```powershell
# Skills are directly callable from the prompt
deploy_staging                          # invoke by name
deploy_staging main                     # with positional args

# Or programmatically
Invoke-UserSkill -Name 'deploy_staging' -Parameters @{ branch = 'main' }

skills              # List user skills
new-skill 'name'    # Create interactively
reload-skills       # Reload from JSON
```

**Trigger phrases** in the `triggers` array register as intent aliases — the AI can invoke your skill by natural language match. `UserSkills.json` is auto-created from the example template on first run.

### 🔄 Multi-Step Workflows

Chain multiple intents together for complex tasks:

```powershell
# List available workflows
workflows

# Run a workflow
workflow daily_standup
workflow research_and_document -Params @{ topic = "AI agents" }

# Stop on first failure
Invoke-Workflow -Name daily_standup -StopOnError

# AI can trigger via intent:
# {"intent":"run_workflow","name":"research_and_document","params":"{\"topic\":\"PowerShell\"}"}
```

**Built-in Workflows:**
| Workflow | Description |
|----------|-------------|
| `daily_standup` | Show calendar + git status |
| `research_and_document` | Search web + create notes doc |
| `project_setup` | Create folder + init git |

### 🛠️ Terminal Tools Integration
- **bat** - Syntax-highlighted file viewing
- **glow** - Markdown rendering
- **broot** - Interactive file navigation
- **fzf** - Fuzzy finding
- **jq/yq** - JSON/YAML processing

### 📁 Navigation Utilities
- `tree` - Directory tree visualization
- `size` - Folder size analysis
- `z` - Quick directory jumping
- `..`, `...`, `....` - Quick parent navigation
- `gco`, `gmerge`, `grb` - Git checkout/merge/rebase with branch tab completion

## Quick Start

```powershell
# Start AI chat (local Ollama)
chat

# Start AI chat with Claude
chat -p anthropic

# Start with folder awareness (AI sees your current directory)
chat -FolderAware   # or: chat -f

# Resume last session with context recall
chat -Continue      # or: chat -c

# Show available commands
tips

# Check tool health
health
```

## Configuration

### API Keys
Edit `ChatConfig.json` to add your API keys:
```json
{
  "apiKeys": {
    "ANTHROPIC_API_KEY": "your-key-here",
    "OPENAI_API_KEY": "your-key-here"
  }
}
```

### Default Provider
Change the default chat provider in `ChatConfig.json`:
```json
{
  "defaults": {
    "provider": "ollama",
    "model": "llama3.2"
  }
}
```

Provider-level overrides (e.g. default model per provider) are also supported:
```json
{
  "providers": {
    "anthropic": { "defaultModel": "claude-sonnet-4-6" }
  }
}
```

## File Structure

```
BildsyPS/
├── Microsoft.PowerShell_profile.ps1  # Main profile (loads modules)
├── ChatConfig.json                   # API keys and settings
├── ToolPreferences.json              # Tool preferences
├── NaturalLanguageMappings.json      # Command mappings
├── UserSkills.json                   # Custom user-defined intents (your file)
├── UserSkills.example.json           # Template for user skills
├── UserAliases.ps1                   # Your custom persistent aliases
├── BildsyPS.psm1                     # Module loader
├── BildsyPS.psd1                     # Module manifest
├── Modules/
│   ├── ConfigLoader.ps1              # .env and config loading
│   ├── PlatformUtils.ps1             # Cross-platform helpers
│   ├── SecurityUtils.ps1             # Path/URL security
│   ├── SecretScanner.ps1             # API key / credential leak detection
│   ├── CommandValidation.ps1         # Command whitelist & safety
│   ├── SystemUtilities.ps1           # uptime, hwinfo, ports, sudo, PATH
│   ├── ArchiveUtils.ps1              # zip, unzip
│   ├── DockerTools.ps1               # Docker shortcuts
│   ├── DevTools.ps1                  # IDE launchers, dev checks
│   ├── NaturalLanguage.ps1           # NL to command translation
│   ├── ResponseParser.ps1            # Parse AI responses, format markdown
│   ├── DocumentTools.ps1             # OpenXML document creation
│   ├── SafetySystem.ps1              # AI execution safety + secret scanning
│   ├── SystemCleanup.ps1             # Wrapped cleanup commands (flush DNS, restart explorer)
│   ├── TerminalTools.ps1             # bat, glow, broot, fzf integration
│   ├── NavigationUtils.ps1           # Navigation & git shortcuts
│   ├── PackageManager.ps1            # Tool installation
│   ├── WebTools.ps1                  # Web search APIs
│   ├── ProductivityTools.ps1         # Clipboard, Git, Calendar
│   ├── MCPClient.ps1                 # MCP protocol client
│   ├── BrowserAwareness.ps1          # Browser tab URL + content reading
│   ├── VisionTools.ps1               # Screenshot capture + vision model analysis
│   ├── OCRTools.ps1                  # Tesseract OCR + pdftotext integration
│   ├── CodeArtifacts.ps1             # AI code save + execute + tracking
│   ├── AppBuilder.ps1                # Prompt-to-executable pipeline (ps2exe, PyInstaller)
│   ├── FzfIntegration.ps1            # Fuzzy finder integration
│   ├── PersistentAliases.ps1         # User-defined aliases
│   ├── ProfileHelp.ps1               # Help, tips, system prompt
│   ├── FolderContext.ps1             # Folder awareness for AI context
│   ├── ToastNotifications.ps1        # BurntToast/.NET notifications
│   ├── ChatStorage.ps1               # SQLite persistence + FTS5 full-text search
│   ├── ChatSession.ps1               # LLM chat loop + session management
│   ├── ChatProviders.ps1             # AI provider implementations
│   ├── AgentHeartbeat.ps1            # Cron-triggered background agent tasks
│   ├── UserSkills.ps1                # JSON user-defined intent loader
│   ├── PluginLoader.ps1              # Plugin system (deps, config, hooks, tests)
│   ├── IntentAliasSystem.ps1         # Intent system orchestrator (loads below)
│   ├── IntentRegistry.ps1            # Intent metadata + category definitions
│   ├── IntentActions.ps1             # Core intent scriptblocks (docs, web, git, etc.)
│   ├── IntentActionsSystem.ps1       # System/filesystem/workflow/vision/build scriptblocks
│   ├── WorkflowEngine.ps1            # Multi-step workflow engine
│   ├── IntentRouter.ps1              # Intent router, help, tab completion
│   ├── AgentTools.ps1                # Agent tool registry (17 built-in tools incl. spawn_agent)
│   └── AgentLoop.ps1                 # Autonomous agent engine (ReAct + tools + memory + sub-agents)
├── Plugins/
│   ├── _Example.ps1                  # Reference plugin template
│   ├── _Pomodoro.ps1                 # Pomodoro timer plugin
│   ├── _QuickNotes.ps1               # Note-taking plugin
│   └── Config/                       # Per-plugin configuration overrides
├── Tests/                            # 17 Pester test files (368 tests)
├── README.md
├── VISION.md                         # Product direction and roadmap
├── CHANGELOG.md                      # Release history
├── CONTRIBUTING.md                   # Contributor guide
└── SETUP.md                          # Detailed setup instructions
```

## Chat Commands

While in chat mode:
- `exit` - Exit chat (auto-saves session)
- `clear` - Clear conversation (auto-saves previous)
- `save` / `save <name>` - Save session
- `resume` / `resume <name>` - Load a saved session
- `sessions` - Browse all saved sessions
- `search <keyword>` - Search across all sessions
- `rename <name>` - Rename current session
- `delete <name>` - Delete a saved session
- `export` / `export <name>` - Export session to markdown
- `budget` - Show token usage breakdown by role
- `folder` - Inject current directory context
- `folder <path>` - Inject a specific directory
- `agent <task>` or `/agent <task>` - Run autonomous agent to complete a multi-step task
- `/agent` - Enter interactive agent mode (follow-up tasks with shared memory)
- `/tools` - List all registered agent tools
- `/steps` - Show steps from last agent run
- `/memory` - Show agent working memory
- `/plan` - Show agent's last announced plan
- `vision` / `vision <path>` - Analyze an image or screenshot with vision AI
- `build "prompt"` - Build a standalone .exe from a description
- `builds` - List all previous builds
- `rebuild <name> "changes"` - Modify and rebuild an existing app
- `switch` - Change AI provider
- `model <name>` - Change model

### Session Flags
```powershell
chat -Resume        # or: chat -r  — resume last session
chat -Continue      # or: chat -c  — resume + inject summary so model recalls context
chat -FolderAware   # or: chat -f  — inject current directory on start, auto-update on cd
chat -AutoTrim      # automatically trim context when approaching model limits
```

## Safety Features

- **Command whitelist**: Only approved commands can be executed
- **Confirmation prompts**: Dangerous commands require approval — `RequiresConfirmation` intents always prompt, even in agent mode
- **Rate limiting**: Prevents runaway execution
- **Execution logging**: All AI commands are logged
- **Path security**: File read/write operations validated against allowed roots
- **Calculator sandboxing**: Only `[math]::` .NET calls permitted; arbitrary type access blocked
- **Secret scanning**: Detects API keys, tokens, and credentials in files and staged git commits at startup; lookbehind-aware regex avoids false positives on UI variable names
- **Code validation**: App Builder validates generated code for syntax errors, dangerous patterns, and secret leaks before compilation; code generation prompts forbid hardcoded/placeholder API keys and require runtime settings UI instead

## Requirements

- **PowerShell 7.0+** (Windows/Mac/Linux)
- Windows 10/11, macOS, or Linux
- Optional: Ollama for local AI
- Optional: Anthropic/OpenAI API keys for cloud AI
- Optional: Node.js for MCP servers
- Optional: Tesseract OCR for image text extraction
- Optional: Python 3.8+ for python-tk / python-web build lanes
- Optional: ps2exe (`Install-Module ps2exe`) for PowerShell build lane

## Installation

### PowerShell 7 (Recommended)
```powershell
# Windows
git clone https://github.com/gsultani1/BildsyPS.git "$HOME\Documents\PowerShell"

# macOS/Linux
git clone https://github.com/gsultani1/BildsyPS.git ~/.config/powershell
```

### Setup
1. Copy `ChatConfig.example.json` to `ChatConfig.json`
2. Add your API keys to `ChatConfig.json`
3. Restart PowerShell or run `. $PROFILE`

See [SETUP.md](SETUP.md) for detailed setup instructions including optional dependencies.

## MCP (Model Context Protocol) Support

Connect to external MCP servers to extend AI capabilities.

### Quick Start
```powershell
# Register common MCP servers
mcp-register

# List registered servers
mcp-servers

# Connect to a server
mcp-connect filesystem

# Call a tool
mcp-call -ServerName filesystem -ToolName read_file -Arguments @{path="C:\file.txt"}
```

### Available MCP Servers
| Server | Description | Requirements |
|--------|-------------|--------------|
| `filesystem` | File system access | Node.js/npx |
| `memory` | Persistent knowledge graph | Node.js/npx |
| `fetch` | Web content fetching | Node.js/npx |
| `brave-search` | Web search | BRAVE_API_KEY env var |
| `github` | GitHub operations | GITHUB_TOKEN env var |

### Register Custom Server
```powershell
Register-MCPServer -Name "myserver" `
    -Command "npx" `
    -Args @("-y", "@org/mcp-server-name") `
    -Description "My custom server"
```

## Roadmap

BildsyPS today is a shell orchestrator — an AI that understands your terminal context and acts on your behalf. The direction is broader: **mission control for your entire computer**.

See [VISION.md](VISION.md) for the full product direction.

| Status | Feature |
|--------|---------|
| ✅ | Multi-provider AI chat (Claude, GPT, Ollama, LM Studio, llm CLI) |
| ✅ | Intent system — 80+ natural language actions |
| ✅ | Multi-step workflows + Windows Task Scheduler integration |
| ✅ | Conversation persistence — SQLite with FTS5 full-text search |
| ✅ | Token budget management — model-aware context trimming |
| ✅ | Folder awareness — AI sees your directory, git state, file structure |
| ✅ | MCP client — connect to any MCP server |
| ✅ | Safety system — command whitelist, confirmation prompts, rate limiting |
| ✅ | Secret scanner — detect exposed API keys in files and staged git commits |
| ✅ | Toast notifications — BurntToast/.NET alerts on task completions |
| ✅ | Plugin architecture — drop `.ps1` files with deps, config, hooks, tests, hot-reload |
| ✅ | Custom user skills — define intents via JSON config, no PowerShell required |
| ✅ | Browser awareness — read active tab URL, fetch page content via UI Automation |
| ✅ | Code artifacts — save, execute, and track AI-generated code blocks |
| ✅ | **Autonomous agent** — ReAct loop, 17 built-in tools, working memory, interactive mode, hierarchical sub-agents |
| ✅ | **Codebase audit** — security hardening, parse fixes, duplicate removal, deterministic ordering |
| ✅ | **Vision model support** — send screenshots/images to Claude/GPT-4o, auto-resize, clipboard capture |
| ✅ | **OCR integration** — Tesseract for scanned docs, pdftotext for PDFs, vision API fallback |
| ✅ | **SQLite + FTS5** — full-text search over all conversation history, session persistence |
| ✅ | **Agent heartbeat** — cron-triggered background tasks via Windows Task Scheduler |
| ✅ | **App Builder** — describe an app in English → get a compiled .exe (PowerShell, Python-TK, Python-Web) |
| ✅ | **Hierarchical agent orchestration** — `spawn_agent` tool, depth-limited recursion, memory isolation, parallel thread jobs |
| ✅ | **E2E test suite** — 368 tests across 17 modules, 0 failures; Pester v5 hardened |
| ✅ | **App Builder** — describe an app in English → get a compiled .exe (PowerShell, Python-TK, Python-Web, Tauri) |
| ✅ | **PowerShell Module lane** — generate, validate, and package a `.psm1`/`.psd1` module as a zip |
| ✅ | **Build Pipeline v2** — planning agent, fix loop (2 retries), review agent, build memory with constraint learning |
| ✅ | **E2E test suite** — 133 tests, 0 failures; Pester v5 hardened |
| ✅ | **UserSkills v2** — shell-invocable functions, `Invoke-UserSkill`, trigger phrase registration, auto-created JSON |
| ✅ | **Tab completion** — dynamic argument completers across all public functions; `gm` → `gmerge` alias conflict resolved |
| 🔜 | Browser automation — Selenium WebDriver integration |
| 🔜 | Remote listener + webhooks — receive commands via Twilio/HTTP |
| 🔜 | GUI layer — mission control dashboard for your entire computer |

## License

MIT License - See LICENSE file

## Author

George Sultani
