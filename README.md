# PSAigent

> Turn your PowerShell terminal into an AI-powered assistant. Chat with Claude, GPT, or local LLMs. Execute commands, manage files, search the web, and connect to MCP servers.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![AI](https://img.shields.io/badge/AI-Claude%20%7C%20GPT%20%7C%20Ollama-purple)

**Topics:** `powershell` `ai-assistant` `claude` `chatgpt` `ollama` `llm` `terminal` `mcp` `automation` `cli`

## Features

### 🤖 AI Chat Assistant
- **Multi-provider support**: Ollama, Anthropic Claude, OpenAI, LM Studio, + **llm CLI** (100+ plugins)
- **Command execution**: AI can run safe PowerShell commands on your behalf
- **Intent system**: Natural language actions like "create a doc called Report"
- **Streaming responses**: Real-time output from AI providers
- **MCP Client**: Connect to external MCP servers for extended capabilities

### 🔧 Available Intents

| Category | Intents |
|----------|---------|
| **Documents** | `create_docx`, `create_xlsx` - Create and open Office documents |
| **Clipboard** | `clipboard_read`, `clipboard_write`, `clipboard_format_json`, `clipboard_case` |
| **Files** | `read_file`, `file_stats` - Analyze file contents |
| **Git** | `git_status`, `git_log`, `git_commit`, `git_push`, `git_pull`, `git_diff` |
| **Calendar** | `calendar_today`, `calendar_week`, `calendar_create` (Outlook) |
| **Web** | `web_search`, `wikipedia`, `fetch_url`, `search_web` |
| **Apps** | `open_word`, `open_excel`, `open_notepad`, `open_folder`, `open_terminal` |
| **MCP** | `mcp_servers`, `mcp_connect`, `mcp_tools`, `mcp_call` |
| **Workflows** | `run_workflow`, `list_workflows`, `research_topic`, `daily_standup` |
| **System** | `service_restart`, `system_info`, `network_status`, `process_list`, `process_kill` |

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
chat-anthropic

# Use llm CLI (100+ plugins)
Set-DefaultChatProvider llm
chat

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
WindowsPowerShell/
├── Microsoft.PowerShell_profile.ps1  # Main profile (~150 lines, loads modules)
├── ChatConfig.json                   # API keys and settings
├── ToolPreferences.json              # Tool preferences
├── NaturalLanguageMappings.json      # Command mappings
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
│   ├── ChatSession.ps1               # LLM chat loop
│   ├── ChatProviders.ps1             # AI provider implementations
│   └── IntentAliasSystem.ps1         # Intent routing system
└── README.md
```

## Chat Commands

While in chat mode:
- `exit` - Exit chat
- `clear` - Clear conversation history
- `save` - Save conversation to file
- `tokens` - Show token usage
- `switch` - Change AI provider
- `model <name>` - Change model

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
git clone https://github.com/gsultani1/PSAIgent.git "$HOME\Documents\WindowsPowerShell"
```

### PowerShell 7 (Cross-Platform)
```powershell
# Windows
git clone https://github.com/gsultani1/PSAIgent.git "$HOME\Documents\PowerShell"

# macOS/Linux
git clone https://github.com/gsultani1/PSAIgent.git ~/.config/powershell
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

## Development Notes

### Linter Warnings

You may see PSScriptAnalyzer warnings like:
```
The cmdlet 'chat-ollama' uses an unapproved verb.
```

**These are intentional.** PowerShell prefers formal `Verb-Noun` naming (like `Get-Process`), but these are convenience aliases designed for quick daily use, not formal cmdlets. They work correctly.

Affected functions: `chat-ollama`, `chat-anthropic`, `chat-local`, `chat-llm`, `profile-edit`, `pwd-full`, `pwd-short`

## License

MIT License - See LICENSE file

## Author

George Sultani
