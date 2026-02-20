# ===== AgentLoop.ps1 =====
# LLM-driven autonomous task decomposition using the ReAct (Reason + Act) pattern.
# Enhanced with: unified tool+intent dispatch, working memory, ASK/PLAN protocol,
# and interactive multi-turn agent sessions.
# Depends on: AgentTools.ps1 (tool registry), IntentRouter.ps1 (intent dispatch),
#             ChatProviders.ps1 (LLM calls)

# ===== Agent Configuration =====
$global:AgentMaxSteps = 15
$global:AgentMaxTokenBudget = 12000
$global:AgentRequireConfirmation = $true
$global:AgentAbort = $false
$global:AgentLastResult = $null
$global:AgentLastPlan = $null

function Get-AgentSystemPrompt {
    <#
    .SYNOPSIS
    Build the agent system prompt with available tools, intents, memory state, and protocol.
    #>
    param(
        [switch]$IncludeFolderContext,
        [hashtable]$Memory = $global:AgentMemory
    )

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("You are an autonomous task agent inside a PowerShell environment called Shelix.")
    [void]$sb.AppendLine("Break the user's request into steps. Execute one step at a time using the tools and intents below.")
    [void]$sb.AppendLine("")

    # --- Agent Tools section ---
    [void]$sb.AppendLine("TOOLS (lightweight, for computation and lookups):")
    foreach ($toolName in $global:AgentTools.Keys) {
        $tool = $global:AgentTools[$toolName]
        $paramStr = ""
        if ($tool.Parameters -and $tool.Parameters.Count -gt 0) {
            $parts = $tool.Parameters | ForEach-Object {
                $req = if ($_.Required) { "" } else { "?" }
                "`"$($_.Name)$req`":`"..`""
            }
            $paramStr = "," + ($parts -join ",")
        }
        [void]$sb.AppendLine("  {`"tool`":`"$toolName`"$paramStr}  -- $($tool.Description)")
    }

    # --- Intents section ---
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("INTENTS (actions that affect the system — files, apps, git, etc.):")
    foreach ($catKey in $global:IntentCategories.Keys | Sort-Object) {
        $cat = $global:IntentCategories[$catKey]
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("  $($cat.Name.ToUpper()):")
        foreach ($intentName in $cat.Intents) {
            if ($global:IntentMetadata.ContainsKey($intentName)) {
                $meta = $global:IntentMetadata[$intentName]
                # Skip agent_task to prevent recursion
                if ($intentName -eq 'agent_task') { continue }
                $paramStr = ""
                if ($meta.Parameters -and $meta.Parameters.Count -gt 0) {
                    $parts = $meta.Parameters | ForEach-Object {
                        $req = if ($_.Required) { "" } else { "?" }
                        "`"$($_.Name)$req`":`"..`""
                    }
                    $paramStr = "," + ($parts -join ",")
                }
                [void]$sb.AppendLine("    {`"intent`":`"$intentName`"$paramStr}  -- $($meta.Description)")
            }
        }
    }

    # --- Working Memory ---
    [void]$sb.AppendLine("")
    if ($Memory -and $Memory.Count -gt 0) {
        [void]$sb.AppendLine("WORKING MEMORY (values stored this session):")
        foreach ($key in $Memory.Keys) {
            $val = "$($Memory[$key])"
            if ($val.Length -gt 100) { $val = $val.Substring(0, 100) + "..." }
            [void]$sb.AppendLine("  $key = $val")
        }
    }
    else {
        [void]$sb.AppendLine("WORKING MEMORY: (empty) — use store/recall tools to save values between steps")
    }

    # --- Protocol ---
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(@"
RESPONSE FORMAT — use exactly one per response:

To show your plan (optional, first response only):
PLAN:
1. First step description
2. Second step description

To reason and act:
THOUGHT: <your reasoning>
ACTION: <JSON on its own line — either {"tool":"name",...} or {"intent":"name",...}>

To ask the user a question mid-task:
THOUGHT: <why you need input>
ASK: <question for the user>

To finish:
THOUGHT: <summary>
DONE: <final answer or result>

To report inability:
THOUGHT: <what went wrong>
STUCK: <what you need from the user>

RULES:
1. ONE action per response. Wait for the OBSERVATION before continuing.
2. Output ACTION JSON as plain text — never in code blocks or backticks.
3. Use {"tool":"name",...} for computation/lookups, {"intent":"name",...} for system actions.
4. Use store/recall tools to save important intermediate values.
5. If an action fails, analyze and try an alternative.
6. Use ASK when you genuinely need user input to proceed.
7. Use DONE when complete with a clear summary.
8. Do not repeat the same failed action.
"@)

    # --- Folder context ---
    if ($IncludeFolderContext -and (Get-Command Get-FolderContext -ErrorAction SilentlyContinue)) {
        $folderCtx = Get-FolderContext -IncludeGitStatus
        if ($folderCtx) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("CURRENT DIRECTORY CONTEXT:")
            [void]$sb.AppendLine($folderCtx)
        }
    }

    return $sb.ToString()
}

