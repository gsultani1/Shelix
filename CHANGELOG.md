# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.0] - 2026-02-20

### Added

#### Autonomous Agent Architecture
- **`AgentLoop.ps1`** — Full ReAct (Reason + Act) agent engine
  - Unified tool + intent dispatch: `{"tool":"calculator","expression":"2+2"}` or `{"intent":"create_docx","name":"report"}`
  - Working memory (`$global:AgentMemory`) — `store`/`recall` values across steps
  - ASK/ANSWER protocol — agent pauses mid-task to ask the user a question
  - PLAN display — agent announces numbered plan before executing
  - Interactive mode (`-Interactive`) — follow-up tasks with shared context and memory
  - `Show-AgentSteps`, `Show-AgentMemory`, `Show-AgentPlan` inspection functions
  - Increased defaults: 15 max steps, 12K token budget
  - Aliases: `agent`, `agent-stop`, `agent-steps`, `agent-memory`, `agent-plan`

- **`AgentTools.ps1`** — Lightweight tool registry for the agent
  - `Register-AgentTool` — extensible registry (plugins can add tools)
  - `Invoke-AgentTool`, `Get-AgentTools`, `Get-AgentToolInfo`
  - 12 built-in tools:

  | Tool | Description |
  |------|-------------|
  | `calculator` | Sanitized math expression evaluator |
  | `datetime` | Current time, date math, timezone conversion |
  | `web_search` | Web search (wraps WebTools.ps1) |
  | `fetch_url` | Fetch and extract web page content |
  | `wikipedia` | Wikipedia article search |
  | `stock_quote` | Live stock price via Yahoo Finance (no API key) |
  | `json_parse` | Parse JSON, extract values by dot-path |
  | `regex_match` | Test regex patterns, return all matches |
  | `read_file` | Read local text files |
  | `shell` | Execute PowerShell (gated through safety system) |
  | `store` | Save named value to working memory |
  | `recall` | Retrieve named value from working memory |

#### Chat Slash Commands
- `/agent <task>` — Run agent task from within chat session
- `/agent` — Enter interactive agent mode
- `/tools` — List registered agent tools
- `/steps` — Show steps from last agent run
- `/memory` — Show agent working memory
- `/plan` — Show agent's last announced plan

#### Codebase Cleanup (previous session)
- Merged `AIExecution.ps1` into `SafetySystem.ps1` — eliminated 9 duplicate functions
- Removed duplicate `ll`, `la`, `lsd`, `lsf` from `SystemUtilities.ps1` (canonical in `NavigationUtils.ps1`)
- Removed duplicate fzf functions and duplicate `Ctrl+R` binding from `TerminalTools.ps1` (canonical in `FzfIntegration.ps1`)
- Wrapped all `SystemCleanup.ps1` commands in `Invoke-SystemCleanup` — nothing auto-runs on profile load

#### Plugin Architecture (previous session)
- **`PluginLoader.ps1`** — Comprehensive plugin system
  - Dependency resolution via topological sort (`Resolve-PluginLoadOrder`)
  - Per-plugin config: `$PluginConfig` defaults + `Plugins/Config/*.json` overrides
  - `Get-PluginConfig`, `Set-PluginConfig`, `Reset-PluginConfig`
  - Lifecycle hooks: `$PluginHooks` with `OnLoad`/`OnUnload` scriptblocks
  - Self-test framework: `$PluginTests` + `Test-BildsyPSPlugin`
  - Helper function sharing: `$PluginFunctions` → `$global:PluginHelpers`
  - Version compatibility: `MinBildsyPSVersion`/`MaxBildsyPSVersion` checks
  - Hot-reload file watcher: `Watch-BildsyPSPlugins` / `Stop-WatchBildsyPSPlugins`
  - Aliases: `test-plugin`, `watch-plugins`, `plugin-config`
- Example plugins: `_Example.ps1` (updated), `_Pomodoro.ps1`, `_QuickNotes.ps1`
- `$global:BildsyPSVersion` set to `'1.0.0'` in profile

### Changed
- `IntentAliasSystem.ps1` — Added `AgentTools.ps1` and `AgentLoop.ps1` to load order
- `ChatSession.ps1` — Added agent slash commands to REPL switch block
- `ProfileHelp.ps1` — Updated system prompt with agent tools and slash command info
- Intent count: 30+ → 77+ (expanded intent system)

---

## [1.1.0] - 2025-12-25

### Changed - Major Refactoring

#### Modular Architecture
- **Profile reduced from ~2000 lines to ~150 lines** - All functionality extracted to modules
- Moved `ChatProviders.ps1` and `IntentAliasSystem.ps1` to `Modules/` folder
- Created 9 new focused modules for better maintainability

