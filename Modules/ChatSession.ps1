# ===== ChatSession.ps1 =====
# LLM Chat session management, persistence, and the main chat loop

# ===== Chat Session State =====
$global:ChatSessionHistory = @()

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
        [switch]$AutoTrim
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
    Write-Host "Type 'exit' to quit, 'clear' to reset, 'save' to archive, 'tokens' for usage, 'switch' to change provider." -ForegroundColor DarkGray
    
    # Clear history and initialize with safe commands context if requested
    $global:ChatSessionHistory = @()
    $systemPrompt = $null
    
    if ($IncludeSafeCommands) {
        $safeCommandsPrompt = Get-SafeCommandsPrompt
        
        # Anthropic handles system prompts differently
        if ($Provider -eq 'anthropic') {
            $systemPrompt = $safeCommandsPrompt
        } else {
            # For OpenAI-compatible APIs, add as user message with acknowledgment
            $global:ChatSessionHistory += @{ role = "user"; content = $safeCommandsPrompt }
            $global:ChatSessionHistory += @{ role = "assistant"; content = "Understood. I have access to PowerShell commands and intent actions. I'm ready to help." }
        }
        Write-Host "Safe commands context loaded." -ForegroundColor Green
    }
    Write-Host ""

    $continue = $true
    while ($continue) {
        Write-Host -NoNewline "`nYou> " -ForegroundColor Yellow
        $inputText = Read-Host

        switch -Regex ($inputText) {
            '^exit$'   { 
                Write-Host "`nSession ended." -ForegroundColor Green
                $continue = $false
                break
            }
            '^clear$'  { 
                $global:ChatSessionHistory = @()
                Write-Host "Memory cleared." -ForegroundColor DarkGray
                continue 
            }
            '^save$'   { 
                Save-Chat
                continue 
            }
            '^tokens$' { 
                $est = Get-EstimatedTokenCount
                Write-Host "Estimated tokens in context: $est / $MaxTokens" -ForegroundColor Cyan
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
            '^\s*$'    { continue }
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
        } elseif ($estimatedTokens -gt ($MaxTokens * 0.8)) {
            Write-Host "  Approaching token limit ($estimatedTokens / $MaxTokens). Consider using 'clear' to reset." -ForegroundColor Yellow
        }

        # Prepare messages for API call
        $messagesToSend = $global:ChatSessionHistory

        try {
            # Show thinking indicator (not for streaming - it prints directly)
            if (-not $Stream) {
                Write-Host "`n:<) Thinking..." -ForegroundColor DarkGray
            } else {
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
            } else {
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
function Save-Chat {
    <#
    .SYNOPSIS
    Save current chat session to file
    #>
    $path = "$env:USERPROFILE\Documents\ChatLogs"
    if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
    Get-ChildItem $path -Filter "*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force
    $file = "$path\Chat_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $jsonContent = $global:ChatSessionHistory | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($file, $jsonContent, [System.Text.Encoding]::UTF8)
    Write-Host "Chat saved to $file" -ForegroundColor Green
}

function Import-Chat {
    <#
    .SYNOPSIS
    Load a saved chat session
    #>
    param([Parameter(Mandatory=$true)][string]$file)
    if (Test-Path $file) {
        $global:ChatSessionHistory = Get-Content $file -Raw | ConvertFrom-Json
        Write-Host "Chat history loaded: $file" -ForegroundColor Cyan
    } else {
        Write-Host "File not found: $file" -ForegroundColor Red
    }
}

function Get-ChatHistory {
    <#
    .SYNOPSIS
    List saved chat sessions
    #>
    $path = "$env:USERPROFILE\Documents\ChatLogs"
    if (Test-Path $path) {
        Get-ChildItem $path -Filter "*.json" | Sort-Object LastWriteTime -Descending | 
        Select-Object Name, LastWriteTime | Format-Table -AutoSize
    } else {
        Write-Host "No chat logs directory found" -ForegroundColor Yellow
    }
}

# ===== Chat Shortcut Functions =====
function chat {
    <#
    .SYNOPSIS
    Start a chat session with optional provider selection
    #>
    param(
        [Alias("p")]
        [ValidateSet('ollama', 'anthropic', 'lmstudio', 'openai', 'llm')]
        [string]$Provider = $global:DefaultChatProvider,
        
        [Alias("m")]
        [string]$Model,
        
        [switch]$Stream,
        [switch]$AutoTrim
    )
    
    $params = @{
        Provider = $Provider
        IncludeSafeCommands = $true
        Stream = $Stream
        AutoTrim = $AutoTrim
    }
    if ($Model) { $params.Model = $Model }
    
    Start-ChatSession @params
}

function chat-ollama { Start-ChatSession -Provider ollama -IncludeSafeCommands -Stream -AutoTrim }
function chat-anthropic { Start-ChatSession -Provider anthropic -IncludeSafeCommands -AutoTrim }
function chat-local { Start-ChatSession -Provider lmstudio -IncludeSafeCommands -Stream -AutoTrim }
function chat-llm { Start-ChatSession -Provider llm -IncludeSafeCommands -AutoTrim }

# ===== Aliases =====
Set-Alias cc chat -Force

Write-Verbose "ChatSession loaded: Start-ChatSession, chat, Save-Chat, Import-Chat, Get-ChatHistory"
