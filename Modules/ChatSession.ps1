# ===== ChatSession.ps1 =====
# LLM Chat session management, persistence, and the main chat loop

# ===== Chat Session State =====
$global:ChatSessionHistory = @()
$global:ChatSessionName = $null       # Current session name (null = unnamed)
$global:ChatLogsPath = "$global:BildsyPSHome\logs\sessions"
$global:ChatSessionIndex = @{}        # In-memory index: name -> metadata

# ===== Chat Session Functions =====
function Start-ChatSession {
    <#
    .SYNOPSIS
    Start an interactive LLM chat session
    #>
    param(
        [ValidateSet('ollama', 'anthropic', 'lmstudio', 'openai', 'llm')]
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model = $null,
        [double]$Temperature = 0.7,
        [int]$MaxResponseTokens = 4096,  # Max tokens for AI response (sent to API)
        [switch]$IncludeSafeCommands,
        [switch]$Stream,
        [switch]$AutoTrim,
        [switch]$Resume,
        [switch]$Continue,
        [switch]$FolderAware   # Inject current directory context + auto-update on cd
    )
    
    # Get provider config
    $providerConfig = $global:ChatProviders[$Provider]
    if (-not $providerConfig) {
        Write-Host "Unknown provider: $Provider" -ForegroundColor Red
        return
    }
    
    # Use default model if not specified
    if (-not $Model) {
        $Model = $providerConfig.DefaultModel
    }
    
    # Check API key if required
    if ($providerConfig.ApiKeyRequired) {
        $apiKey = Get-ChatApiKey $Provider
        if (-not $apiKey) {
            Write-Host "API key required for $($providerConfig.Name)." -ForegroundColor Red
            Write-Host "Set it with: Set-ChatApiKey -Provider $Provider -ApiKey 'your-key'" -ForegroundColor Yellow
            return
        }
    }

    Write-Host "`nEntering LLM chat mode" -ForegroundColor Cyan
    Write-Host "  Provider: $($providerConfig.Name)" -ForegroundColor Gray
    Write-Host "  Model: $Model" -ForegroundColor Gray
    if ($Stream) { Write-Host "  Streaming: enabled" -ForegroundColor Gray }
    if ($AutoTrim) { Write-Host "  Auto-trim: enabled" -ForegroundColor Gray }
    $contextLimit = Get-ModelContextLimit -Model $Model
    Write-Host "  Context: $([math]::Round($contextLimit/1000))K tokens | Response: $MaxResponseTokens tokens" -ForegroundColor Gray
    Write-Host "Type 'exit' to quit, 'clear' to reset, 'save' to archive, 'resume' to load last session, 'sessions' to browse, 'budget' for token usage, 'switch' to change provider." -ForegroundColor DarkGray
    
    # Initialize session state
    $global:ChatSessionHistory = @()
    $global:ChatSessionName = $null
    $systemPrompt = $null
    
    # -Continue implies -Resume
    if ($Continue) { $Resume = $true }
    
    # Auto-resume: load last saved session
    if ($Resume) {
        $loaded = Resume-Chat
        if ($loaded) {
            Write-Host "  Resumed: $($loaded.name) ($($global:ChatSessionHistory.Count) messages)" -ForegroundColor DarkCyan
            if ($Continue) {
                $summary = Get-SessionSummary
                $continuePreamble = "You are continuing a conversation from $($loaded.savedAt). Here is a summary of what was discussed:`n$summary`nThe user may reference previous topics. Use this context naturally."
                if ($Provider -eq 'anthropic') {
                    $systemPrompt = $continuePreamble
                }
                else {
                    # Prepend as first exchange for OpenAI-compatible
                    $global:ChatSessionHistory = @(
                        @{ role = "user"; content = "[Context from previous session]`n$continuePreamble" },
                        @{ role = "assistant"; content = "I remember our previous conversation. I'm ready to continue." }
                    ) + $global:ChatSessionHistory
                }
                Write-Host "  Context recall: injected previous session summary" -ForegroundColor DarkCyan
            }
        }
        else {
            Write-Host "  No previous session to resume. Starting fresh." -ForegroundColor DarkGray
        }
    }
    
    # Load safe commands context
    if ($IncludeSafeCommands) {
        $safeCommandsPrompt = Get-SafeCommandsPrompt
        
        if ($Provider -eq 'anthropic') {
            # Append to existing system prompt if -Continue already set one
            if ($systemPrompt) {
                $systemPrompt = $systemPrompt + "`n`n" + $safeCommandsPrompt
            }
            else {
                $systemPrompt = $safeCommandsPrompt
            }
        }
        else {
            $global:ChatSessionHistory += @{ role = "user"; content = $safeCommandsPrompt }
            $global:ChatSessionHistory += @{ role = "assistant"; content = "Understood. I have access to PowerShell commands and intent actions. I'm ready to help." }
        }
        Write-Host "  Safe commands context loaded." -ForegroundColor Green
    }
    
    # Folder awareness -- inject current directory context
    if ($FolderAware) {
        Invoke-FolderContextUpdate -IncludeGitStatus
        Enable-FolderAwareness
    }
    Write-Host ""

    $continue = $true
    while ($continue) {
        Write-Host -NoNewline "`nYou> " -ForegroundColor Yellow
        $inputText = Read-Host

        switch -Regex ($inputText) {
            '^exit$' { 
                Write-Host "`nSession ended." -ForegroundColor Green
                # Auto-save on exit if there's anything worth keeping
                if ($global:ChatSessionHistory.Count -gt 0) {
                    Save-Chat -Auto
                }
                $continue = $false
                break
            }
            '^clear$' { 
                if ($global:ChatSessionHistory.Count -gt 0) { Save-Chat -Auto }
                $global:ChatSessionHistory = @()
                $global:ChatSessionName = $null
                Write-Host "Memory cleared (auto-saved previous)." -ForegroundColor DarkGray
                continue 
            }
            '^save$' { 
                Save-Chat
                continue 
            }
            '^save\s+(.+)$' {
                Save-Chat -Name $Matches[1]
                continue
            }
            '^resume$' {
                $loaded = Resume-Chat
                if ($loaded) {
                    Write-Host "Resumed: $($loaded.Name) ($($global:ChatSessionHistory.Count) messages)" -ForegroundColor Cyan
                }
                continue
            }
            '^resume\s+(.+)$' {
                $loaded = Resume-Chat -Name $Matches[1]
                if ($loaded) {
                    Write-Host "Resumed: $($loaded.Name) ($($global:ChatSessionHistory.Count) messages)" -ForegroundColor Cyan
                }
                continue
            }
            '^sessions$' {
                Get-ChatSessions
                continue
            }
            '^rename\s+(.+)$' {
                $newName = $Matches[1]
                if ($global:ChatSessionHistory.Count -eq 0) {
                    Write-Host "No active session to rename." -ForegroundColor Yellow
                }
                else {
                    $oldName = $global:ChatSessionName
                    if ($oldName -and $global:ChatDbReady -and (Get-Command Rename-ChatSessionInDb -ErrorAction SilentlyContinue)) {
                        Rename-ChatSessionInDb -OldName $oldName -NewName $newName | Out-Null
                    }
                    Save-Chat -Name $newName
                    Write-Host "Session renamed to: $newName" -ForegroundColor Green
                }
                continue
            }
            '^(tokens|budget)$' { 
                $est = Get-EstimatedTokenCount
                $contextLimit = Get-ModelContextLimit -Model $Model
                $budget = $contextLimit - $MaxResponseTokens
                $pct = if ($budget -gt 0) { [math]::Round(($est / $budget) * 100) } else { 0 }
                
                Write-Host "`n  Token Budget" -ForegroundColor Cyan
                Write-Host "  Context window: $([math]::Round($contextLimit/1000))K tokens ($Model)" -ForegroundColor Gray
                Write-Host "  Response reserve: $MaxResponseTokens tokens" -ForegroundColor Gray
                Write-Host "  Input budget: $budget tokens" -ForegroundColor Gray
                Write-Host "  Current usage: ~$est tokens ($pct%)" -ForegroundColor $(if ($pct -gt 80) { 'Yellow' } elseif ($pct -gt 60) { 'DarkYellow' } else { 'Green' })
                Write-Host "  Messages: $($global:ChatSessionHistory.Count)" -ForegroundColor Gray
                
                # Show per-category breakdown
                $systemTokens = 0; $userTokens = 0; $assistantTokens = 0
                foreach ($msg in $global:ChatSessionHistory) {
                    $t = [math]::Ceiling($msg.content.Length / 4)
                    switch ($msg.role) {
                        'system' { $systemTokens += $t }
                        'user' { $userTokens += $t }
                        'assistant' { $assistantTokens += $t }
                    }
                }
                Write-Host "  Breakdown: system=$systemTokens  user=$userTokens  assistant=$assistantTokens" -ForegroundColor DarkGray
                Write-Host ""
                continue 
            }
            '^search\s+(.+)$' {
                Search-ChatSessions -Keyword $Matches[1]
                continue
            }
            '^(secrets|/secrets)$' {
                if (Get-Command Invoke-StartupSecretScan -ErrorAction SilentlyContinue) {
                    Invoke-StartupSecretScan
                }
                else { Write-Host 'SecretScanner module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(ocr|/ocr)\s+(.+)$' {
                $ocrPath = $Matches[2]
                if (Get-Command Invoke-OCRFile -ErrorAction SilentlyContinue) {
                    $ocrResult = Invoke-OCRFile -Path $ocrPath
                    if ($ocrResult -and $ocrResult.Success) {
                        $global:ChatSessionHistory += @{ role = 'user'; content = "[OCR: extracted text from $ocrPath]" }
                        $global:ChatSessionHistory += @{ role = 'assistant'; content = $ocrResult.Output }
                    }
                }
                else { Write-Host 'OCRTools module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(heartbeat|/heartbeat)$' {
                if (Get-Command Get-HeartbeatStatus -ErrorAction SilentlyContinue) { Get-HeartbeatStatus }
                else { Write-Host 'AgentHeartbeat module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(heartbeat|/heartbeat)\s+list$' {
                if (Get-Command Show-AgentTaskList -ErrorAction SilentlyContinue) { Show-AgentTaskList }
                else { Write-Host 'AgentHeartbeat module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(heartbeat|/heartbeat)\s+add\s+"([^"]+)"\s*(.*)$' {
                if (Get-Command Add-AgentTask -ErrorAction SilentlyContinue) {
                    $taskDesc = $Matches[2]
                    $taskId = ($taskDesc -replace '[^a-zA-Z0-9]', '-').Trim('-').Substring(0, [math]::Min(30, $taskDesc.Length))
                    $extraArgs = $Matches[3]
                    $schedule = 'daily'; $time = '08:00'
                    if ($extraArgs -match 'weekly') { $schedule = 'weekly' }
                    if ($extraArgs -match '(\d{1,2}:\d{2})') { $time = $Matches[1] }
                    Add-AgentTask -Id $taskId -Task $taskDesc -Schedule $schedule -Time $time
                }
                else { Write-Host 'AgentHeartbeat module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(heartbeat|/heartbeat)\s+stop$' {
                if (Get-Command Unregister-AgentHeartbeat -ErrorAction SilentlyContinue) { Unregister-AgentHeartbeat }
                else { Write-Host 'AgentHeartbeat module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(build|/build)\s+(-tokens\s+\d+\s+)?(-nobranding\s+)?(python-tk\s+|python-web\s+|powershell\s+)?"(.+)"$' {
                if (Get-Command New-AppBuild -ErrorAction SilentlyContinue) {
                    $buildParams = @{ Prompt = $Matches[5] }
                    if ($Matches[4]) { $buildParams.Framework = $Matches[4].Trim() }
                    if ($Matches[2] -match '(\d+)') { $buildParams.MaxTokens = [int]$Matches[1] }
                    if ($Matches[3]) { $buildParams.NoBranding = $true }
                    New-AppBuild @buildParams
                }
                else { Write-Host 'AppBuilder module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(build|/build)\s+"(.+)"$' {
                if (Get-Command New-AppBuild -ErrorAction SilentlyContinue) {
                    New-AppBuild -Prompt $Matches[2]
                }
                else { Write-Host 'AppBuilder module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(builds|/builds)$' {
                if (Get-Command Get-AppBuilds -ErrorAction SilentlyContinue) { Get-AppBuilds }
                else { Write-Host 'AppBuilder module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(rebuild|/rebuild)\s+(\S+)\s+"(.+)"$' {
                if (Get-Command Update-AppBuild -ErrorAction SilentlyContinue) {
                    Update-AppBuild -Name $Matches[2] -Changes $Matches[3]
                }
                else { Write-Host 'AppBuilder module not loaded.' -ForegroundColor Red }
                continue
            }
            '^delete\s+(.+)$' {
                $delName = $Matches[1]
                Write-Host "Delete session '$delName'? (y/N): " -ForegroundColor Yellow -NoNewline
                $confirm = Read-Host
                if ($confirm -eq 'y') {
                    Remove-ChatSession -Name $delName
                }
                else {
                    Write-Host "Cancelled." -ForegroundColor DarkGray
                }
                continue
            }
            '^export$' {
                Export-ChatSession
                continue
            }
            '^export\s+(.+)$' {
                Export-ChatSession -Name $Matches[1]
                continue
            }
            '^commands$' {
                Write-Host "`nSafe PowerShell Commands Available:" -ForegroundColor Cyan
                Get-SafeActions
                continue
            }
            '^switch$' {
                Show-ChatProviders
                Write-Host "Current: $Provider" -ForegroundColor Cyan
                $newProvider = Read-Host "Enter provider name (or press Enter to keep current)"
                if ($newProvider -and $global:ChatProviders.ContainsKey($newProvider)) {
                    $Provider = $newProvider
                    $providerConfig = $global:ChatProviders[$Provider]
                    $Model = $providerConfig.DefaultModel
                    Write-Host "Switched to $($providerConfig.Name) ($Model)" -ForegroundColor Green
                }
                continue
            }
            '^model\s+(.+)$' {
                $Model = $Matches[1]
                Write-Host "Model changed to: $Model" -ForegroundColor Green
                continue
            }
            '^folder$' {
                Invoke-FolderContextUpdate -IncludeGitStatus
                continue
            }
            '^folder\s+--preview$' {
                Show-FolderContext -IncludeGitStatus
                continue
            }
            '^folder\s+(.+)$' {
                $folderPath = $Matches[1]
                if (Test-Path $folderPath) {
                    Invoke-FolderContextUpdate -Path (Resolve-Path $folderPath).Path -IncludeGitStatus
                }
                else {
                    Write-Host "Path not found: $folderPath" -ForegroundColor Yellow
                }
                continue
            }
            '^(vision|/vision)\s+--full\s+(.+)$' {
                # vision --full <path or prompt>
                $visionArg = $Matches[2]
                if (Get-Command Send-ImageToAI -ErrorAction SilentlyContinue) {
                    if (Test-Path $visionArg) {
                        Write-Host '[Vision] Analyzing image at full resolution...' -ForegroundColor Cyan
                        $vResult = Send-ImageToAI -ImagePath $visionArg -FullResolution -Provider $Provider -Model $Model
                    }
                    else {
                        Write-Host '[Vision] Capturing screenshot at full resolution...' -ForegroundColor Cyan
                        $cap = Capture-Screenshot -FullResolution
                        if ($cap.Success) {
                            $vResult = Send-ImageToAI -ImagePath $cap.Path -Prompt $visionArg -FullResolution -Provider $Provider -Model $Model
                            Remove-Item $cap.Path -Force -ErrorAction SilentlyContinue
                        }
                        else {
                            Write-Host "  $($cap.Output)" -ForegroundColor Red
                            continue
                        }
                    }
                    if ($vResult.Success) {
                        $global:ChatSessionHistory += @{ role = 'user'; content = '[Vision: image analyzed at full resolution]' }
                        $global:ChatSessionHistory += @{ role = 'assistant'; content = $vResult.Output }
                        Write-Host "`nAI>" -ForegroundColor Cyan
                        if (Get-Command Format-Markdown -ErrorAction SilentlyContinue) { Format-Markdown $vResult.Output } else { Write-Host $vResult.Output }
                    }
                    else { Write-Host "  $($vResult.Output)" -ForegroundColor Red }
                }
                else { Write-Host 'VisionTools module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(vision|/vision)\s+--full$' {
                # vision --full (screenshot at full res)
                if (Get-Command Capture-Screenshot -ErrorAction SilentlyContinue) {
                    Write-Host '[Vision] Capturing screenshot at full resolution...' -ForegroundColor Cyan
                    $cap = Capture-Screenshot -FullResolution
                    if ($cap.Success) {
                        $vResult = Send-ImageToAI -ImagePath $cap.Path -FullResolution -Provider $Provider -Model $Model
                        Remove-Item $cap.Path -Force -ErrorAction SilentlyContinue
                        if ($vResult.Success) {
                            $global:ChatSessionHistory += @{ role = 'user'; content = '[Vision: screenshot analyzed at full resolution]' }
                            $global:ChatSessionHistory += @{ role = 'assistant'; content = $vResult.Output }
                            Write-Host "`nAI>" -ForegroundColor Cyan
                            if (Get-Command Format-Markdown -ErrorAction SilentlyContinue) { Format-Markdown $vResult.Output } else { Write-Host $vResult.Output }
                        }
                        else { Write-Host "  $($vResult.Output)" -ForegroundColor Red }
                    }
                    else { Write-Host "  $($cap.Output)" -ForegroundColor Red }
                }
                else { Write-Host 'VisionTools module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(vision|/vision)\s+(.+)$' {
                # vision <path> or vision <prompt>
                $visionArg = $Matches[2]
                if (Get-Command Send-ImageToAI -ErrorAction SilentlyContinue) {
                    if (Test-Path $visionArg) {
                        Write-Host "[Vision] Analyzing: $visionArg" -ForegroundColor Cyan
                        $vResult = Send-ImageToAI -ImagePath $visionArg -Provider $Provider -Model $Model
                    }
                    else {
                        # Treat as prompt for screenshot
                        Write-Host '[Vision] Capturing screenshot...' -ForegroundColor Cyan
                        $cap = Capture-Screenshot
                        if ($cap.Success) {
                            $vResult = Send-ImageToAI -ImagePath $cap.Path -Prompt $visionArg -Provider $Provider -Model $Model
                            Remove-Item $cap.Path -Force -ErrorAction SilentlyContinue
                        }
                        else {
                            Write-Host "  $($cap.Output)" -ForegroundColor Red
                            continue
                        }
                    }
                    if ($vResult.Success) {
                        $placeholder = if (Test-Path $visionArg) { "[Vision: analyzed $visionArg]" } else { "[Vision: screenshot -- $visionArg]" }
                        $global:ChatSessionHistory += @{ role = 'user'; content = $placeholder }
                        $global:ChatSessionHistory += @{ role = 'assistant'; content = $vResult.Output }
                        Write-Host "`nAI>" -ForegroundColor Cyan
                        if (Get-Command Format-Markdown -ErrorAction SilentlyContinue) { Format-Markdown $vResult.Output } else { Write-Host $vResult.Output }
                    }
                    else { Write-Host "  $($vResult.Output)" -ForegroundColor Red }
                }
                else { Write-Host 'VisionTools module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(vision|/vision)$' {
                # Plain vision -- screenshot + describe
                if (Get-Command Capture-Screenshot -ErrorAction SilentlyContinue) {
                    Write-Host '[Vision] Capturing screenshot...' -ForegroundColor Cyan
                    $cap = Capture-Screenshot
                    if ($cap.Success) {
                        Write-Host "  Captured $($cap.Width)x$($cap.Height)" -ForegroundColor DarkGray
                        $vResult = Send-ImageToAI -ImagePath $cap.Path -Provider $Provider -Model $Model
                        Remove-Item $cap.Path -Force -ErrorAction SilentlyContinue
                        if ($vResult.Success) {
                            $global:ChatSessionHistory += @{ role = 'user'; content = '[Vision: screenshot analyzed]' }
                            $global:ChatSessionHistory += @{ role = 'assistant'; content = $vResult.Output }
                            Write-Host "`nAI>" -ForegroundColor Cyan
                            if (Get-Command Format-Markdown -ErrorAction SilentlyContinue) { Format-Markdown $vResult.Output } else { Write-Host $vResult.Output }
                        }
                        else { Write-Host "  $($vResult.Output)" -ForegroundColor Red }
                    }
                    else { Write-Host "  $($cap.Output)" -ForegroundColor Red }
                }
                else { Write-Host 'VisionTools module not loaded.' -ForegroundColor Red }
                continue
            }
            '^(agent|/agent)\s+(.+)$' {
                $agentTask = $Matches[2]
                if (Get-Command Invoke-AgentTask -ErrorAction SilentlyContinue) {
                    $agentResult = Invoke-AgentTask -Task $agentTask -Provider $Provider -Model $Model -AutoConfirm
                    if ($agentResult) {
                        $global:ChatSessionHistory += @{ role = "user"; content = "[Agent task: $agentTask]" }
                        $global:ChatSessionHistory += @{ role = "assistant"; content = $agentResult.Summary }
                    }
                }
                else {
                    Write-Host "Agent module not loaded." -ForegroundColor Red
                }
                continue
            }
            '^(/agent)$' {
                if (Get-Command Invoke-AgentTask -ErrorAction SilentlyContinue) {
                    Write-Host "Enter task for interactive agent (or 'cancel'):" -ForegroundColor Magenta
                    Write-Host -NoNewline "  Task> " -ForegroundColor Yellow
                    $agentTask = Read-Host
                    if ($agentTask -and $agentTask -notin @('cancel', '')) {
                        $agentResult = Invoke-AgentTask -Task $agentTask -Provider $Provider -Model $Model -AutoConfirm -Interactive
                        if ($agentResult) {
                            $global:ChatSessionHistory += @{ role = "user"; content = "[Interactive agent session: $agentTask]" }
                            $global:ChatSessionHistory += @{ role = "assistant"; content = $agentResult.Summary }
                        }
                    }
                }
                else {
                    Write-Host "Agent module not loaded." -ForegroundColor Red
                }
                continue
            }
            '^/tools$' {
                if (Get-Command Get-AgentTools -ErrorAction SilentlyContinue) {
                    Get-AgentTools
                }
                else {
                    Write-Host "Agent tools not loaded." -ForegroundColor Red
                }
                continue
            }
            '^/steps$' {
                if (Get-Command Show-AgentSteps -ErrorAction SilentlyContinue) {
                    Show-AgentSteps
                }
                else {
                    Write-Host "Agent module not loaded." -ForegroundColor Red
                }
                continue
            }
            '^/memory$' {
                if (Get-Command Show-AgentMemory -ErrorAction SilentlyContinue) {
                    Show-AgentMemory
                }
                else {
                    Write-Host "Agent module not loaded." -ForegroundColor Red
                }
                continue
            }
            '^/plan$' {
                if (Get-Command Show-AgentPlan -ErrorAction SilentlyContinue) {
                    Show-AgentPlan
                }
                else {
                    Write-Host "Agent module not loaded." -ForegroundColor Red
                }
                continue
            }
            '^\s*$' { continue }
        }

        # Check for artifact commands (code, save <#>, run <#>, save-all)
        if (Get-Command Invoke-ArtifactFromChat -ErrorAction SilentlyContinue) {
            if (Invoke-ArtifactFromChat -InputText $inputText) { continue }
        }

        if (-not $continue) { break }

        # Don't preprocess user input - let the AI interpret naturally
        $global:ChatSessionHistory += @{ role = "user"; content = $inputText }
        
        $estimatedTokens = Get-EstimatedTokenCount
        $contextLimit = Get-ModelContextLimit -Model $Model
        $budget = $contextLimit - $MaxResponseTokens
        
        # Auto-trim context if enabled and approaching limit
        if ($AutoTrim -and $estimatedTokens -gt ($budget * 0.8)) {
            $trimResult = Get-TrimmedMessages -Messages $global:ChatSessionHistory -ContextLimit $contextLimit -MaxResponseTokens $MaxResponseTokens -KeepFirstN 2 -Summarize
            if ($trimResult.Trimmed) {
                $global:ChatSessionHistory = $trimResult.Messages
                Write-Host "  [Auto-trimmed: $($trimResult.RemovedCount) old messages summarized, ~$($trimResult.EstimatedTokens)/$budget tokens]" -ForegroundColor DarkYellow
                $estimatedTokens = $trimResult.EstimatedTokens
            }
        }
        elseif ($estimatedTokens -gt ($budget * 0.8)) {
            $pct = [math]::Round(($estimatedTokens / $budget) * 100)
            Write-Host "  Context $pct% full (~$estimatedTokens/$budget tokens). Use 'budget' for details or 'clear' to reset." -ForegroundColor Yellow
        }

        # Prepare messages for API call
        $messagesToSend = $global:ChatSessionHistory

        try {
            # Show thinking indicator (not for streaming - it prints directly)
            if (-not $Stream) {
                Write-Host "`n:<) Thinking..." -ForegroundColor DarkGray
            }
            else {
                Write-Host "`nAI> " -ForegroundColor Cyan -NoNewline
            }
            
            # Use unified chat completion with optional streaming
            $response = Invoke-ChatCompletion -Messages $messagesToSend -Provider $Provider -Model $Model -Temperature $Temperature -MaxTokens $MaxResponseTokens -SystemPrompt $systemPrompt -Stream:$Stream
            
            $reply = $response.Content

            # Store AI response as-is
            $global:ChatSessionHistory += @{ role = "assistant"; content = $reply }

            # Only show formatted output if not streaming (streaming already printed)
            if (-not $response.Streamed) {
                Write-Host "`nAI>" -ForegroundColor Cyan
                $parsedReply = Convert-JsonIntent $reply
                Format-Markdown $parsedReply
            }
            else {
                # For streamed responses, still process intents/commands
                $parsedReply = Convert-JsonIntent $reply
            }
            
            # Detect and track code artifacts in the response
            if (Get-Command Register-ArtifactsFromResponse -ErrorAction SilentlyContinue) {
                Register-ArtifactsFromResponse -ResponseText $reply
            }

            # Show token usage if available
            if ($response.Usage) {
                $totalTokens = $response.Usage.total_tokens
                if ($totalTokens) {
                    Write-Host "`n[Tokens: $totalTokens]" -ForegroundColor DarkGray
                }
            }
        }
        catch {
            Write-Host "`nERROR: Request failed" -ForegroundColor Red
            Write-Host "$($_.Exception.Message)" -ForegroundColor Yellow
            
            # Remove the failed user message from history
            if ($global:ChatSessionHistory.Count -gt 0) {
                $global:ChatSessionHistory = $global:ChatSessionHistory[0..($global:ChatSessionHistory.Count - 2)]
            }
        }
    }
}

# ===== Persistence Helpers =====

function Initialize-ChatLogs {
    if (-not (Test-Path $global:ChatLogsPath)) {
        New-Item -ItemType Directory -Path $global:ChatLogsPath -Force | Out-Null
    }
}

function Get-ChatIndexPath { Join-Path $global:ChatLogsPath "index.json" }

function Read-ChatIndex {
    $indexPath = Get-ChatIndexPath
    if (Test-Path $indexPath) {
        try { return Get-Content $indexPath -Raw | ConvertFrom-Json -AsHashtable } catch {}
    }
    return @{}
}

function Write-ChatIndex {
    param([hashtable]$Index)
    $Index | ConvertTo-Json -Depth 3 | Set-Content (Get-ChatIndexPath) -Encoding UTF8
}

function Save-Chat {
    <#
    .SYNOPSIS
    Save current chat session to file. Use -Name for a named session, -Auto for silent auto-save.
    #>
    param(
        [string]$Name,
        [switch]$Auto   # Silent save, no user prompt output
    )
    
    if ($global:ChatSessionHistory.Count -eq 0) {
        if (-not $Auto) { Write-Host "Nothing to save." -ForegroundColor Yellow }
        return
    }
    
    Initialize-ChatLogs
    
    # Determine session name
    if ($Name) {
        $global:ChatSessionName = $Name
    }
    elseif (-not $global:ChatSessionName) {
        # Generate a name from the first user message
        $firstMsg = ($global:ChatSessionHistory | Where-Object { $_.role -eq 'user' } | Select-Object -First 1).content
        if ($firstMsg) {
            # Truncate and sanitify for filename
            $slug = ($firstMsg -replace '[^a-zA-Z0-9 ]', '' -replace '\s+', '-').Trim('-')
            if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd('-') }
            $global:ChatSessionName = $slug
        }
        else {
            $global:ChatSessionName = "session"
        }
    }
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeSlug = $global:ChatSessionName -replace '[^a-zA-Z0-9_-]', '_'
    $filename = "${safeSlug}_${timestamp}.json"
    $filePath = Join-Path $global:ChatLogsPath $filename
    
    # Build session envelope
    $session = @{
        name         = $global:ChatSessionName
        savedAt      = (Get-Date -Format 'o')
        provider     = $global:DefaultChatProvider
        messages     = $global:ChatSessionHistory
        messageCount = $global:ChatSessionHistory.Count
    }
    
    $session | ConvertTo-Json -Depth 10 | Set-Content $filePath -Encoding UTF8
    
    # Update index (JSON fallback)
    $index = Read-ChatIndex
    $index[$global:ChatSessionName] = @{
        file     = $filename
        savedAt  = $session.savedAt
        messages = $session.messageCount
        preview  = ($global:ChatSessionHistory | Where-Object { $_.role -eq 'user' } | Select-Object -First 1).content
    }
    Write-ChatIndex $index
    
    # Save to SQLite (primary storage)
    if ($global:ChatDbReady -and (Get-Command Save-ChatToDb -ErrorAction SilentlyContinue)) {
        Save-ChatToDb -Name $global:ChatSessionName -Messages $global:ChatSessionHistory -Provider $global:DefaultChatProvider -Model $session.model | Out-Null
    }
    
    # Prune logs older than 30 days
    Get-ChildItem $global:ChatLogsPath -Filter "*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'index.json' -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
    
    if (-not $Auto) {
        Write-Host "Saved session '$($global:ChatSessionName)' ($($global:ChatSessionHistory.Count) messages)" -ForegroundColor Green
        if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
            Send-ShелixToast -Title "Session saved" -Message "'$($global:ChatSessionName)' -- $($global:ChatSessionHistory.Count) messages" -Type Info
        }
    }
    else {
        # Auto-save on exit -- toast so the user knows context was preserved
        if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
            Send-ShелixToast -Title "Session auto-saved" -Message "'$($global:ChatSessionName)' -- $($global:ChatSessionHistory.Count) messages" -Type Info
        }
    }
    
    return $filePath
}

function Resume-Chat {
    <#
    .SYNOPSIS
    Load the most recent saved session, or a named session. Returns session metadata.
    Tries SQLite first, falls back to JSON index.
    #>
    param([string]$Name)
    
    # Try SQLite first
    if ($global:ChatDbReady -and (Get-Command Resume-ChatFromDb -ErrorAction SilentlyContinue)) {
        $dbSession = Resume-ChatFromDb -Name $Name
        if ($dbSession) {
            $global:ChatSessionHistory = @($dbSession.Messages)
            $global:ChatSessionName = $dbSession.Name
            return @{
                name     = $dbSession.Name
                messages = $dbSession.Messages.Count
                source   = 'sqlite'
            }
        }
        # If Name was provided and not found in DB, try partial match
        if ($Name) {
            $dbSessions = Get-ChatSessionsFromDb -NameFilter $Name -Limit 1
            if ($dbSessions.Count -gt 0) {
                $dbSession = Resume-ChatFromDb -Name $dbSessions[0].Name
                if ($dbSession) {
                    $global:ChatSessionHistory = @($dbSession.Messages)
                    $global:ChatSessionName = $dbSession.Name
                    return @{
                        name     = $dbSession.Name
                        messages = $dbSession.Messages.Count
                        source   = 'sqlite'
                    }
                }
            }
        }
        # If no name given, get most recent from DB
        if (-not $Name) {
            $dbSessions = Get-ChatSessionsFromDb -Limit 1
            if ($dbSessions.Count -gt 0) {
                $dbSession = Resume-ChatFromDb -Name $dbSessions[0].Name
                if ($dbSession) {
                    $global:ChatSessionHistory = @($dbSession.Messages)
                    $global:ChatSessionName = $dbSession.Name
                    return @{
                        name     = $dbSession.Name
                        messages = $dbSession.Messages.Count
                        source   = 'sqlite'
                    }
                }
            }
        }
    }

    # JSON fallback
    Initialize-ChatLogs
    $index = Read-ChatIndex
    
    if ($index.Count -eq 0) {
        Write-Host "No saved sessions found." -ForegroundColor Yellow
        return $null
    }
    
    # Find target session
    $entry = $null
    if ($Name) {
        # Exact match first, then partial
        if ($index.ContainsKey($Name)) {
            $entry = $index[$Name]
            $entry['name'] = $Name
        }
        else {
            $match = $index.Keys | Where-Object { $_ -like "*$Name*" } | Select-Object -First 1
            if ($match) { $entry = $index[$match]; $entry['name'] = $match }
        }
        if (-not $entry) {
            Write-Host "Session '$Name' not found. Use 'sessions' to list." -ForegroundColor Yellow
            return $null
        }
    }
    else {
        # Most recently saved
        $latest = $index.Keys | Sort-Object { $index[$_].savedAt } -Descending | Select-Object -First 1
        $entry = $index[$latest]
        $entry['name'] = $latest
    }
    
    $filePath = Join-Path $global:ChatLogsPath $entry.file
    if (-not (Test-Path $filePath)) {
        Write-Host "Session file missing: $($entry.file)" -ForegroundColor Red
        return $null
    }
    
    $session = Get-Content $filePath -Raw | ConvertFrom-Json
    $global:ChatSessionHistory = @($session.messages)
    $global:ChatSessionName = $entry.name
    
    return $entry
}

function Get-ChatSessions {
    <#
    .SYNOPSIS
    List all saved chat sessions with preview of first message.
    Uses SQLite if available, otherwise falls back to JSON index.
    #>

    # Try SQLite first
    if ($global:ChatDbReady -and (Get-Command Get-ChatSessionsFromDb -ErrorAction SilentlyContinue)) {
        $dbSessions = Get-ChatSessionsFromDb -Limit 50
        if ($dbSessions.Count -gt 0) {
            Write-Host "`n===== Saved Sessions (SQLite) =====" -ForegroundColor Cyan
            foreach ($s in $dbSessions) {
                $date = try { [datetime]::Parse($s.UpdatedAt).ToString('MMM dd HH:mm') } catch { $s.UpdatedAt }
                Write-Host "  $($s.Name) " -ForegroundColor Yellow -NoNewline
                Write-Host "[$($s.MessageCount) msgs, $date]" -ForegroundColor DarkGray
            }
            Write-Host ""
            Write-Host '  resume <name>  to load a session' -ForegroundColor DarkGray
            Write-Host ""
            return
        }
    }

    # JSON fallback
    Initialize-ChatLogs
    $index = Read-ChatIndex
    
    if ($index.Count -eq 0) {
        Write-Host "No saved sessions." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n===== Saved Sessions =====" -ForegroundColor Cyan
    $index.Keys | Sort-Object { $index[$_].savedAt } -Descending | ForEach-Object {
        $e = $index[$_]
        $date = [datetime]::Parse($e.savedAt).ToString('MMM dd HH:mm')
        $preview = if ($e.preview) { 
            $p = $e.preview -replace '\s+', ' '
            if ($p.Length -gt 60) { $p.Substring(0, 60) + '...' } else { $p }
        }
        else { '(no preview)' }
        Write-Host "  $_ " -ForegroundColor Yellow -NoNewline
        $msgCount = $e.messages
        Write-Host ('[' + "$msgCount msgs, $date" + ']') -ForegroundColor DarkGray
        Write-Host "    $preview" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host '  resume <name>  to load a session' -ForegroundColor DarkGray
    Write-Host ""
}

function Import-Chat {
    <#
    .SYNOPSIS
    Load a saved chat session by file path (legacy/direct access).
    #>
    param([Parameter(Mandatory = $true)][string]$file)
    if (Test-Path $file) {
        $raw = Get-Content $file -Raw | ConvertFrom-Json
        # Support both old format (array) and new envelope format
        if ($raw.messages) {
            $global:ChatSessionHistory = @($raw.messages)
            $global:ChatSessionName = $raw.name
        }
        else {
            $global:ChatSessionHistory = @($raw)
        }
        Write-Host "Chat loaded: $file ($($global:ChatSessionHistory.Count) messages)" -ForegroundColor Cyan
    }
    else {
        Write-Host "File not found: $file" -ForegroundColor Red
    }
}

function Get-ChatHistory {
    <#
    .SYNOPSIS
    List saved chat sessions (alias for Get-ChatSessions, kept for compatibility).
    #>
    Get-ChatSessions
}

function Get-SessionSummary {
    <#
    .SYNOPSIS
    Generate a compact summary of the current session for context injection.
    Local heuristic -- no LLM call, fast and free.
    #>
    param(
        [array]$Messages = $global:ChatSessionHistory,
        [int]$MaxLength = 500
    )
    
    $userMessages = $Messages | Where-Object { $_.role -eq 'user' }
    if (-not $userMessages -or $userMessages.Count -eq 0) { return '(empty session)' }
    
    $lines = @()
    foreach ($msg in $userMessages) {
        $text = ($msg.content -replace '\s+', ' ').Trim()
        if ($text.Length -gt 100) { $text = $text.Substring(0, 100) + '...' }
        $lines += "- $text"
    }
    
    $summary = $lines -join "`n"
    if ($summary.Length -gt $MaxLength) {
        $summary = $summary.Substring(0, $MaxLength) + "`n... (truncated)"
    }
    return $summary
}

function Search-ChatSessions {
    <#
    .SYNOPSIS
    Search across all saved sessions by keyword. Uses FTS5 if SQLite is available.
    #>
    param([Parameter(Mandatory = $true)][string]$Keyword)
    
    # Try FTS5 search first
    if ($global:ChatDbReady -and (Get-Command Search-ChatFTS -ErrorAction SilentlyContinue)) {
        $results = Search-ChatFTS -Query $Keyword -Limit 20
        if ($results.Count -gt 0) {
            Write-Host "`nFTS5 search results for '$Keyword':" -ForegroundColor Cyan
            $currentSession = ''
            foreach ($r in $results) {
                if ($r.SessionName -ne $currentSession) {
                    $currentSession = $r.SessionName
                    Write-Host "`n  $($r.SessionName)" -ForegroundColor Yellow
                }
                $roleColor = if ($r.Role -eq 'user') { 'Gray' } else { 'DarkCyan' }
                Write-Host "    [$($r.Role)] $($r.Snippet)" -ForegroundColor $roleColor
            }
            Write-Host ""
            return
        }
        # If FTS5 returned nothing, it means no match -- don't fall through to JSON
        Write-Host "No sessions matching '$Keyword'." -ForegroundColor Yellow
        return
    }

    # JSON fallback
    Initialize-ChatLogs
    $index = Read-ChatIndex
    $found = @()
    
    # First pass: search index previews and names
    foreach ($name in $index.Keys) {
        $entry = $index[$name]
        if ($name -like "*$Keyword*" -or ($entry.preview -and $entry.preview -like "*$Keyword*")) {
            $found += @{ Name = $name; Source = 'index'; Preview = $entry.preview; Date = $entry.savedAt; Messages = $entry.messages }
        }
    }
    
    # Second pass: deep search into session files for sessions not already matched
    $matchedNames = $found | ForEach-Object { $_.Name }
    foreach ($name in $index.Keys) {
        if ($name -in $matchedNames) { continue }
        $filePath = Join-Path $global:ChatLogsPath $index[$name].file
        if (-not (Test-Path $filePath)) { continue }
        try {
            $content = Get-Content $filePath -Raw
            if ($content -like "*$Keyword*") {
                $found += @{ Name = $name; Source = 'content'; Preview = $index[$name].preview; Date = $index[$name].savedAt; Messages = $index[$name].messages }
            }
        }
        catch {}
    }
    
    if ($found.Count -eq 0) {
        Write-Host "No sessions matching '$Keyword'." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`nSearch results for '$Keyword':" -ForegroundColor Cyan
    foreach ($r in $found) {
        $date = [datetime]::Parse($r.Date).ToString('MMM dd HH:mm')
        Write-Host "  $($r.Name) " -ForegroundColor Yellow -NoNewline
        Write-Host "[$($r.Messages) msgs, $date]" -ForegroundColor DarkGray
        if ($r.Preview) {
            $p = $r.Preview -replace '\s+', ' '
            if ($p.Length -gt 60) { $p = $p.Substring(0, 60) + '...' }
            Write-Host "    $p" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

function Remove-ChatSession {
    <#
    .SYNOPSIS
    Remove a saved session from SQLite and/or JSON index.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)
    
    $removed = $false

    # Remove from SQLite
    if ($global:ChatDbReady -and (Get-Command Remove-ChatSessionFromDb -ErrorAction SilentlyContinue)) {
        if (Remove-ChatSessionFromDb -Name $Name) { $removed = $true }
    }

    # Remove from JSON index
    Initialize-ChatLogs
    $index = Read-ChatIndex
    if ($index.ContainsKey($Name)) {
        $entry = $index[$Name]
        $filePath = Join-Path $global:ChatLogsPath $entry.file
        if (Test-Path $filePath) { Remove-Item $filePath -Force }
        $index.Remove($Name)
        Write-ChatIndex $index
        $removed = $true
    }

    if ($removed) {
        Write-Host "Deleted session: $Name" -ForegroundColor Green
    }
    else {
        Write-Host "Session '$Name' not found." -ForegroundColor Yellow
    }
}

function Export-ChatSession {
    <#
    .SYNOPSIS
    Export a session to formatted markdown. Defaults to current session.
    #>
    param([string]$Name)
    
    $messages = $null
    $sessionName = $null
    
    if ($Name) {
        # Load named session
        $index = Read-ChatIndex
        if (-not $index.ContainsKey($Name)) {
            Write-Host "Session '$Name' not found." -ForegroundColor Yellow
            return
        }
        $filePath = Join-Path $global:ChatLogsPath $index[$Name].file
        if (-not (Test-Path $filePath)) {
            Write-Host "Session file missing." -ForegroundColor Red
            return
        }
        $session = Get-Content $filePath -Raw | ConvertFrom-Json
        $messages = $session.messages
        $sessionName = $Name
    }
    else {
        if ($global:ChatSessionHistory.Count -eq 0) {
            Write-Host "No active session to export." -ForegroundColor Yellow
            return
        }
        $messages = $global:ChatSessionHistory
        $sessionName = if ($global:ChatSessionName) { $global:ChatSessionName } else { 'session' }
    }
    
    Initialize-ChatLogs
    $exportPath = Join-Path $global:ChatLogsPath "$sessionName.md"
    
    $md = @("# Chat Session: $sessionName", "", "Exported: $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "", "---", "")
    
    foreach ($msg in $messages) {
        $role = if ($msg.role -eq 'user') { '**You**' } elseif ($msg.role -eq 'assistant') { '**AI**' } else { "**$($msg.role)**" }
        $md += $role
        $md += ""
        $md += $msg.content
        $md += ""
        $md += "---"
        $md += ""
    }
    
    $md -join "`n" | Set-Content $exportPath -Encoding UTF8
    Write-Host "Exported to: $exportPath" -ForegroundColor Green
}

# ===== Chat Shortcut Functions =====
function chat {
    <#
    .SYNOPSIS
    Start a chat session with optional provider selection
    .EXAMPLE
    chat                    # Fresh session
    chat -Resume            # Continue last session
    chat -Continue          # Continue with context recall
    chat -FolderAware       # Include current directory context
    chat -r -f              # Resume + folder aware
    chat -p anthropic -m claude-sonnet-4-5-20250929
    #>
    param(
        [Alias("p")]
        [ValidateSet('ollama', 'anthropic', 'lmstudio', 'openai', 'llm')]
        [string]$Provider = $global:DefaultChatProvider,
        
        [Alias("m")]
        [string]$Model,
        
        [switch]$Stream,
        [switch]$AutoTrim,
        [Alias("r")]
        [switch]$Resume,
        [Alias("c")]
        [switch]$Continue,
        [Alias("f")]
        [switch]$FolderAware
    )
    
    $params = @{
        Provider            = $Provider
        IncludeSafeCommands = $true
        Stream              = $Stream
        AutoTrim            = $AutoTrim
        Resume              = $Resume
        Continue            = $Continue
        FolderAware         = $FolderAware
    }
    if ($Model) { $params.Model = $Model }
    
    Start-ChatSession @params
}

function Start-ChatOllama { Start-ChatSession -Provider ollama -IncludeSafeCommands -Stream -AutoTrim }
function Start-ChatAnthropic { Start-ChatSession -Provider anthropic -IncludeSafeCommands -AutoTrim }
function Start-ChatLocal { Start-ChatSession -Provider lmstudio -IncludeSafeCommands -Stream -AutoTrim }
function Start-ChatLLM { Start-ChatSession -Provider llm -IncludeSafeCommands -AutoTrim }

# ===== Tab Completion =====
$_chatSessionNameCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $names = @()
    if ($global:ChatDbReady -and (Get-Command Get-ChatSessionsFromDb -ErrorAction SilentlyContinue)) {
        $names = @(Get-ChatSessionsFromDb -Limit 50 | ForEach-Object { $_.Name })
    }
    if ($names.Count -eq 0) {
        $idx = Read-ChatIndex
        $names = @($idx.Keys)
    }
    $names | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new("'$_'", $_, 'ParameterValue', "Session: $_")
    }
}

Register-ArgumentCompleter -CommandName Resume-Chat        -ParameterName Name -ScriptBlock $_chatSessionNameCompleter
Register-ArgumentCompleter -CommandName Remove-ChatSession -ParameterName Name -ScriptBlock $_chatSessionNameCompleter
Register-ArgumentCompleter -CommandName Export-ChatSession -ParameterName Name -ScriptBlock $_chatSessionNameCompleter

$_chatProviderCompleter2 = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:ChatProviders.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        $desc = $global:ChatProviders[$_].Name
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
    }
}

Register-ArgumentCompleter -CommandName Start-ChatSession -ParameterName Provider -ScriptBlock $_chatProviderCompleter2
Register-ArgumentCompleter -CommandName chat              -ParameterName Provider -ScriptBlock $_chatProviderCompleter2

# ===== Aliases =====
Set-Alias cc chat -Force
Set-Alias chat-ollama Start-ChatOllama -Force
Set-Alias chat-anthropic Start-ChatAnthropic -Force
Set-Alias chat-local Start-ChatLocal -Force
Set-Alias chat-llm Start-ChatLLM -Force

# ===== SQLite Storage Layer =====
# Active: ChatStorage.ps1 provides SQLite + FTS5 persistence.
# JSON files maintained as fallback and for backward compatibility.

Write-Verbose "ChatSession loaded: Start-ChatSession, chat, Save-Chat, Resume-Chat, Get-ChatSessions, Search-ChatSessions, Export-ChatSession"
