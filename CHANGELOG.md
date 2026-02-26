# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.4.1] - 2026-02-24

### Fixed

#### Model Token Limits & Truncation Guard
- **`ChatProviders.ps1`** — Added `claude-sonnet-4-6` and `claude-opus-4-6` to `$global:ModelContextLimits`; updated default Anthropic model to `claude-sonnet-4-6`; `Get-ChatModels` display updated for current model lineup
- **`AppBuilder.ps1`** — Corrected `Get-BuildMaxTokens` output limits: `claude-sonnet-4-6` from 8192 → 64000, added `claude-opus-4-6` at 128000, added `claude-haiku-4-5-20251001`
- **`AppBuilder.ps1`** — `Invoke-CodeGeneration` now fails early on truncated responses (`max_tokens` stop reason) instead of passing incomplete code to the validator
- **`AppBuilder.ps1`** — Fixed truncation guard returning `ErrorMessage` key instead of `Output` — callers read `$codeResult.Output`, so the error was silently lost as `$null`
- **`AppBuilder.ps1`** — Removed redundant `$logsDir` creation; reuse `$logDir` and `$logFile` already created above
- **`ChatProviders.ps1`** — `Import-ChatConfig` now applies provider-level overrides (`defaultModel`, `endpoint`) from `ChatConfig.json` so config is single source of truth

#### AgentHeartbeat Hardening
- **Schedule logic** — `ConvertTo-NormalizedDayName` handles both full ("Monday") and abbreviated ("Mon") day names; `ConvertTo-TimeSpanFromInterval` adds `d` (days) unit alongside `h/m/s`
- **Input validation** — `Add-AgentTask` validates `-Time` as `HH:mm`, requires `-Interval` for interval schedule with syntax check (`digits + d/h/m/s`), validates `-Days` against known day names
- **Atomic save** — `Save-AgentTaskList` writes to `.tmp` then `Move-Item` to prevent task list corruption on mid-write process kill
- **Execution efficiency** — `Invoke-AgentHeartbeat` pre-scans for due tasks (skips log/DB/save overhead when nothing fires), moves `Get-Command` check outside loop, lazy-inits SQLite table via `Initialize-HeartbeatTable` with session-scoped flag
- **Bootstrap** — `Register-AgentHeartbeat` fixes module load order (`ChatProviders.ps1` before `IntentAliasSystem.ps1`), adds `SecretScanner.ps1` and `CodeArtifacts.ps1`, escapes single quotes in paths, ensures error log directory exists, adds `ExecutionTimeLimit` (10-minute cap)
- **Log rotation** — Trims `heartbeat.log` to 70% of limit when exceeding `HeartbeatMaxLogLines`

#### Secret Scanner — False Positive Fix & Prompt Rules
- **`SecretScanner.ps1`** — Added `(?<![A-Za-z])` negative lookbehind to `Generic Secret Assign` pattern; prevents matching when keyword (`password`, `secret`, `token`, `api_key`) is embedded in a larger variable name like `$tbApiKey` or `$lblApiKey`, while still catching standalone assignments
- **`SecretScanner.ps1`** — Added `-ExcludePatterns` parameter to `Invoke-SecretScan` for callers to opt out of specific pattern names
- **`AppBuilder.ps1`** — All three code generation prompts (PowerShell rule 12, Python-Tk rule 11, Python-Web rule 9) now explicitly forbid hardcoded/placeholder API keys and require a runtime settings UI with masked input fields and JSON config persistence
- **`AppBuilder.ps1`** — Reverted blanket `-ExcludePatterns @('Generic Secret Assign')` exclusion in `Test-GeneratedCode` since the lookbehind regex precisely targets the false positives

### Added

#### Tests
- **`Tests/AgentHeartbeat.Tests.ps1`** — Input validation (bad time, missing interval, invalid syntax, `d` unit, invalid/full day names), atomic save (no `.tmp` residue, valid JSON), day name normalization, interval parsing, mocked heartbeat execution
- **`Tests/AppBuilder.Tests.ps1`** — Truncation guard tests (mock `max_tokens` and `length` stop reasons), updated secret scanning tests for lookbehind behavior (UI element variables pass, standalone assignments caught)
- **`Tests/SecretScanner.Tests.ps1`** — Embedded keyword test (verifies lookbehind skips `$lblApiKey`, `$tbPassword`)
- **368 total tests passing, 0 failures** (up from 338)
## [1.5.0] - 2026-02-22

### Added

#### AI Build Pipeline v2 — `AppBuilder.ps1`

Full redesign of the App Builder generation pipeline with five new subsystems and a fifth build framework.

