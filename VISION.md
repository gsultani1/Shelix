# BildsyPS Vision

> Your terminal, orchestrated. An AI shell environment with interconnected, spiraling capability.

---

## What BildsyPS Is Today

BildsyPS is an AI shell environment for PowerShell. It gives your terminal a brain — one that understands your context, executes commands on your behalf, remembers your conversations, and connects to external tools through MCP.

Today it does things like:

- **"Create a doc called Q1 Review"** → creates and opens a Word document
- **"What's changed in git since yesterday?"** → runs `git log` and summarizes it
- **"Search the web for PowerShell async patterns and save the results"** → searches, fetches, creates a notes doc
- **"Schedule the daily standup workflow to run every morning at 8am"** → registers a Windows Task Scheduler job
- **"What's in this folder?"** → reads your directory structure, git state, and notable files into the AI's context
- **"Deploy staging"** → runs a user-defined skill (JSON config, no code) that chains git commands + intents
- **Plugins** → drop a `.ps1` file into `Plugins/` and it registers new intents, categories, and workflows automatically
- **`agent "check AAPL and MSFT and calculate the difference"`** → the agent searches stock prices, runs the math, and reports back — no orchestration from you
- **`agent -Interactive "research async patterns"`** → multi-turn agent session with shared working memory across follow-up tasks
- **`Invoke-Workflow -Name daily_standup -StopOnError`** → halt a workflow on first failure rather than running all steps regardless
- **`vision screenshot`** → captures your screen and sends it to a vision-capable model for analysis
- **`build "a todo list app with categories"`** → planning agent decomposes the spec, generates code, fix loop retries on validation failure, review agent checks against spec, compiles a standalone .exe, and tracks the build in SQLite
- **`build powershell-module "a log parser module"`** → generates a `.psm1` + `.psd1` module with approved verb-noun functions, validates naming and manifest completeness, packages as a zip
- **`rebuild my-app "add dark mode"`** → applies diff-based edits to an existing build and recompiles
- **`search meeting notes`** → FTS5 full-text search across all saved conversation sessions
- **Tab ↹ on any parameter** → `Resume-Chat -Name <tab>` lists saved sessions; `Invoke-Workflow -Name <tab>` lists workflows; `gco -Branch <tab>` lists git branches; `Remove-AppBuild -Name <tab>` lists builds — every public function now has dynamic completers

All of it runs locally. Nothing phones home. The AI can only run commands you've explicitly whitelisted.

As of v1.5.0, the App Builder pipeline has been fully redesigned with five build lanes and a self-improving generation loop. A comprehensive E2E test suite covers 133 tests with 0 failures. Every public function has dynamic tab completion; the `gm` alias conflict with `Get-Member` has been resolved (`gmerge`).

---

## What BildsyPS Is Becoming

The terminal is just the first surface.

The long-term vision is **mission control for your entire computer** — an AI layer that sits between you and everything your machine can do, understands what you're working on, and acts as a continuous collaborator rather than a one-shot tool.

### The layers, in order:

**1. Shell orchestrator** *(✅ complete)*
The AI understands your terminal context — current directory, git state, running processes, file structure — and can execute actions through a safety-gated intent system with 80+ built-in intents. Security hardened: calculator sandboxed to `[math]::` only, file reads validated against allowed roots, `RequiresConfirmation` intents always prompt even in agent mode. Secret scanner detects leaked API keys in files and staged git commits.

**2. Extensibility layer** *(✅ complete)*
Drop-in plugin architecture with dependency resolution, per-plugin configuration, lifecycle hooks, self-tests, and hot-reload. User-defined skills via JSON config for non-programmers — skills are now directly callable from the shell prompt, support `{param}` substitution, trigger phrase registration, and are auto-created from the example template on first run. Community contributions without merge conflicts.

**3. Context engine** *(✅ complete)*
Persistent memory across sessions via SQLite with FTS5 full-text search. The AI recalls what you worked on yesterday, what files you've touched, what decisions you made. Conversation history stored locally, searchable across all sessions. Token budget management with intelligent context trimming and eviction summarization.

