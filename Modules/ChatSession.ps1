# ===== ChatSession.ps1 =====
# LLM Chat session management, persistence, and the main chat loop

# ===== Chat Session State =====
$global:ChatSessionHistory = @()
$global:ChatSessionName = $null       # Current session name (null = unnamed)
$global:ChatLogsPath = "$env:USERPROFILE\Documents\ChatLogs"
$global:ChatSessionIndex = @{}        # In-memory index: name -> metadata

# ===== Chat Session Functions =====
function Start-ChatSession {
    <#
    .SYNOPSIS
    Start an interactive LLM chat session
    #>
    param(
        [ValidateSet('ollama', 'anthropic', 'lmstudio', 'openai')]
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model = $null,
        [double]$Temperature = 0.7,
        [int]$MaxTokens = 4096,
        [switch]$IncludeSafeCommands,
        [switch]$Stream,
        [switch]$AutoTrim,
        [switch]$Resume,     # Load last session into context
        [switch]$Continue    # Load last session + inject summary so model "remembers"
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
    Write-Host "Type 'exit' to quit, 'clear' to reset, 'save' to archive, 'resume' to load last session, 'sessions' to browse, 'tokens' for usage, 'switch' to change provider." -ForegroundColor DarkGray
    
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
                    Save-Chat -Name $newName
                    Write-Host "Session renamed to: $newName" -ForegroundColor Green
                }
                continue
            }
            '^tokens$' { 
                $est = Get-EstimatedTokenCount
                Write-Host "Estimated tokens in context: $est / $MaxTokens" -ForegroundColor Cyan
                continue 
            }
            '^search\s+(.+)$' {
                Search-ChatSessions -Keyword $Matches[1]
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
            '^\s*$' { continue }
        }

        if (-not $continue) { break }

        # Don't preprocess user input - let the AI interpret naturally
        $global:ChatSessionHistory += @{ role = "user"; content = $inputText }
        
        $estimatedTokens = Get-EstimatedTokenCount
        
        # Auto-trim context if enabled and approaching limit
        if ($AutoTrim -and $estimatedTokens -gt ($MaxTokens * 0.8)) {
            $trimResult = Get-TrimmedMessages -Messages $global:ChatSessionHistory -MaxTokens $MaxTokens -KeepFirstN 2
            if ($trimResult.Trimmed) {
                $global:ChatSessionHistory = $trimResult.Messages
                Write-Host "  [Auto-trimmed: removed $($trimResult.RemovedCount) old messages]" -ForegroundColor DarkYellow
                $estimatedTokens = $trimResult.EstimatedTokens
            }
        }
        elseif ($estimatedTokens -gt ($MaxTokens * 0.8)) {
            Write-Host "  Approaching token limit ($estimatedTokens / $MaxTokens). Consider using 'clear' to reset." -ForegroundColor Yellow
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
            $response = Invoke-ChatCompletion -Messages $messagesToSend -Provider $Provider -Model $Model -Temperature $Temperature -MaxTokens $MaxTokens -SystemPrompt $systemPrompt -Stream:$Stream
            
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
    
    # Update index
    $index = Read-ChatIndex
    $index[$global:ChatSessionName] = @{
        file     = $filename
        savedAt  = $session.savedAt
        messages = $session.messageCount
        preview  = ($global:ChatSessionHistory | Where-Object { $_.role -eq 'user' } | Select-Object -First 1).content
    }
    Write-ChatIndex $index
    
    # Prune logs older than 30 days
    Get-ChildItem $global:ChatLogsPath -Filter "*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'index.json' -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
    
    if (-not $Auto) {
        Write-Host "Saved session '$($global:ChatSessionName)' ($($global:ChatSessionHistory.Count) messages)" -ForegroundColor Green
    }
    
    return $filePath
}

function Resume-Chat {
    <#
    .SYNOPSIS
    Load the most recent saved session, or a named session. Returns session metadata.
    #>
    param([string]$Name)
    
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
    #>
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
        Write-Host "[$($e.messages) msgs, $date]" -ForegroundColor DarkGray
        Write-Host "    $preview" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  resume <name>  to load a session" -ForegroundColor DarkGray
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
    Local heuristic — no LLM call, fast and free.
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
    Search across all saved sessions by keyword.
    #>
    param([Parameter(Mandatory = $true)][string]$Keyword)
    
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
    Remove a saved session from index and disk.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)
    
    Initialize-ChatLogs
    $index = Read-ChatIndex
    
    if (-not $index.ContainsKey($Name)) {
        Write-Host "Session '$Name' not found." -ForegroundColor Yellow
        return
    }
    
    $entry = $index[$Name]
    $filePath = Join-Path $global:ChatLogsPath $entry.file
    
    # Remove file
    if (Test-Path $filePath) { Remove-Item $filePath -Force }
    
    # Remove from index
    $index.Remove($Name)
    Write-ChatIndex $index
    
    Write-Host "Deleted session: $Name" -ForegroundColor Green
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
        [switch]$Continue
    )
    
    $params = @{
        Provider            = $Provider
        IncludeSafeCommands = $true
        Stream              = $Stream
        AutoTrim            = $AutoTrim
        Resume              = $Resume
        Continue            = $Continue
    }
    if ($Model) { $params.Model = $Model }
    
    Start-ChatSession @params
}

function Start-ChatOllama { Start-ChatSession -Provider ollama -IncludeSafeCommands -Stream -AutoTrim }
function Start-ChatAnthropic { Start-ChatSession -Provider anthropic -IncludeSafeCommands -AutoTrim }
function Start-ChatLocal { Start-ChatSession -Provider lmstudio -IncludeSafeCommands -Stream -AutoTrim }
function Start-ChatLLM { Start-ChatSession -Provider llm -IncludeSafeCommands -AutoTrim }

# ===== Aliases =====
Set-Alias cc chat -Force
Set-Alias chat-ollama Start-ChatOllama -Force
Set-Alias chat-anthropic Start-ChatAnthropic -Force
Set-Alias chat-local Start-ChatLocal -Force
Set-Alias chat-llm Start-ChatLLM -Force

# ===== SQLite Storage Layer (Phase 3 stub) =====
# Future: Replace JSON files with SQLite for portable storage and FTS5 full-text search.
# Schema: sessions(id, name, created, updated, provider, model), messages(session_id, role, content, timestamp)
# Migration: On first run, import existing JSON sessions into SQLite.
# This enables RAG-ready conversation history — embeddings can be stored alongside messages.

Write-Verbose "ChatSession loaded: Start-ChatSession, chat, Save-Chat, Resume-Chat, Get-ChatSessions, Search-ChatSessions, Export-ChatSession"