##### Build Memory System
- **`build_memory` SQLite table** — stores learned constraints from failed builds, keyed by framework
- **`Initialize-BuildMemoryTable`** — lazy-creates the table alongside `builds`
- **`Save-BuildConstraint`** — upserts a constraint with hit-count increment on duplicate; called automatically on final fix-loop failure
- **`Get-BuildConstraints`** — retrieves top constraints by hit count for a given framework
- **Constraint injection** — `Invoke-CodeGeneration` prepends learned constraints to every generation system prompt so the LLM avoids known failure patterns

##### Fix Loop (`Invoke-BuildFixLoop`)
- Retries code generation up to **2 times** on validation or review failure, feeding the full error list back to the LLM as context
- On final failure, calls `ConvertTo-BuildConstraint` to categorize the error and saves it to build memory for future builds
- Wired into `New-AppBuild` — replaces the previous instant-fail path after validation

##### Error Categorizer (`ConvertTo-BuildConstraint`)
- Converts raw error text into actionable constraint strings by framework:
  - **PowerShell**: variable scope colons, PS7+ null-coalescing operators
  - **Tauri**: unresolved imports/crates, borrow checker / moved value errors
  - **Python**: missing module / `No module named` errors
  - **Generic fallback**: `Avoid <error summary>` for uncategorized errors

##### Planning Agent (`Invoke-BuildPlanning`)
- Triggers on specs **> 150 words** — skips silently for short prompts
- Decomposes the spec into components, functions, data model, and edge cases via a focused LLM call
- Output prepended to the generation spec before `Invoke-CodeGeneration`
- Wired into `New-AppBuild` between prompt refinement and code generation

##### Review Agent (`Invoke-BuildReview`)
- Post-validation LLM review comparing generated code against the original spec
- Returns `PASS` or `FAIL` with a structured issues list
- On `FAIL`, triggers one additional fix-loop retry before accepting the output
- Wired into `New-AppBuild` after validation and before branding

##### PowerShell Module Framework (`powershell-module`)
- **Framework routing** — `Get-BuildFramework` detects keywords: `module`, `cmdlet`, `ps module`, `automation module`, `profile module`
- **Generation prompt** (`BuilderPowerShellModulePrompt`) — enforces verb-noun naming, `[CmdletBinding()]`, pipeline support, `.psd1` manifest with `ModuleVersion`/`FunctionsToExport`/`PowerShellVersion`, and security rules
- **Code parser** — `Invoke-CodeGeneration` extracts `.psm1` and `.psd1` fenced code blocks; primary file detection updated for module framework
- **Validators** in `Test-GeneratedCode`:
  - Unapproved verb detection (checked against `Get-Verb` approved list)
  - Manifest completeness — flags missing `ModuleVersion` or `FunctionsToExport`
  - Module must contain at least one exported function
  - Security: blocks `New-Object -ComObject`, remote WMI (`-ComputerName`), network listeners (`HttpListener`, `TcpListener`, `Socket`)
- **`Build-PowerShellModule`** — PascalCase output naming, attribution header injection, auto-generated `README.md`, zip packaging to `$OutputDir/<AppName>-module.zip`
- **Branding** — `Invoke-BildsyPSBranding` injects `# Generated by BildsyPS` header into `.psm1`; dedup-safe
- **Repair** — `Repair-GeneratedCode` now processes `.psm1` files alongside `.ps1`
- **Build routing** — `New-AppBuild` and `Update-AppBuild` both route `powershell-module` to `Build-PowerShellModule`
- **Framework detection** in `Update-AppBuild` — checks for `.psm1` files first before other framework heuristics
- **Tab completer** — `New-AppBuild -Framework <tab>` now includes `powershell-module`

##### Tauri Validators (Audit Remediation)
- **HTML structure checks** (`.html` files, Tauri framework only): requires `<!DOCTYPE html>`, `<head>`, `<body>`; blocks external CDN `<script src>` and `<link href>` references
- **JS security checks** (`.js` files, Tauri framework only): flags `eval()`, `innerHTML =`, `document.write`, `new Function()`, `setTimeout`/`setInterval` with string arguments
- Non-Tauri frameworks are not affected by these checks

##### Accent Color Fix
- Dark theme accent corrected from `#7c3aed` (purple) → `#4A90E2` (Bildsy blue) across all 5 keys in `$script:ThemePresets` (powershell, python-tk, python-web, tauri, refine)