**4. Computer awareness** *(✅ complete)*
Vision model support for screenshots and images — send to Claude, GPT-4o, or local multimodal models. Browser tab awareness via UI Automation. Tesseract OCR for scanned documents and images, pdftotext for text PDFs, with vision API fallback. The AI sees what you see.

**5. Agent architecture** *(✅ complete)*
Dynamic multi-step task planning via the ReAct (Reason + Act) loop. The agent has 17 built-in tools (calculator, web search, stock quotes, Wikipedia, datetime, JSON parsing, regex, file reading, shell execution, working memory, screenshot, OCR, app building, chat history search, sub-agent spawning), unified tool+intent dispatch, an ASK protocol for mid-task user input, PLAN display, and interactive multi-turn sessions with shared memory. Background agent heartbeat for cron-triggered scheduled tasks. **Hierarchical orchestration**: agents can spawn sub-agents via `spawn_agent` with depth-limited recursion (max depth 2), memory isolation (shared at depth 0→1, isolated at depth 1→2), and parallel execution via thread jobs.

**6. App Builder** *(✅ complete)*
Prompt-to-executable pipeline. Describe an app in plain English and get a compiled Windows `.exe`. Three build lanes: PowerShell/WinForms (default — zero external deps beyond ps2exe), Python-TK (Tkinter + PyInstaller), and Python-Web (PyWebView + PyInstaller). Token budget auto-detects from model context window. Generated code is validated for syntax errors, dangerous patterns, and secret leaks before compilation. Diff-based rebuild modifies existing builds without full regeneration. Every app includes "Built with BildsyPS" branding. All builds tracked in SQLite. Code generation prompts forbid placeholder API keys and require runtime settings UI instead.

**7. Developer ergonomics** *(✅ complete)*
Dynamic tab completion on all 22 newly covered public functions across 10 modules — providers, session names, skill names, workflow names, build names, MCP server names, heartbeat task IDs, artifact files, persistent alias names, and git branches. Completers are live-data: session names come from SQLite, build names from the filesystem, branch names from `git branch --list`. The `gm` alias conflict with PowerShell's built-in `Get-Member` was resolved by renaming to `gmerge`. 37 new tests verify all completers.
Prompt-to-executable pipeline. Describe an app in plain English and get a compiled Windows `.exe` — or a packaged PowerShell module. Five build lanes: PowerShell/WinForms (default — zero external deps beyond ps2exe), PowerShell Module (`.psm1`/`.psd1` zip, zero deps), Python-TK (Tkinter + PyInstaller), Python-Web (PyWebView + PyInstaller), and Tauri (Rust + HTML/CSS/JS). Token budget auto-detects from model context window. Generated code is validated for syntax errors, dangerous patterns, and secret leaks before compilation. Diff-based rebuild modifies existing builds without full regeneration. Every app includes "Built with BildsyPS" branding. All builds tracked in SQLite.

**6b. Build Pipeline v2** *(✅ complete)*
Self-improving generation loop. A **planning agent** decomposes complex specs (>150 words) into components, functions, and data models before generation. A **fix loop** retries generation up to 2 times on validation failure, feeding the full error list back to the LLM. A **review agent** checks generated code against the original spec and triggers one additional retry on mismatch. A **build memory** SQLite table stores learned constraints from past failures — these are injected into every future generation prompt so the LLM avoids known failure patterns. An **error categorizer** converts raw error text into actionable constraint strings by framework.

**6c. Developer ergonomics** *(✅ complete)*
Dynamic tab completion on all public functions — providers, session names, skill names, workflow names, build names, MCP server names, heartbeat task IDs, artifact files, persistent alias names, git branches, and now framework names. Completers are live-data: session names come from SQLite, build names from the filesystem, branch names from `git branch --list`. The `gm` alias conflict with PowerShell's built-in `Get-Member` was resolved by renaming to `gmerge`.