function Format-AgentObservation {
    <#
    .SYNOPSIS
    Compress a tool or intent result into a token-efficient observation string.
    #>
    param(
        [int]$StepNumber,
        [int]$MaxSteps,
        [string]$ActionName,
        [string]$ActionType,
        [hashtable]$Result,
        [int]$MaxChars = 2000
    )

    $status = if ($Result.Success) { "Success" } else { "Failed" }
    $output = if ($Result.Output) { "$($Result.Output)" } elseif ($Result.Error -and $Result.Error -is [string]) { "$($Result.Error)" } else { "(no output)" }

    $truncated = ""
    if ($output.Length -gt $MaxChars) {
        $fullLength = $output.Length
        $output = $output.Substring(0, $MaxChars)
        $truncated = "`n  ... (truncated, ${fullLength} chars total)"
    }

    $time = if ($Result.ExecutionTime) { " in $([math]::Round($Result.ExecutionTime, 2))s" } else { "" }

    # Include memory state hint if memory was modified
    $memHint = ""
    if ($global:AgentMemory.Count -gt 0) {
        $memHint = "`n  Memory keys: $($global:AgentMemory.Keys -join ', ')"
    }

    return @"
OBSERVATION [step $StepNumber/$MaxSteps] (${ActionType}: ${ActionName}):
  Status: $status$time
  Output: $output$truncated$memHint
"@
}

function Stop-AgentTask {
    <#
    .SYNOPSIS
    Abort a running agent task. Call this or press Ctrl+C.
    #>
    $global:AgentAbort = $true
    Write-Host "`n[Agent] Abort requested. Stopping after current step." -ForegroundColor Yellow
}

function Show-AgentSteps {
    <#
    .SYNOPSIS
    Show the steps from the last agent run.
    #>
    if (-not $global:AgentLastResult -or $global:AgentLastResult.Steps.Count -eq 0) {
        Write-Host "No agent steps to show." -ForegroundColor Yellow
        return
    }
    Write-Host "`n===== Last Agent Run ($($global:AgentLastResult.StepCount) steps) =====" -ForegroundColor Cyan
    foreach ($step in $global:AgentLastResult.Steps) {
        $icon = if ($step.Success) { "[OK]" } else { "[FAIL]" }
        $color = if ($step.Success) { "Green" } else { "Red" }
        $typeLabel = if ($step.Type -eq 'tool') { "tool" } else { "intent" }
        $nameLabel = if ($step.Tool) { $step.Tool } else { $step.Intent }
        Write-Host "  $($step.Step). $icon " -ForegroundColor $color -NoNewline
        Write-Host "${typeLabel}:${nameLabel}" -ForegroundColor Yellow -NoNewline
        $preview = if ($step.Output) {
            $o = "$($step.Output)" -replace "`n", " "
            if ($o.Length -gt 60) { $o.Substring(0, 60) + "..." } else { $o }
        } else { "" }
        Write-Host " $preview" -ForegroundColor Gray
    }
    if ($global:AgentLastResult.Summary) {
        Write-Host "`n  Summary: $($global:AgentLastResult.Summary)" -ForegroundColor White
    }
    Write-Host "=========================" -ForegroundColor Cyan
}