#### Test Suite — 133 tests, 0 failures
- Added `Describe 'AppBuilder — Pipeline v2'` with **39 new tests** covering:
  - PS Module framework routing (7 cases)
  - Tauri HTML validators (7 cases)
  - Tauri JS security validators (6 cases)
  - PS Module validators — verbs, manifest, completeness, security (9 cases)
  - PS Module branding — inject, dedup, NoBranding (3 cases)
  - Build memory CRUD — table init, save, increment, retrieve, empty (5 cases)
  - Error categorizer — per-framework pattern matching (6 cases)
  - Planning agent threshold — skip vs trigger (2 cases)
  - Code repair `.psm1` support (1 case)
- Total test count: **133 offline + 11 NotRun (Live/integration)**

### Changed
- `BildsyPSVersion` bumped to `1.5.0`
- `New-AppBuild` pipeline: validation failure now enters fix loop instead of returning immediately
- `Update-AppBuild` rebuild routing: added `powershell-module` → `Build-PowerShellModule`
- `Update-AppBuild` modify prompt: Tauri context injected when framework is `tauri`
- `Update-AppBuild` capability detection: clipboard, notifications, fs, shell, dialog, and 5 other Tauri capability keywords trigger full regeneration

---

## [1.4.0] - 2026-02-20

### Added

#### Hierarchical Agent Orchestration — `spawn_agent` tool

- **`spawn_agent` tool** registered in `AgentTools.ps1` — allows the LLM to dynamically spawn sub-agents for focused sub-tasks
  - **Single task mode**: `{"tool":"spawn_agent","task":"do something specific"}`
  - **Parallel mode**: `{"tool":"spawn_agent","tasks":"[{\"task\":\"research X\"},{\"task\":\"research Y\"}]","parallel":"true"}` via `Start-ThreadJob`
  - Optional `max_steps` (default 10) and `memory` (JSON seed) per sub-task
- **Depth tracking** (`$global:AgentDepth`, `$global:AgentMaxDepth = 2`) prevents runaway recursion
  - Depth guard returns `DepthLimit` abort before incrementing when at max depth
  - Depth counter decremented in `finally` block (semaphore pattern) — safe even on exceptions
- **Memory isolation strategy**:
  - Depth 0→1: sub-agents **share** parent's `$global:AgentMemory` via `-ParentMemory` reference
  - Depth 1→2: sub-agents get **isolated** memory copy; results returned via namespaced key (`subagent:<task_hash>`)
  - Parallel jobs: fully isolated memory per thread job, merged on completion — no race conditions
- **`-Silent` switch** on `Invoke-AgentTask` — suppresses all `Write-Host` output for sub-agent use; ASK prompts auto-resolve as STUCK
- **`-ParentMemory` parameter** on `Invoke-AgentTask` — passes shared memory reference for depth 0→1 sub-agents
- **System prompt** updated with `spawn_agent` usage documentation (RULES section)
- **`Tests/SpawnAgent.Tests.ps1`** — 24 new tests covering: tool registration, depth guard, memory isolation, input validation, Silent mode, finally-block safety; **338 total tests passing**

## [1.3.1] - 2026-02-20

### Added

#### Tab Completion — 22 new dynamic argument completers across 10 modules

| Command | Parameter | Source |
|---------|-----------|--------|
| `Set-DefaultChatProvider`, `Get-ChatModels`, `Test-ChatProvider` | `-Provider` | `$global:ChatProviders.Keys` |
| `Start-ChatSession`, `chat` | `-Provider` | `$global:ChatProviders.Keys` |
| `Resume-Chat`, `Remove-ChatSession`, `Export-ChatSession` | `-Name` | SQLite sessions → JSON index fallback |
| `Invoke-UserSkill`, `Remove-UserSkill` | `-Name` | `$global:LoadedUserSkills.Keys` |
| `Invoke-Workflow` | `-Name` | `$global:Workflows.Keys` (tooltip = description) |
| `Connect-MCPServer` | `-Name` | `$global:MCPServers.Keys` (registered servers) |
| `Disconnect-MCPServer`, `Get-MCPTools`, `Invoke-MCPTool` | `-Name` / `-ServerName` | `$global:MCPConnections.Keys` (connected servers) |
| `Remove-AppBuild`, `Update-AppBuild` | `-Name` | Subdirectories of `$global:AppBuilderPath` |
| `New-AppBuild` | `-Framework` | Static: `powershell`, `python-tk`, `python-web` |
| `Remove-AgentTask`, `Enable-AgentTask`, `Disable-AgentTask` | `-Id` | `Get-AgentTaskList` (tooltip = task description) |
| `Remove-PersistentAlias` | `-Name` | Parsed `Set-Alias` lines from `$global:UserAliasesPath` |
| `Remove-Artifact` | `-Name` | Files in `$global:ArtifactsPath` |
| `gco`, `gmerge`, `grb` | `-Branch` | `git branch --list` |

