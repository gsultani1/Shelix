# Shelix

> Your terminal, orchestrated. Shelix is an AI shell environment that understands your context — your files, your git state, your running processes — and acts on your behalf. Chat with Claude, GPT, or local LLMs. Execute commands, manage files, search the web, schedule workflows, and connect to MCP servers. All from PowerShell, all local-first, nothing phoning home.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![AI](https://img.shields.io/badge/AI-Claude%20%7C%20GPT%20%7C%20Ollama-purple)

**Topics:** `shelix` `ai-assistant` `claude` `chatgpt` `ollama` `llm` `terminal` `mcp` `automation` `cli`

## Features

### 🤖 AI Chat Assistant
- **Multi-provider support**: Ollama, Anthropic Claude, OpenAI, LM Studio, + **llm CLI** (100+ plugins)
- **Command execution**: AI can run safe PowerShell commands on your behalf
- **Intent system**: Natural language actions like "create a doc called Report"
- **Streaming responses**: Real-time output from AI providers
- **MCP Client**: Connect to external MCP servers for extended capabilities
- **Conversation persistence**: Sessions auto-save and resume across restarts
- **Folder awareness**: AI sees your current directory, git status, and file structure
- **Token budget management**: Intelligently trims context to fit model limits, summarizes evicted messages

### 🔧 Available Intents

| Category | Intents |
|----------|---------|
| **Documents** | `create_docx`, `create_xlsx` - Create and open Office documents |
| **Clipboard** | `clipboard_read`, `clipboard_write`, `clipboard_format_json`, `clipboard_case` |
| **Files** | `read_file`, `file_stats`, `save_code`, `list_artifacts` - Files and code artifacts |
| **Git** | `git_status`, `git_log`, `git_commit`, `git_push`, `git_pull`, `git_diff` |
| **Calendar** | `calendar_today`, `calendar_week`, `calendar_create` (Outlook) |
| **Web** | `web_search`, `wikipedia`, `fetch_url`, `search_web`, `browser_tab`, `browser_content` |
| **Apps** | `open_word`, `open_excel`, `open_notepad`, `open_folder`, `open_terminal` |
| **MCP** | `mcp_servers`, `mcp_connect`, `mcp_tools`, `mcp_call` |
| **Workflows** | `run_workflow`, `list_workflows`, `schedule_workflow`, `list_scheduled_workflows`, `remove_scheduled_workflow` |
| **System** | `service_restart`, `system_info`, `network_status`, `process_list`, `process_kill`, `run_code` |

### 🧩 Plugin Architecture

Drop `.ps1` files into `Plugins/` to add new intents without touching core code:

```powershell
plugins                        # List active & disabled plugins
Enable-ShelixPlugin 'Example'  # Activate a plugin
new-plugin 'MyPlugin'          # Scaffold from template
test-plugin -All               # Run plugin self-tests
watch-plugins                  # Auto-reload on file save
plugin-config Pomodoro          # View plugin configuration
```

**Plugin features:** dependency resolution, per-plugin config (`Plugins/Config/*.json`), lifecycle hooks (`OnLoad`/`OnUnload`), self-test framework, helper function sharing, version compatibility checks, hot-reload file watcher.

See `Plugins/_Example.ps1` for the full template.

### 🎯 Custom User Skills

Define your own intents via JSON — no PowerShell required:

```json
{
  "skills": {
    "deploy_staging": {
      "description": "Pull latest and show status",
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
skills              # List user skills
new-skill 'name'    # Create interactively
reload-skills       # Reload from JSON
```

Copy `UserSkills.example.json` → `UserSkills.json` to get started.

### 🔄 Multi-Step Workflows

Chain multiple intents together for complex tasks:

```powershell
# List available workflows
workflows

# Run a workflow
workflow daily_standup
workflow research_and_document -Params @{ topic = "AI agents" }

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
    "model": null
  }
}
```

## File Structure

```
Shelix/
├── Microsoft.PowerShell_profile.ps1  # Main profile (loads modules)
├── ChatConfig.json                   # API keys and settings
├── ToolPreferences.json              # Tool preferences
├── NaturalLanguageMappings.json      # Command mappings
├── UserSkills.json                   # Custom user-defined intents (your file)
├── UserSkills.example.json           # Template for user skills
├── UserAliases.ps1                   # Your custom persistent aliases
├── Modules/
│   ├── ConfigLoader.ps1              # .env and config loading
│   ├── PlatformUtils.ps1             # Cross-platform helpers
│   ├── SecurityUtils.ps1             # Path/URL security
│   ├── CommandValidation.ps1         # Command whitelist & safety
│   ├── SystemUtilities.ps1           # uptime, hwinfo, ports, sudo, PATH
│   ├── ArchiveUtils.ps1              # zip, unzip
│   ├── DockerTools.ps1               # Docker shortcuts
│   ├── DevTools.ps1                  # IDE launchers, dev checks
│   ├── NaturalLanguage.ps1           # NL to command translation
│   ├── AIExecution.ps1               # AI command gateway, rate limiting
│   ├── ResponseParser.ps1            # Parse AI responses, format markdown
│   ├── DocumentTools.ps1             # OpenXML document creation
│   ├── SafetySystem.ps1              # AI execution safety
│   ├── TerminalTools.ps1             # bat, glow, broot, fzf integration
│   ├── NavigationUtils.ps1           # Navigation & git shortcuts
│   ├── PackageManager.ps1            # Tool installation
│   ├── WebTools.ps1                  # Web search APIs
│   ├── ProductivityTools.ps1         # Clipboard, Git, Calendar
│   ├── MCPClient.ps1                 # MCP protocol client
│   ├── FzfIntegration.ps1            # Fuzzy finder integration
│   ├── PersistentAliases.ps1         # User-defined aliases
│   ├── ProfileHelp.ps1               # Help, tips, system prompt
│   ├── FolderContext.ps1             # Folder awareness for AI context
│   ├── ToastNotifications.ps1        # BurntToast/.NET notifications
│   ├── BrowserAwareness.ps1          # Browser tab URL + content reading
│   ├── CodeArtifacts.ps1             # AI code save + execute + tracking
│   ├── UserSkills.ps1                # JSON user-defined intent loader
│   ├── PluginLoader.ps1              # Plugin system (deps, config, hooks, tests)
│   ├── ChatSession.ps1               # LLM chat loop + session persistence
│   ├── ChatProviders.ps1             # AI provider implementations
│   ├── IntentAliasSystem.ps1         # Intent system orchestrator (loads below)
│   ├── IntentRegistry.ps1           # Intent metadata + category definitions
│   ├── IntentActions.ps1            # Core intent scriptblocks (docs, web, git, etc.)
│   ├── IntentActionsSystem.ps1      # System/filesystem/workflow scriptblocks
│   ├── WorkflowEngine.ps1           # Multi-step workflow engine
│   └── IntentRouter.ps1             # Intent router, help, tab completion
├── Plugins/
│   ├── _Example.ps1                  # Reference plugin template
│   ├── _Pomodoro.ps1                 # Pomodoro timer plugin
│   ├── _QuickNotes.ps1               # Note-taking plugin
│   └── Config/                       # Per-plugin configuration overrides
└── README.md
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
- **Confirmation prompts**: Dangerous commands require approval
- **Rate limiting**: Prevents runaway execution
- **Execution logging**: All AI commands are logged

## Requirements

- PowerShell 5.1+ (Windows) or PowerShell 7+ (Windows/Mac/Linux)
- Windows 10/11, macOS, or Linux (PS 7)
- Optional: Ollama for local AI
- Optional: Anthropic/OpenAI API keys for cloud AI
- Optional: Node.js for MCP servers

## Installation

### PowerShell 5.1 (Windows Default)
```powershell
git clone https://github.com/gsultani1/Shelix.git "$HOME\Documents\WindowsPowerShell"
```

### PowerShell 7 (Cross-Platform)
```powershell
# Windows
git clone https://github.com/gsultani1/Shelix.git "$HOME\Documents\PowerShell"

# macOS/Linux
git clone https://github.com/gsultani1/Shelix.git ~/.config/powershell
```

### Setup
1. Copy `ChatConfig.example.json` to `ChatConfig.json`
2. Add your API keys to `ChatConfig.json`
3. Restart PowerShell or run `. $PROFILE`

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

Shelix today is a shell orchestrator — an AI that understands your terminal context and acts on your behalf. The direction is broader: **mission control for your entire computer**.

See [VISION.md](VISION.md) for the full product direction.

| Status | Feature |
|--------|---------|
| ✅ | Multi-provider AI chat (Claude, GPT, Ollama, LM Studio, llm CLI) |
| ✅ | Intent system — 30+ natural language actions |
| ✅ | Multi-step workflows + Windows Task Scheduler integration |
| ✅ | Conversation persistence — sessions survive restarts |
| ✅ | Token budget management — model-aware context trimming |
| ✅ | Folder awareness — AI sees your directory, git state, file structure |
| ✅ | MCP client — connect to any MCP server |
| ✅ | Safety system — command whitelist, confirmation prompts, rate limiting |
| ✅ | Toast notifications — BurntToast/.NET alerts on task completions |
| ✅ | Plugin architecture — drop `.ps1` files with deps, config, hooks, tests, hot-reload |
| ✅ | Custom user skills — define intents via JSON config, no PowerShell required |
| ✅ | Browser awareness — read active tab URL, fetch page content via UI Automation |
| ✅ | Code artifacts — save, execute, and track AI-generated code blocks |
| 🔜 | Vision model support — send screenshots/images directly to Claude/GPT-4o |
| 🔜 | OCR integration — Tesseract for scanned docs, pdftotext for text PDFs |
| 🔜 | Agent architecture — dynamic multi-step planning, not just predefined workflows |
| 🔜 | RAG + SQLite — full-text search over conversation history, embedding-ready |
| 🔜 | Browser automation — Selenium WebDriver integration |
| 🔜 | Remote listener + webhooks — receive commands via Twilio/HTTP |
| 🔜 | GUI layer — mission control dashboard for your entire computer |

## License

MIT License - See LICENSE file

## Author

George Sultani
