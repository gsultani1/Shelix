# PowerShell AI Assistant Profile

A modular PowerShell profile with an integrated AI chat assistant that can execute commands, search the web, manage files, and interact with your system.

## Features

### 🤖 AI Chat Assistant
- **Multi-provider support**: Ollama (local), Anthropic (Claude), OpenAI, LM Studio
- **Command execution**: AI can run safe PowerShell commands on your behalf
- **Intent system**: Natural language actions like "create a doc called Report"
- **Streaming responses**: Real-time output from AI providers

### 🔧 Available Intents

| Category | Intents |
|----------|---------|
| **Documents** | `create_docx`, `create_xlsx` - Create and open Office documents |
| **Clipboard** | `clipboard_read`, `clipboard_write`, `clipboard_format_json`, `clipboard_case` |
| **Files** | `read_file`, `file_stats` - Analyze file contents |
| **Git** | `git_status`, `git_log`, `git_commit`, `git_push`, `git_pull`, `git_diff` |
| **Calendar** | `calendar_today`, `calendar_week`, `calendar_create` (Outlook) |
| **Web** | `web_search`, `wikipedia`, `fetch_url`, `search_web` |
| **Apps** | `open_word`, `open_excel`, `open_notepad`, `open_calculator` |

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
├── Microsoft.PowerShell_profile.ps1  # Main profile
├── ChatProviders.ps1                 # AI provider implementations
├── IntentAliasSystem.ps1             # Intent routing system
├── ChatConfig.json                   # API keys and settings
├── ToolPreferences.json              # Tool preferences
├── NaturalLanguageMappings.json      # Command mappings
├── Modules/
│   ├── SafetySystem.ps1              # Command validation
│   ├── TerminalTools.ps1             # External tool integration
│   ├── NavigationUtils.ps1           # Navigation helpers
│   ├── PackageManager.ps1            # Tool installation
│   ├── WebTools.ps1                  # Web search APIs
│   └── ProductivityTools.ps1         # Clipboard, Git, Calendar
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

- PowerShell 5.1 or later
- Windows 10/11
- Optional: Ollama for local AI
- Optional: Anthropic/OpenAI API keys for cloud AI

## Installation

1. Clone or copy files to `~\Documents\WindowsPowerShell\`
2. Edit `ChatConfig.json` with your API keys
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

## License

MIT License - See LICENSE file

## Author

Created with ❤️ and AI assistance