- **`Tests/TabCompletion.Tests.ps1`** — 37 new tests covering all completers; **313 total tests, 0 failures**

### Fixed
- **`gm` → `gmerge`** (`NavigationUtils.ps1`) — `gm` conflicted with PowerShell's built-in `gm` alias for `Get-Member`, silently preventing the tab completer from firing. Renamed to `gmerge`.

---

## [1.3.0] - 2026-02-20

### Added

#### App Builder — Prompt to .exe (`AppBuilder.ps1`, ~1259 lines)
- **3 build lanes**: PowerShell/WinForms via `ps2exe` (default, zero Python deps), Python-TK via PyInstaller, Python-Web (PyWebView) via PyInstaller
- **2-stage LLM pipeline**: prompt refinement → code generation, both via `Invoke-ChatCompletion`
- **Token budget auto-detect**: reads model context window via `Get-ModelContextLimit`, applies per-lane caps (PS/TK: 16K, Web: 64K) and floors (4K/8K); user override via `-tokens` flag
- **Branding injection**: every generated app includes "Built with BildsyPS"; `Invoke-BildsyPSBranding` patches deterministically if LLM omits it; `-nobranding` flag reserved for future paid tier
- **Code validation**: PowerShell AST syntax check / Python `ast.parse`, dangerous pattern scan (`os.system`, `subprocess`, `Remove-Item -Recurse`, `Start-Process -Verb RunAs`), secret leak scan via `Invoke-SecretScan`
- **Diff-based rebuild**: `Update-AppBuild` applies FIND/REPLACE edits to existing source; falls back to full regeneration on "rewrite"/"redesign" triggers
- **SQLite build tracking**: `builds` table in `bildsyps.db`, lazy-created via `Initialize-BuildsTable`
- **Chat commands**: `build "prompt"`, `builds`, `rebuild <name> "changes"`
- **Agent tool**: `build_app` registered as 17th tool in `AgentTools.ps1`
- **Intent**: `build_app` in `IntentRegistry.ps1` + `IntentActionsSystem.ps1`

#### Vision Model Support (`VisionTools.ps1`, ~350 lines)
- `Capture-Screenshot` — .NET `System.Drawing` screen capture, optional `-Region`, `-FullResolution`
- `Get-ClipboardImage` — grab image from clipboard
- `ConvertTo-ImageBase64` — file to base64 with media type detection (png/jpg/gif/webp/bmp), 20MB limit
- `Resize-ImageBitmap` — auto-resize to 2048px longest edge (configurable via `$global:VisionMaxEdge`)
- `New-VisionMessage` — builds multimodal content arrays for Anthropic and OpenAI formats
- `Send-ImageToAI` — unified entry point: encode image → build message → call `Invoke-ChatCompletion`
- `Test-VisionSupport` — checks model against `$global:VisionModels` list
- `Invoke-Vision` — convenience wrapper (alias: `vision`)
- Chat commands: `vision`, `vision <path>`, `vision --full`, `vision <prompt>`
- Vision-capable models: `claude-3-5-sonnet`, `gpt-4o`, `gpt-4o-mini`, `llava`, `llama3.2-vision`, `moondream`, `bakllava`
- Agent tool: `screenshot` registered as 13th tool

#### OCR Integration (`OCRTools.ps1`)
- Tesseract OCR for image text extraction (`winget install UB-Mannheim.TesseractOCR`)
- `pdftotext` for PDF text extraction (Xpdf tools)
- Vision API fallback when Tesseract is unavailable
- Agent tool: `ocr` registered as 14th tool
- Intent: `ocr_file` in `IntentRegistry.ps1`

#### SQLite + FTS5 Conversation Persistence (`ChatStorage.ps1`)
- Full SQLite backend replacing JSON file storage
- Schema: `sessions(id, name, created, updated, provider, model)`, `messages(session_id, role, content, timestamp)`
- FTS5 full-text search across all conversation history
- `Get-ChatSessionsFromDb`, `Save-ChatToDb`, `Search-ChatDb`
- `$global:ChatDbPath` defaults to `bildsyps.db` at module load (prevents init crash when `ChatSession.ps1` loads after `ChatStorage.ps1`)

#### Secret Scanner (`SecretScanner.ps1`)
- Detects API keys, tokens, and credentials in files and staged git commits
- Runs at profile load; warns on findings without blocking startup
- Patterns: AWS keys, GitHub tokens, Anthropic/OpenAI keys, generic `Bearer` tokens, private keys
- `Invoke-SecretScan` callable by App Builder code validation pipeline