function Show-AgentMemory {
    <#
    .SYNOPSIS
    Display the agent's current working memory.
    #>
    if ($global:AgentMemory.Count -eq 0) {
        Write-Host "Agent memory is empty." -ForegroundColor Yellow
        return
    }
    Write-Host "`n===== Agent Memory =====" -ForegroundColor Cyan
    foreach ($key in $global:AgentMemory.Keys) {
        $val = "$($global:AgentMemory[$key])"
        if ($val.Length -gt 100) { $val = $val.Substring(0, 100) + "..." }
        Write-Host "  $key" -ForegroundColor Yellow -NoNewline
        Write-Host " = $val" -ForegroundColor Gray
    }
    Write-Host "========================`n" -ForegroundColor Cyan
}

function Show-AgentPlan {
    <#
    .SYNOPSIS
    Show the agent's last announced plan.
    #>
    if (-not $global:AgentLastPlan) {
        Write-Host "No agent plan available." -ForegroundColor Yellow
        return
    }
    Write-Host "`n===== Agent Plan =====" -ForegroundColor Cyan
    Write-Host $global:AgentLastPlan -ForegroundColor White
    Write-Host "======================" -ForegroundColor Cyan
}

function Invoke-AgentTask {
    <#
    .SYNOPSIS
    Execute a natural language task autonomously using the ReAct pattern.
    Enhanced with tool+intent dispatch, working memory, ASK protocol, and interactive mode.

    .PARAMETER Task
    Natural language description of what to accomplish.

    .PARAMETER Interactive
    Enter interactive mode — after the task completes, prompt for follow-up tasks
    with shared context and memory.

    .PARAMETER Memory
    Pre-seed working memory with a hashtable of named values.

    .PARAMETER Provider
    LLM provider (default: $global:DefaultChatProvider).

    .PARAMETER Model
    Model override.

    .PARAMETER MaxSteps
    Maximum number of agent steps (default: $global:AgentMaxSteps).

    .PARAMETER AutoConfirm
    Skip confirmation for safe intents. Destructive intents still prompt.

    .PARAMETER ShowThoughts
    Display the LLM's THOUGHT reasoning (default: $true).

    .EXAMPLE
    Invoke-AgentTask -Task "list files and find the largest"
    agent "check stock prices for AAPL and MSFT"
    agent -Interactive "research PowerShell automation"
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Task,

        [ValidateSet('ollama', 'anthropic', 'lmstudio', 'openai', 'llm')]
        [string]$Provider = $global:DefaultChatProvider,

        [string]$Model = $null,

        [int]$MaxSteps = $global:AgentMaxSteps,

        [switch]$AutoConfirm,

        [switch]$ShowThoughts,

        [switch]$Interactive,

        [hashtable]$Memory = $null
    )

    # Default ShowThoughts to true
    if (-not $PSBoundParameters.ContainsKey('ShowThoughts')) { $ShowThoughts = $true }

    # Reset state
    $global:AgentAbort = $false
    $global:AgentLastPlan = $null
    if ($Memory) {
        $global:AgentMemory = $Memory.Clone()
    }
    else {
        $global:AgentMemory = @{}
    }

    # Resolve provider and model
    $providerConfig = $global:ChatProviders[$Provider]
    if (-not $providerConfig) {
        Write-Host "[Agent] Unknown provider: $Provider" -ForegroundColor Red
        return @{ Success = $false; AbortReason = "UnknownProvider" }
    }
    if (-not $Model) { $Model = $providerConfig.DefaultModel }

    # Check API key
    if ($providerConfig.ApiKeyRequired) {
        $apiKey = Get-ChatApiKey $Provider
        if (-not $apiKey) {
            Write-Host "[Agent] API key required for $($providerConfig.Name)." -ForegroundColor Red
            return @{ Success = $false; AbortReason = "NoApiKey" }
        }
    }

    # Display task header
    $modeLabel = if ($Interactive) { "Interactive Agent" } else { "Agent Task" }
    Write-Host "`n===== $modeLabel =====" -ForegroundColor Cyan
    Write-Host "  Task: $Task" -ForegroundColor White
    Write-Host "  Provider: $($providerConfig.Name) | Model: $Model" -ForegroundColor Gray
    Write-Host "  Max steps: $MaxSteps | Tools: $($global:AgentTools.Count) | Ctrl+C to abort" -ForegroundColor Gray
    if ($Interactive) { Write-Host "  Interactive: type follow-up tasks or 'done' to exit" -ForegroundColor Gray }
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host ""

    # Outer loop for interactive mode
    $continueInteractive = $true
    $allStepResults = @()
    $allMessages = @()
    $totalSteps = 0
    $overallStart = Get-Date

    while ($continueInteractive) {
        # Build system prompt (refreshed each task to include updated memory)
        $includeFolderCtx = $global:FolderContextEnabled -or (Test-Path .git -ErrorAction SilentlyContinue)
        $systemPrompt = Get-AgentSystemPrompt -IncludeFolderContext:$includeFolderCtx -Memory $global:AgentMemory

        # Initialize conversation for this task
        $agentMessages = @()
        # Carry forward previous messages in interactive mode for context
        if ($Interactive -and $allMessages.Count -gt 0) {
            # Inject a compact summary of prior work instead of full history
            $priorSummary = "Previous agent work in this session: $($allStepResults.Count) steps completed."
            if ($global:AgentMemory.Count -gt 0) {
                $priorSummary += " Working memory: $($global:AgentMemory.Keys -join ', ')."
            }
            $agentMessages += @{ role = "user"; content = "[CONTEXT] $priorSummary" }
            $agentMessages += @{ role = "assistant"; content = "Understood. I have context from our previous work and access to working memory." }
        }
        $agentMessages += @{ role = "user"; content = "TASK: $Task" }

        $stepResults = @()
        $stepNumber = 0
        $taskStartTime = Get-Date
        $done = $false
        $finalSummary = ""
        $abortReason = $null

        # ===== Main ReAct Loop =====
        while ($stepNumber -lt $MaxSteps -and -not $done -and -not $global:AgentAbort) {
            $stepNumber++
            $totalSteps++

            # Token budget check
            $totalChars = ($agentMessages | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum
            $estimatedTokens = [math]::Ceiling($totalChars / 4)
            if ($estimatedTokens -gt $global:AgentMaxTokenBudget) {
                Write-Host "[Agent] Token budget exceeded (~$estimatedTokens tokens). Stopping." -ForegroundColor Yellow
                $abortReason = "TokenBudget"
                break
            }

            # Rate limit check
            if (Get-Command Test-RateLimit -ErrorAction SilentlyContinue) {
                $rateCheck = Test-RateLimit
                if (-not $rateCheck.Allowed) {
                    Write-Host "[Agent] Rate limited: $($rateCheck.Message)" -ForegroundColor Yellow
                    $abortReason = "RateLimit"
                    break
                }
            }

            # Call LLM
            Write-Host "[Step $stepNumber/$MaxSteps] Thinking..." -ForegroundColor DarkCyan
            try {
                $response = Invoke-ChatCompletion `
                    -Messages $agentMessages `
                    -Provider $Provider `
                    -Model $Model `
                    -Temperature 0.3 `
                    -MaxTokens 2048 `
                    -SystemPrompt $systemPrompt
            }
            catch {
                Write-Host "[Agent] LLM call failed: $($_.Exception.Message)" -ForegroundColor Red
                $abortReason = "LLMError"
                break
            }

            $reply = $response.Content
            $agentMessages += @{ role = "assistant"; content = $reply }

            # Parse response for THOUGHT, ACTION, DONE, STUCK, ASK, PLAN
            $thought = $null
            $action = $null
            $doneText = $null
            $stuckText = $null
            $askText = $null
            $planLines = @()
            $inPlan = $false

            foreach ($line in ($reply -split "`n")) {
                $trimmed = $line.Trim()
                if ($inPlan) {
                    if ($trimmed -match '^(THOUGHT|ACTION|DONE|STUCK|ASK):') {
                        $inPlan = $false
                        # Fall through to parse this line normally
                    }
                    elseif ($trimmed) {
                        $planLines += $trimmed
                        continue
                    }
                    else { continue }
                }
                if ($trimmed -match '^THOUGHT:\s*(.+)$') {
                    $thought = $Matches[1]
                }
                elseif ($trimmed -match '^ACTION:\s*(.+)$') {
                    $action = $Matches[1]
                }
                elseif ($trimmed -match '^DONE:\s*(.+)$') {
                    $doneText = $Matches[1]
                }
                elseif ($trimmed -match '^STUCK:\s*(.+)$') {
                    $stuckText = $Matches[1]
                }
                elseif ($trimmed -match '^ASK:\s*(.+)$') {
                    $askText = $Matches[1]
                }
                elseif ($trimmed -match '^PLAN:\s*$' -or $trimmed -match '^PLAN:$') {
                    $inPlan = $true
                }
                elseif ($trimmed -match '^PLAN:\s*(.+)$') {
                    $planLines += $Matches[1]
                    $inPlan = $true
                }
                elseif (-not $action -and $trimmed -match '^\s*\{.*"(intent|tool)".*\}\s*$') {
                    $action = $trimmed
                }
            }

            # Display plan if provided
            if ($planLines.Count -gt 0) {
                $planText = $planLines -join "`n"
                $global:AgentLastPlan = $planText
                Write-Host "  Plan:" -ForegroundColor Magenta
                foreach ($pl in $planLines) {
                    Write-Host "    $pl" -ForegroundColor DarkMagenta
                }
            }

            # Display thought
            if ($thought -and $ShowThoughts) {
                Write-Host "  Thought: $thought" -ForegroundColor DarkGray
            }

            # Handle DONE
            if ($doneText) {
                $done = $true
                $finalSummary = $doneText
                Write-Host "`n[Agent] Task Complete" -ForegroundColor Green
                Write-Host "  $doneText" -ForegroundColor White
                break
            }

            # Handle STUCK
            if ($stuckText) {
                $done = $true
                $finalSummary = "STUCK: $stuckText"
                $abortReason = "Stuck"
                Write-Host "`n[Agent] Stuck — needs user input" -ForegroundColor Yellow
                Write-Host "  $stuckText" -ForegroundColor White
                break
            }

            # Handle ASK — pause for user input
            if ($askText) {
                Write-Host "`n[Agent] Question:" -ForegroundColor Magenta
                Write-Host "  $askText" -ForegroundColor White
                Write-Host -NoNewline "  Answer> " -ForegroundColor Yellow
                $userAnswer = Read-Host
                if ($userAnswer -in @('abort', 'cancel', 'stop')) {
                    $global:AgentAbort = $true
                    break
                }
                $agentMessages += @{ role = "user"; content = "ANSWER: $userAnswer" }
                # Don't increment step for ASK — it's not an action
                $stepNumber--
                $totalSteps--
                continue
            }

            # Handle ACTION — unified tool + intent dispatch
            if ($action) {
                $actionJson = $null
                try {
                    $actionJson = $action | ConvertFrom-Json
                }
                catch {
                    Write-Host "  [Agent] Failed to parse action JSON: $action" -ForegroundColor Red
                    $observation = "OBSERVATION [step $stepNumber/$MaxSteps]:`n  Error: Could not parse JSON. Use {`"tool`":`"name`",...} or {`"intent`":`"name`",...}"
                    $agentMessages += @{ role = "user"; content = $observation }
                    continue
                }

                $actionType = $null
                $actionName = $null
                $actionParams = @{}

                # Determine if it's a tool call or intent call
                if ($actionJson.tool) {
                    $actionType = 'tool'
                    $actionName = $actionJson.tool
                    $actionJson.PSObject.Properties | Where-Object { $_.Name -ne 'tool' } | ForEach-Object {
                        $actionParams[$_.Name] = $_.Value
                    }
                }
                elseif ($actionJson.intent) {
                    $actionType = 'intent'
                    $actionName = $actionJson.intent
                    $actionJson.PSObject.Properties | Where-Object { $_.Name -ne 'intent' } | ForEach-Object {
                        $actionParams[$_.Name] = $_.Value
                    }
                }
                else {
                    Write-Host "  [Agent] JSON must contain 'tool' or 'intent' key" -ForegroundColor Red
                    $observation = "OBSERVATION [step $stepNumber/$MaxSteps]:`n  Error: JSON must have a 'tool' or 'intent' key."
                    $agentMessages += @{ role = "user"; content = $observation }
                    continue
                }

                # Display action
                $typeIcon = if ($actionType -eq 'tool') { "T" } else { "I" }
                Write-Host "  [$typeIcon] $actionName" -ForegroundColor Yellow -NoNewline
                if ($actionParams.Count -gt 0) {
                    $paramDisplay = ($actionParams.GetEnumerator() | ForEach-Object {
                        $v = "$($_.Value)"
                        if ($v.Length -gt 40) { $v = $v.Substring(0, 40) + "..." }
                        "$($_.Key)=$v"
                    }) -join ", "
                    Write-Host " ($paramDisplay)" -ForegroundColor DarkYellow
                }
                else {
                    Write-Host "" # newline
                }

                # Execute
                $stepStart = Get-Date
                $actionResult = $null

                if ($actionType -eq 'tool') {
                    try {
                        $actionResult = Invoke-AgentTool -Name $actionName -Params $actionParams
                        $actionResult['ExecutionTime'] = ((Get-Date) - $stepStart).TotalSeconds
                    }
                    catch {
                        $actionResult = @{
                            Success       = $false
                            Output        = "Tool exception: $($_.Exception.Message)"
                            ExecutionTime = ((Get-Date) - $stepStart).TotalSeconds
                        }
                    }
                }
                else {
                    # Intent dispatch
                    try {
                        $intentResult = Invoke-IntentAction -Intent $actionName -Payload $actionParams -AutoConfirm:$AutoConfirm
                        $actionResult = @{
                            Success       = $intentResult.Success
                            Output        = $intentResult.Output
                            ExecutionTime = $intentResult.ExecutionTime
                        }
                    }
                    catch {
                        $actionResult = @{
                            Success       = $false
                            Output        = "Intent exception: $($_.Exception.Message)"
                            ExecutionTime = ((Get-Date) - $stepStart).TotalSeconds
                        }
                    }
                }

                # Display result
                $statusIcon = if ($actionResult.Success) { "[OK]" } else { "[FAIL]" }
                $statusColor = if ($actionResult.Success) { "Green" } else { "Red" }
                $outputPreview = if ($actionResult.Output) {
                    $o = "$($actionResult.Output)" -replace "`n", " "
                    if ($o.Length -gt 80) { $o.Substring(0, 80) + "..." } else { $o }
                } else { "(no output)" }
                Write-Host "  $statusIcon $outputPreview" -ForegroundColor $statusColor

                # Record step
                $stepRecord = @{
                    Step          = $stepNumber
                    Type          = $actionType
                    Intent        = if ($actionType -eq 'intent') { $actionName } else { $null }
                    Tool          = if ($actionType -eq 'tool') { $actionName } else { $null }
                    Params        = $actionParams
                    Success       = $actionResult.Success
                    Output        = $actionResult.Output
                    ExecutionTime = $actionResult.ExecutionTime
                }
                $stepResults += $stepRecord

                # Build observation
                $observation = Format-AgentObservation `
                    -StepNumber $stepNumber `
                    -MaxSteps $MaxSteps `
                    -ActionName $actionName `
                    -ActionType $actionType `
                    -Result $actionResult

                $agentMessages += @{ role = "user"; content = $observation }
            }
            elseif (-not $doneText -and -not $stuckText -and -not $askText) {
                Write-Host "  [Agent] No action detected. Nudging..." -ForegroundColor DarkYellow
                $agentMessages += @{ role = "user"; content = "Respond with ACTION: {JSON}, DONE: result, ASK: question, or STUCK: reason." }
            }
        }

        # Handle max steps reached
        if ($stepNumber -ge $MaxSteps -and -not $done) {
            $abortReason = "MaxSteps"
            Write-Host "`n[Agent] Reached max steps ($MaxSteps). Stopping." -ForegroundColor Yellow
        }

        # Handle user abort
        if ($global:AgentAbort -and -not $done) {
            $abortReason = "UserAbort"
            Write-Host "`n[Agent] Aborted by user." -ForegroundColor Yellow
        }

        # Accumulate results
        $allStepResults += $stepResults
        $allMessages += $agentMessages

        $taskTime = ((Get-Date) - $taskStartTime).TotalSeconds
        $taskTokensEst = [math]::Ceiling(($agentMessages | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum / 4)

        # Summary
        Write-Host "`n===== Agent Summary =====" -ForegroundColor Cyan
        Write-Host "  Steps: $stepNumber | Time: $([math]::Round($taskTime, 1))s | ~$taskTokensEst tokens" -ForegroundColor Gray
        $successes = @($stepResults | Where-Object { $_.Success }).Count
        $failures = @($stepResults | Where-Object { -not $_.Success }).Count
        if ($stepResults.Count -gt 0) {
            Write-Host "  Results: $successes succeeded, $failures failed" -ForegroundColor $(if ($failures -eq 0) { 'Green' } else { 'Yellow' })
        }
        if ($global:AgentMemory.Count -gt 0) {
            Write-Host "  Memory: $($global:AgentMemory.Keys -join ', ')" -ForegroundColor DarkCyan
        }
        if ($abortReason) {
            Write-Host "  Stopped: $abortReason" -ForegroundColor Yellow
        }
        Write-Host "=========================" -ForegroundColor Cyan

        # Toast notification
        if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
            $toastMsg = if ($finalSummary) {
                $s = $finalSummary; if ($s.Length -gt 80) { $s.Substring(0, 80) + '...' } else { $s }
            } else { "Agent finished ($stepNumber steps)" }
            $toastType = if ($done -and -not $abortReason) { 'Success' } else { 'Warning' }
            Send-ShелixToast -Title "Agent task complete" -Message $toastMsg -Type $toastType
        }

        # Interactive mode: prompt for follow-up
        if ($Interactive -and -not $global:AgentAbort) {
            Write-Host ""
            Write-Host -NoNewline "Agent> " -ForegroundColor Magenta
            $followUp = Read-Host
            if ($followUp -in @('done', 'exit', 'quit', '')) {
                $continueInteractive = $false
            }
            else {
                $Task = $followUp
                $global:AgentAbort = $false
                Write-Host ""
                continue
            }
        }
        else {
            $continueInteractive = $false
        }
    }

    $overallTime = ((Get-Date) - $overallStart).TotalSeconds
    $overallTokensEst = [math]::Ceiling(($allMessages | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum / 4)

    # Store result globally
    $result = @{
        Success     = ($done -and -not $abortReason)
        Summary     = if ($finalSummary) { $finalSummary } else { "Agent stopped after $totalSteps steps ($abortReason)" }
        Steps       = $allStepResults
        StepCount   = $totalSteps
        TotalTime   = [math]::Round($overallTime, 2)
        TokensUsed  = $overallTokensEst
        AbortReason = $abortReason
        Messages    = $allMessages
        Memory      = $global:AgentMemory.Clone()
    }
    $global:AgentLastResult = $result

    return $result
}

# ===== Aliases =====
Set-Alias agent Invoke-AgentTask -Force
Set-Alias agent-stop Stop-AgentTask -Force
Set-Alias agent-steps Show-AgentSteps -Force
Set-Alias agent-memory Show-AgentMemory -Force
Set-Alias agent-plan Show-AgentPlan -Force

Write-Verbose "AgentLoop loaded: Invoke-AgentTask (agent), Stop-AgentTask, Show-AgentSteps, Show-AgentMemory, Show-AgentPlan"