**8. Reliability hardening** *(✅ complete)*
Model token limits corrected: claude-sonnet-4-6 output cap set to 64K, claude-opus-4-6 to 128K. AppBuilder truncation guard now fails early on `max_tokens` stop reason instead of passing incomplete code to the validator. AgentHeartbeat hardened: input validation on `Add-AgentTask` (time format, interval syntax, day names), atomic save via temp-file-then-rename, pre-scan for due tasks (skip overhead when nothing fires), lazy-init SQLite table, bootstrap module load order fixed, execution time limit capped at 10 minutes. Secret scanner regex refined with `(?<![A-Za-z])` lookbehind to prevent false positives on UI variable names like `$tbApiKey`.

**9. Mission control GUI** *(next)*
A dashboard layer over the shell. Not a replacement — an amplifier. The terminal stays the engine; the GUI surfaces context, history, running tasks, and agent state in a way that's faster to scan than a command line.

---

## Design Principles

**Local-first.** Your data stays on your machine. No cloud sync, no telemetry, no accounts. The AI providers you connect to are your choice.

**Nothing runs unless you tell it to.** The safety system isn't an afterthought — it's structural. Commands are whitelisted. Destructive actions require confirmation. The AI cannot execute anything outside the approved set without explicit user approval.

**Shell as the foundation.** The terminal isn't a legacy interface to be replaced. It's the most powerful general-purpose computer interface ever built. BildsyPS extends it rather than abstracting it away.

**Modular by design.** Every capability is a drop-in module. Adding a new intent, provider, or tool doesn't require touching core code. The plugin architecture makes this explicit — drop a `.ps1` file in `Plugins/` or add a skill to `UserSkills.json` and it's live.

**Open.** MIT licensed. The goal is a community of people building their own intents, workflows, and integrations on top of a shared foundation.

---

## Why Not Just Use an Existing AI Tool?

There are more AI agent tools now than there were six months ago. Most of them have real tradeoffs:

- **Provider lock-in.** Many tools are built by AI companies, for their own models. Switching providers means switching tools.
- **Subscription walls.** The most capable features sit behind monthly fees. Your automation budget scales with your usage.
- **Security exposure.** Tools that run in the cloud or require broad system permissions create attack surface. Some require you to hand over filesystem access to a remote service.
- **Narrow scope.** Most agent tools are scoped to development — code generation, PR review, terminal commands. They don't touch your calendar, your documents, your clipboard, your browser, your scheduled tasks.
- **No memory.** Most tools treat every conversation as a fresh start. There's no continuity between sessions, no awareness of what you worked on yesterday.

BildsyPS is different on all five:

**Provider-agnostic.** Claude, GPT, Ollama, LM Studio, or any llm CLI plugin. Swap models mid-session. Run entirely local if you want.

**Free and open.** MIT licensed. No subscription, no account, no telemetry. The only costs are the API calls you choose to make.

**Safety-first by design.** The safety system isn't a setting — it's structural. Commands are whitelisted. Destructive actions require confirmation. The AI cannot execute anything outside the approved set. Everything runs on your machine, under your control.

**Scoped to your entire machine.** Files, git, calendar, clipboard, browser, scheduled tasks, running processes, documents. Not just your code.

**Persistent context.** Sessions survive restarts. The AI recalls what you worked on, what decisions you made, what files you touched. Conversation history is stored locally, searchable, and will be RAG-ready.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add intents, providers, and modules.

The highest-leverage contributions right now:
- **Plugins** — Drop `.ps1` files into `Plugins/` with `$PluginIntents`, config, hooks, and tests
- **Agent tools** — Register custom tools via `Register-AgentTool` in a plugin
- **User skills** — Add JSON-defined command sequences to `UserSkills.json`
- **Provider integrations** — New LLM APIs, local model formats
- **Cross-platform testing** — macOS/Linux via PowerShell 7
- **App Builder templates** — Pre-built app scaffolds for common use cases (dashboards, utilities, data viewers)
- **Browser automation** — Selenium WebDriver integration for web scraping and testing
- **GUI layer** — Mission control dashboard (WPF/Avalonia/web) surfacing context, history, and agent state

---

The closest analogy isn't a chatbot. It's closer to having a personal operations layer — one that knows your files, your schedule, your tools, and your workflow, and can actually act on them. Not just for developers. For anyone who uses a computer and has more to do than time to do it.