#### Agent Heartbeat (`AgentHeartbeat.ps1`)
- Cron-triggered background agent tasks via Windows Task Scheduler
- `Add-AgentTask`, `Remove-AgentTask`, `Enable-AgentTask`, `Disable-AgentTask`, `Get-AgentTaskList`
- Schedule types: `daily`, `weekly`, `interval`, `startup`, `logon`
- Chat commands: `heartbeat start`, `heartbeat stop`
- Agent tool: `search_history` registered as 15th tool (FTS5 search over past sessions)

#### E2E Test Suite — 276 tests, 0 failures
- 15 test files covering all major modules
- 11 application defects found and fixed during audit:
  1. `OrderedDictionary.ContainsKey()` → `.Contains()` — 10 sites in `PluginLoader.ps1` (7) and `UserSkills.ps1` (3)
  2. `Get-Content` char coercion — wrapped with `@()` in `SecretScanner.ps1`, `ConfigLoader.ps1`, `PersistentAliases.ps1`
  3. Version mismatch — profile had `1.2.0`, module declared `1.3.0`
  4. `SecretScanner` single finding returned as bare hashtable — fixed with `return @(,$findings)`
  5. `ResponseParser` null `ChatSessionHistory` crash on second `+=` — added null guard
  6. `ProfileTimings` null crash in `PluginLoader.ps1` — added init in bootstrap
  7. `ChatStorage` DB init crash — `$global:ChatLogsPath` null at load time — added default init
  8. `UserSkills` not shell-invocable — added `Set-Item function:$skillName` per skill; `Remove-Item` on unregister
  9. `UserSkills.json` not auto-created on first run — `Import-UserSkills` now copies example file
  10. `Get-AppBuilds` returns `$null` — added `return $builds`; fixed `$($b.BuildTime)` interpolation
  11. `AppBuilder` missing dangerous code patterns — added `os.system`, `subprocess`, `Remove-Item -Recurse`, `Start-Process -Verb RunAs` to `Test-GeneratedCode`

#### UserSkills v2
- `Invoke-UserSkill` — public function to execute skills by name with `{param}` substitution; returns `@{ Success; Output; Error }`
- Trigger phrase registration — `Import-UserSkills` registers `triggers` array into `$global:IntentAliases`; cleanup in `Unregister-UserSkills` and `Remove-UserSkill`
- Shell-invocable functions — each loaded skill creates a global PowerShell function via `Set-Item -Path "function:$skillName"`
- `UserSkills.json` auto-created from `UserSkills.example.json` on first run

### Changed
- `BildsyPSVersion` bumped to `1.3.0` in profile
- `IntentAliasSystem.ps1` load order: added `AgentTools.ps1` before `AgentLoop.ps1`
- Agent tools count: 12 → 17 (screenshot, ocr, build_app, search_history added)
- Intent count: 77+ → 80+ (Vision and Productivity categories added)

---

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

## [1.1.9] - 2026-02-19

### Added

#### Agent Architecture v1 — ReAct Loop (`AgentLoop.ps1`, ~310 lines)
- `Invoke-AgentTask` — ReAct (Reason + Act) loop: LLM↔intent cycle until DONE/STUCK/step limit
- `Get-AgentSystemPrompt` — builds agent prompt from all 76 intents in `$global:IntentMetadata`
- `Format-AgentObservation` — token-aware result compression (truncates at 2000 chars)
- `Stop-AgentTask` — sets `$global:AgentAbort` flag for Ctrl+C abort
- Protocol: `THOUGHT` / `ACTION {"intent":"..."}` / `DONE` / `STUCK`
- Config: `$global:AgentMaxSteps = 10`, `$global:AgentMaxTokenBudget = 8000`
- Aliases: `agent`, `agent-stop`
- Chat command: `agent <task>` inside REPL
- Intent: `agent_task` registered in `IntentRegistry.ps1` + `IntentActionsSystem.ps1`

### Fixed

#### Deduplication & Safety Fixes
- **`AIExecution.ps1` deleted** — was a complete duplicate of `SafetySystem.ps1` (9 functions, 8 globals). `SafetySystem.ps1` version used `Start-ThreadJob` with 30-second timeout vs bare `Invoke-Expression`. Removed load line from profile.
- **`SystemCleanup.ps1`** — bare commands (`ipconfig /flushdns`, `Stop-Process -Name explorer -Force`, `Start-Process explorer.exe`) executed on every dot-source including `reload-all`. Wrapped all commands in `Invoke-SystemCleanup` with confirmation prompt and `-Force` bypass. Added `cleanup` alias.
- **`SystemUtilities.ps1`** — removed duplicate `ll`, `la`, `lsd`, `lsf` (canonical versions in `NavigationUtils.ps1`)
- **`TerminalTools.ps1`** — removed duplicate `Invoke-FzfHistory`, `Invoke-FzfFile`, `Invoke-FzfDirectory`, `Invoke-FzfEdit`, `Ctrl+R` binding, and `fh`/`ff`/`fd`/`fe` aliases (canonical in `FzfIntegration.ps1`; `Ctrl+R` was being registered twice)
- **`SafetySystem.ps1`** — removed `Get-SafeActions`, `Test-SafeAction`, `Invoke-SafeAction` which duplicated `CommandValidation.ps1`