#### New Modules Created
| Module | Purpose |
|--------|---------|
| `SystemUtilities.ps1` | `sudo`, `ports`, `procs`, `uptime`, `hwinfo`, PATH management |
| `ArchiveUtils.ps1` | `zip`, `unzip`, `Get-ArchiveContents` |
| `DockerTools.ps1` | `dps`, `dpsa`, `dlog`, `dexec`, `dstop`, `dclean` |
| `DevTools.ps1` | `open`, `code`, `cursor`, `windsurf`, `Test-DevTools` |
| `NaturalLanguage.ps1` | `Convert-NaturalLanguageToCommand`, token estimation |
| `AIExecution.ps1` | `Invoke-AIExec`, rate limiting, undo tracking, session info |
| `ResponseParser.ps1` | `Convert-JsonIntent`, `Format-Markdown` |
| `ProfileHelp.ps1` | `Show-ProfileTips`, `Get-ProfileTiming`, system prompt |
| `ChatSession.ps1` | `Start-ChatSession`, `chat`, `Save-Chat`, `Import-Chat` |

#### Fixed
- **AI no longer searches web on every message** - System prompt updated to only use intents for explicit action requests
- Consolidated duplicate code from profile and SafetySystem.ps1 into CommandValidation.ps1

#### Module Load Order (24 modules)
```
ConfigLoader → PlatformUtils → SecurityUtils → CommandValidation
→ SystemUtilities → ArchiveUtils → DockerTools → DevTools
→ NaturalLanguage → AIExecution → ResponseParser → DocumentTools
→ SafetySystem → TerminalTools → NavigationUtils → PackageManager
→ WebTools → ProductivityTools → MCPClient → FzfIntegration
→ PersistentAliases → ProfileHelp → ChatSession
→ IntentAliasSystem → ChatProviders
```

---

## [1.0.0] - 2025-12-25 MERRY CHRISTMAS

### Added

#### Core Features
- Multi-provider AI chat support (Ollama, Anthropic Claude, OpenAI, LM Studio, **llm CLI**)
- Streaming responses for real-time output
- Automatic token management and conversation trimming
- Provider switching mid-conversation
- Conversation history with save/load capability

#### Intent System
- JSON-based intent routing for natural language actions
- 11 intent categories with full metadata and parameter documentation
- Document creation (`create_docx`, `create_xlsx`)
- Application launching (`open_word`, `open_notepad`, `open_folder`, `open_terminal`)
- Clipboard operations (`clipboard_read`, `clipboard_write`, `clipboard_format_json`, `clipboard_case`)
- File analysis (`read_file`, `file_stats`, `list_files`)
- Git integration (`git_status`, `git_log`, `git_commit`, `git_push`, `git_pull`, `git_diff`)
- Outlook calendar (`calendar_today`, `calendar_week`, `calendar_create`)
- Web search (`web_search`, `wikipedia`, `fetch_url`)
- System automation (`service_restart`, `system_info`, `network_status`, `process_list`, `process_kill`)
- Scheduled tasks (`scheduled_tasks`, `scheduled_task_run`, `scheduled_task_enable`, `scheduled_task_disable`)
- Safety tiers for dangerous operations (RequiresConfirmation)

#### Command Execution
- Safe command execution with whitelist validation
- User confirmation for non-read-only commands
- Rate limiting to prevent runaway execution
- Comprehensive execution logging with audit trail

#### MCP Support
- Model Context Protocol client implementation
- Connect to external MCP servers via stdio transport
- Pre-configured common servers (filesystem, memory, fetch, brave-search, github)
- Custom server registration
- MCP intents for AI (`mcp_servers`, `mcp_connect`, `mcp_tools`, `mcp_call`)
- Dynamic system prompt with connected MCP tools

#### llm CLI Integration
- Wrapper for Simon Willison's llm CLI tool
- Access to 100+ plugins and models
- Helper commands: `llm-models`, `llm-install`

#### Multi-Step Workflows
- Chain multiple intents together for complex tasks
- Built-in workflows: `daily_standup`, `research_and_document`, `project_setup`
- Workflow intents: `run_workflow`, `list_workflows`
- Custom workflow registration with parameter mapping

#### Terminal Tools Integration
- bat (syntax-highlighted file viewing)
- glow (markdown rendering)
- broot (interactive file navigation)
- fzf (fuzzy finding)
- jq/yq (JSON/YAML processing)

#### Navigation Utilities
- Directory tree visualization
- Folder size analysis
- Quick directory jumping with `z`
- Parent directory shortcuts (`..`, `...`, `....`)

### Security
- Command whitelist with safety classifications
- API keys loaded from config file (not hardcoded)
- Execution logging for audit purposes
- Rate limiting on AI command execution

### Documentation
- README with installation and usage guide
- Example configuration files
- CONTRIBUTING.md with code style guidelines
- MIT License

### Cross-Platform
- PowerShell 5.1+ (Windows) and PowerShell 7+ (Windows/Mac/Linux) support
- Installation instructions for all platforms
