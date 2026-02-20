# ===== IntentAliasSystem.ps1 =====
# Friendly task aliases that the AI can call via JSON intents
# Maps user-friendly intent names to concrete PowerShell commands
# If you're reading this, you're exactly the kind of person who should be using this tool
#
# This file is a thin orchestrator that loads the modular intent subsystem:
#   IntentRegistry.ps1       — Category defs, IntentMetadata, IntentCategories
#   IntentActions.ps1        — Core intent scriptblocks (docs, files, web, git, MCP, calendar)
#   IntentActionsSystem.ps1  — System/filesystem/composite/workflow intent scriptblocks
#   WorkflowEngine.ps1       — Multi-step workflow definitions and execution
#   IntentRouter.ps1         — Invoke-IntentAction, help functions, tab completion, aliases
#   AgentTools.ps1           — Agent tool registry (calculator, web, stock, memory, etc.)
#   AgentLoop.ps1            — LLM-driven autonomous task decomposition (ReAct pattern)

. "$PSScriptRoot\IntentRegistry.ps1"
. "$PSScriptRoot\IntentActions.ps1"
. "$PSScriptRoot\IntentActionsSystem.ps1"
. "$PSScriptRoot\WorkflowEngine.ps1"
. "$PSScriptRoot\IntentRouter.ps1"
. "$PSScriptRoot\AgentTools.ps1"
. "$PSScriptRoot\AgentLoop.ps1"