---

## [1.1.8] - 2026-02-19

### Added

#### `IntentAliasSystem.ps1` Modularization
Split the 2790-line monolith into 6 focused files — zero breaking changes:

| File | Lines | Contents |
|------|-------|----------|
| `IntentRegistry.ps1` | ~490 | 75 intent definitions, `$global:CategoryDefinitions`, `$global:IntentCategories` |
| `IntentActions.ps1` | ~760 | Core intent scriptblocks: documents, files, web, browser, code artifacts, clipboard, git, MCP, calendar |
| `IntentActionsSystem.ps1` | ~700 | System/filesystem/composite/workflow scriptblocks: apps, services, processes, scheduled tasks |
| `WorkflowEngine.ps1` | ~130 | `$global:Workflows`, `Invoke-Workflow`, `Get-Workflows`, `workflow`/`workflows` aliases |
| `IntentRouter.ps1` | ~470 | `Invoke-IntentAction`, `Test-Intent`, `Show-IntentHelp`, `Get-IntentInfo`, tab completion, `intent`/`intent-help` aliases |
| `IntentAliasSystem.ps1` | 17 | Thin orchestrator — dot-sources the 5 files above |

- `$global:IntentAliases` changed from `@{}` to `[ordered]@{}` — deterministic intent ordering in agent prompts and `intent-help`
- Load order: `IntentRegistry` → `IntentActions` → `IntentActionsSystem` → `WorkflowEngine` → `IntentRouter` → `AgentTools` → `AgentLoop`

---

## [1.1.7] - 2026-02-19

### Added

#### Code Artifacts (`CodeArtifacts.ps1`, ~610 lines)
- Auto-detects and tracks AI-generated code blocks in `$global:SessionArtifacts` after every AI response
- Chat commands: `code` (list blocks), `save <#>`, `save <#> filename`, `run <#>`, `save-all`, `artifacts`
- AI intents: `save_code`, `run_code`, `list_artifacts`
- Execution support: PowerShell, Python, JavaScript, TypeScript, Bash, Ruby, Go, Rust, C#, HTML, Batch
- Save-only support: SQL, CSS, JSON, YAML, XML, Markdown, CSV, TOML, Dockerfile, C, C++, Java
- All `run_code` executions require user confirmation; `RequiresConfirmation` safety tier
- Temp files cleaned up after execution

#### Browser Awareness (`BrowserAwareness.ps1`, ~350 lines)
- Three-strategy URL detection: UI Automation (address bar COM), window title parsing, browser history SQLite
- Supports Chrome, Edge, Firefox, Brave (auto-detected by process name)
- Intents: `browser_tab` (URL + title + browser + method), `browser_content` (URL + fetched page text)
- Aliases: `browser-url`, `browser-page`, `browser-tabs`

---

## [1.1.6] - 2026-02-19

### Added

#### Custom User Skills (`UserSkills.ps1`, ~430 lines)
- Users define custom intents via `UserSkills.json` — no PowerShell required
- Step types: `{"command": "git checkout {branch}"}` (raw PowerShell) and `{"intent": "git_status"}` (existing intents)
- `{paramName}` substitution with per-parameter defaults
- `"confirm": true` maps to `RequiresConfirmation` safety tier
- Conflict detection — skills cannot overwrite core or plugin intents
- AI integration — `Get-UserSkillsPrompt` injects skill list into LLM system prompt
- `Get-IntentInfo` shows `Source: user-skill` for JSON-defined intents

| Function | Alias | Description |
|----------|-------|-------------|
| `Get-UserSkills` | `skills` | List loaded user skills |
| `New-UserSkill` | `new-skill` | Interactive skill creator |
| `Remove-UserSkill` | — | Delete skill from JSON + unregister |
| `Import-UserSkills` | — | Load skills from JSON |
| `Update-UserSkills` | `reload-skills` | Unregister + re-import |

- `UserSkills.example.json` — documented template with 4 example skills (deploy, morning report, backup, project init)

#### Plugin Architecture v2 (`PluginLoader.ps1`, ~500 → ~1035 lines)
Expanded with 7 new subsystems — zero breaking changes to existing plugins:

| Subsystem | Description |
|-----------|-------------|
| Dependency resolution | `Resolve-PluginLoadOrder` — topological sort; circular dep detection; `core:` prefix |
| Version compatibility | `$PluginInfo.MinBildsyPSVersion` / `MaxBildsyPSVersion` — skips out-of-range plugins with warning |
| Per-plugin config | `$PluginConfig` defaults + `Plugins/Config/<name>.json` user overrides; `Get/Set/Reset-PluginConfig` |
| Helper function registry | `$PluginFunctions` → `$global:PluginHelpers[name]` — scriptblocks shared across plugins |
| Lifecycle hooks | `$PluginHooks.OnLoad` / `OnUnload` — run after merge / before removal; errors caught and logged |
| Self-test framework | `$PluginTests` + `Test-BildsyPSPlugin` — `test-plugin -Name` or `-All`; pass/fail report |
| Hot-reload file watcher | `Watch-BildsyPSPlugins` / `Stop-WatchBildsyPSPlugins` — `FileSystemWatcher` on `Plugins/`; debounced |

- New aliases: `test-plugin`, `watch-plugins`, `plugin-config`
- New example plugins: `_Pomodoro.ps1` (Pomodoro timer with config, hooks, tests, toast), `_QuickNotes.ps1` (JSON note-taking with CRUD, search, tests)
- Full plugin variable set: `$PluginIntents`, `$PluginMetadata`, `$PluginCategories`, `$PluginWorkflows`, `$PluginInfo`, `$PluginConfig`, `$PluginFunctions`, `$PluginHooks`, `$PluginTests`

---

## [1.1.5] - 2026-02-18

### Added

#### Plugin Architecture v1 (`PluginLoader.ps1`, ~500 lines)
- Drop-in loading — place a `.ps1` in `Plugins/`, run `reload-plugins`
- `Enable-BildsyPSPlugin` / `Disable-BildsyPSPlugin` — toggle via `_` prefix rename
- `Unregister-BildsyPSPlugin` — cleanly removes all contributions from registries
- `new-plugin 'Name'` — scaffolds a ready-to-edit plugin file from template
- Conflict protection — duplicate intent/workflow names warned and skipped; core never overwritten
- Plugin intents dynamically injected into LLM system prompt
- `Get-IntentInfo` shows `Source: plugin: <name>` for plugin intents
- Per-plugin load time tracked in `$global:ProfileTimings`
- Tab completion on all plugin management functions
- `Plugins/_Example.ps1` — reference template demonstrating all plugin conventions

Plugin variable contract:

| Variable | Required | Merges Into |
|----------|----------|-------------|
| `$PluginIntents` | Yes | `$global:IntentAliases` |
| `$PluginMetadata` | Recommended | `$global:IntentMetadata` |
| `$PluginCategories` | Optional | `$global:CategoryDefinitions` |
| `$PluginWorkflows` | Optional | `$global:Workflows` |
| `$PluginInfo` | Optional | `$global:LoadedPlugins` |

#### Toast Notifications (`ToastNotifications.ps1`)
- Provider auto-detection: BurntToast (if installed) → Windows Runtime API → silent no-op
- `Send-BildsyPSToast` — `Title`, `Message`, `Type` (Success/Error/Warning/Info); emoji per type
- `Send-SuccessToast`, `Send-ErrorToast`, `Send-InfoToast` — convenience wrappers
- `Install-BurntToast` — installs module, sets provider, sends confirmation toast
- Hook points: after `Invoke-IntentAction` (document/git/workflow/filesystem intents), after `Invoke-Workflow`, after `Save-Chat`
- All hooks guard with `Get-Command Send-BildsyPSToast -ErrorAction SilentlyContinue`

---

## [1.1.4] - 2026-02-18

### Added

#### Folder Awareness (`FolderContext.ps1`)
- `Get-FolderContext` — compact, token-budget-aware directory snapshot (default 800-token cap):
  - Current path, git repo detection, branch, modified files (`git status --short`)
  - Directories with child counts; files grouped by extension with sizes
  - Notable files called out explicitly (README, Dockerfile, package.json, etc.)
  - Optional file content previews for small config/doc files
- `Invoke-FolderContextUpdate` — injects context into active chat session; re-injecting replaces previous snapshot (uses `[FOLDER_CONTEXT]` sentinel with `.StartsWith()` detection)
- `Enable-FolderAwareness` / `Disable-FolderAwareness` — wraps `Set-Location` to auto-refresh on `cd` when a session is active
- Chat commands: `folder`, `folder <path>`, `folder --preview`
- `chat -FolderAware` / `chat -f` flag

#### Token Budget Management
- `$global:ModelContextLimits` — per-model context window table (Claude: 200K, GPT-4o: 128K, Llama: 8K, etc.)
- `Get-ModelContextLimit` — fuzzy matching + safe fallback
- `Get-TrimmedMessages` upgraded: takes `ContextLimit` and `MaxResponseTokens` separately; `-Summarize` flag compresses evicted messages into a recap (`[Earlier in this conversation (N messages trimmed), you discussed: ...]`)
- `$MaxTokens` renamed to `$MaxResponseTokens` — correctly controls only API response length
- `budget` command — detailed breakdown: context window, response reserve, input budget, current usage %, message count, per-role breakdown
- Auto-trim at 80% with `-AutoTrim` flag

### Fixed
- `MaxTokens` conflated context window with response length — renamed and separated
- `Get-TrimmedMessages` silently dropped evicted messages — now summarizes them
- Nested `Add-Line` function used `$script:` scope — replaced with `$tryAdd` scriptblock closing over enclosing `List[string]`
- Sentinel `-like '[FOLDER_CONTEXT]*'` never matched — PowerShell `-like` treats `[` as wildcard class; fixed with `.StartsWith()`
- Re-injecting folder context accumulated duplicate snapshots — now removes both sentinel message and assistant ack

---

## [1.1.3] - 2026-02-18

### Added

#### Conversation Persistence (`ChatSession.ps1`)
- **Auto-save** on session exit and `clear` — no more lost conversations
- **Named sessions** with auto-generated slugs from first user message
- **`index.json`** session index for fast lookup without scanning files
- Chat commands: `save`, `save <name>`, `resume`, `resume <name>`, `sessions`, `rename <name>`, `delete <name>`, `export`, `export <name>`, `search <keyword>`
- `chat -Resume` / `-r` — auto-loads last session on startup
- `chat -Continue` / `-c` — loads last session + injects `Get-SessionSummary` preamble so model recalls context
- `Get-SessionSummary` — fast local heuristic (no LLM call) compressing session into bullet points
- Two-pass search: index previews first, then deep file content scan
- `Export-ChatSession` — exports session to formatted `.md` file
- 30-day auto-prune on save
- Backward-compatible `Import-Chat` handles both old array format and new envelope format

---

## [1.1.2] - 2026-02-18

### Added

#### Task Scheduler Integration
- `schedule_workflow` intent — schedules any defined workflow via Windows Task Scheduler
- Supported schedule types: `daily`, `weekly`, `interval`, `startup`, `logon`
- Interval formats: `1h`, `30m`, `15s` (human-friendly, parsed explicitly)
- Self-contained bootstrap scripts generated per workflow in `ScheduledScripts/` — dot-sources required modules using absolute paths; runs `pwsh -File` (no `EncodedCommand`, no profile dependency)
- Task Scheduler location: `\BildsyPS\Workflow_<workflow>`
- Error log: `$env:TEMP\bildsyps_task_errors.log`
- `list_scheduled_workflows` and `remove_scheduled_workflow` intents
- Dynamic bootstrap loader in `IntentAliasSystem.ps1`

### Fixed
- **`-Force` not bypassing `Read-Host` in `Invoke-IntentAction`** — safety block checked `-Force` but execution fell through to a second `Read-Host` at line ~2056 with no `-Force` guard. Both gates now check `-not $AutoConfirm -and -not $Force`. This would have caused any automated caller (scheduled tasks, scripts, tests) to hang.

#### Rename: PSAigent → BildsyPS
- `README.md` — `# PSAigent` → `# BildsyPS`; updated tagline, topics, git clone URLs, chat commands
- `CONTRIBUTING.md` — updated project name
- `IntentAliasSystem.ps1` — startup message updated to `"BildsyPS loaded."`
- `chat-ollama`, `chat-anthropic`, `chat-local`, `chat-llm` renamed to proper `Verb-Noun` form; original short names preserved as `Set-Alias` entries

---

## [1.1.1] - 2026-02-18

### Added

#### Repo Housekeeping
- `.gitignore` additions: `*.backup`, `*.old`, `.claude/`, `Modules/Microsoft.PowerShell.ThreadJob/`
- Untracked from git: `Microsoft.PowerShell_profile.ps1.backup`, `.ps1.old`, `.claude/worktrees/`, `Modules/Microsoft.PowerShell.ThreadJob/`

#### Documentation
- `VISION.md` created — product direction, five-layer roadmap, design principles, competitive positioning
- `README.md` overhauled — product-first opening pitch, full feature bullets, intent table, quick start, file structure, roadmap table (✅/🔜), link to VISION.md

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
