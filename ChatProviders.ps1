# ===== ChatProviders.ps1 =====
# Multi-provider LLM chat system supporting Ollama, Anthropic, and LM Studio
# Provides unified interface for different AI backends

# ===== Provider Configuration =====
$global:ChatProviders = @{
    'ollama' = @{
        Name = 'Ollama'
        Endpoint = 'http://localhost:11434/v1/chat/completions'
        DefaultModel = 'llama3.2'
        ApiKeyRequired = $false
        ApiKeyEnvVar = $null
        Format = 'openai'  # OpenAI-compatible API
        Description = 'Local Ollama server (OpenAI-compatible)'
    }
    'anthropic' = @{
        Name = 'Anthropic'
        Endpoint = 'https://api.anthropic.com/v1/messages'
        DefaultModel = 'claude-sonnet-4-5-20250929'
        ApiKeyRequired = $true
        ApiKeyEnvVar = 'ANTHROPIC_API_KEY'
        Format = 'anthropic'  # Anthropic Messages API
        Description = 'Anthropic Claude API (cloud)'
    }
    'lmstudio' = @{
        Name = 'LM Studio'
        Endpoint = 'http://localhost:1234/v1/chat/completions'
        DefaultModel = 'mistral-7b-instruct-v0.3'
        ApiKeyRequired = $false
        ApiKeyEnvVar = $null
        Format = 'openai'  # OpenAI-compatible API
        Description = 'Local LM Studio server'
    }
    'openai' = @{
        Name = 'OpenAI'
        Endpoint = 'https://api.openai.com/v1/chat/completions'
        DefaultModel = 'gpt-4o-mini'
        ApiKeyRequired = $true
        ApiKeyEnvVar = 'OPENAI_API_KEY'
        Format = 'openai'
        Description = 'OpenAI API (cloud)'
    }
}

# Default provider
$global:DefaultChatProvider = 'ollama'

# ===== Config File Loading =====
$global:ChatConfigPath = "$PSScriptRoot\ChatConfig.json"
$global:ChatConfig = $null

function Import-ChatConfig {
    if (Test-Path $global:ChatConfigPath) {
        try {
            $global:ChatConfig = Get-Content $global:ChatConfigPath -Raw | ConvertFrom-Json
            
            # Load API keys from config into environment (Process scope)
            if ($global:ChatConfig.apiKeys) {
                foreach ($prop in $global:ChatConfig.apiKeys.PSObject.Properties) {
                    if ($prop.Value -and $prop.Value.Length -gt 0) {
                        [Environment]::SetEnvironmentVariable($prop.Name, $prop.Value, 'Process')
                    }
                }
            }
            return $true
        } catch {
            Write-Host "Warning: Failed to load ChatConfig.json: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    return $false
}

# Load config on startup
Import-ChatConfig | Out-Null

# ===== API Key Management =====
function Get-ChatApiKey {
    param([string]$Provider)
    
    $config = $global:ChatProviders[$Provider]
    if (-not $config) {
        Write-Host "Unknown provider: $Provider" -ForegroundColor Red
        return $null
    }
    
    if (-not $config.ApiKeyRequired) {
        return $null  # No key needed
    }
    
    $envVar = $config.ApiKeyEnvVar
    
    # Check config file first (already loaded into Process env)
    $key = [Environment]::GetEnvironmentVariable($envVar)
    
    # Then check User/Machine env vars
    if (-not $key) {
        $key = [Environment]::GetEnvironmentVariable($envVar, 'User')
    }
    if (-not $key) {
        $key = [Environment]::GetEnvironmentVariable($envVar, 'Machine')
    }
    
    return $key
}

function Set-ChatApiKey {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('anthropic', 'openai')]
        [string]$Provider,
        
        [Parameter(Mandatory=$true)]
        [string]$ApiKey,
        
        [ValidateSet('User', 'Process')]
        [string]$Scope = 'User'
    )
    
    $config = $global:ChatProviders[$Provider]
    if (-not $config) {
        Write-Host "Unknown provider: $Provider" -ForegroundColor Red
        return $false
    }
    
    $envVar = $config.ApiKeyEnvVar
    
    if ($Scope -eq 'User') {
        [Environment]::SetEnvironmentVariable($envVar, $ApiKey, 'User')
        # Also set in current session
        Set-Item -Path "env:$envVar" -Value $ApiKey
        Write-Host "API key for $($config.Name) saved to user environment." -ForegroundColor Green
        Write-Host "Variable: $envVar" -ForegroundColor Gray
    } else {
        Set-Item -Path "env:$envVar" -Value $ApiKey
        Write-Host "API key for $($config.Name) set for current session only." -ForegroundColor Yellow
    }
    
    return $true
}

function Test-ChatProvider {
    param([string]$Provider = $global:DefaultChatProvider)
    
    $config = $global:ChatProviders[$Provider]
    if (-not $config) {
        Write-Host "Unknown provider: $Provider" -ForegroundColor Red
        return $false
    }
    
    Write-Host "Testing $($config.Name)..." -ForegroundColor Cyan
    
    # Check API key if required
    if ($config.ApiKeyRequired) {
        $key = Get-ChatApiKey $Provider
        if (-not $key) {
            Write-Host "  API key not found. Set it with: Set-ChatApiKey -Provider $Provider -ApiKey 'your-key'" -ForegroundColor Red
            return $false
        }
        Write-Host "  API key found" -ForegroundColor Green
    }
    
    # Test endpoint connectivity
    try {
        if ($config.Format -eq 'openai') {
            # For local servers, try a simple request
            $testBody = @{
                model = $config.DefaultModel
                messages = @(@{ role = "user"; content = "Hi" })
                max_tokens = 5
            } | ConvertTo-Json -Depth 5
            
            $headers = @{ "Content-Type" = "application/json" }
            if ($config.ApiKeyRequired) {
                $headers["Authorization"] = "Bearer $(Get-ChatApiKey $Provider)"
            }
            
            $response = Invoke-RestMethod -Uri $config.Endpoint -Method Post -Body $testBody -Headers $headers -TimeoutSec 10
            Write-Host "  Endpoint responding" -ForegroundColor Green
            Write-Host "  Model: $($config.DefaultModel)" -ForegroundColor Gray
            return $true
        }
        elseif ($config.Format -eq 'anthropic') {
            $testBody = @{
                model = $config.DefaultModel
                max_tokens = 5
                messages = @(@{ role = "user"; content = "Hi" })
            } | ConvertTo-Json -Depth 5
            
            $headers = @{
                "Content-Type" = "application/json"
                "x-api-key" = (Get-ChatApiKey $Provider)
                "anthropic-version" = "2023-06-01"
            }
            
            $response = Invoke-RestMethod -Uri $config.Endpoint -Method Post -Body $testBody -Headers $headers -TimeoutSec 10
            Write-Host "  Endpoint responding" -ForegroundColor Green
            Write-Host "  Model: $($config.DefaultModel)" -ForegroundColor Gray
            return $true
        }
    }
    catch {
        Write-Host "  Connection failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ===== Provider-Specific API Calls =====
function Invoke-OpenAICompatibleChat {
    param(
        [string]$Endpoint,
        [string]$Model,
        [array]$Messages,
        [double]$Temperature = 0.7,
        [int]$MaxTokens = 4096,
        [string]$ApiKey = $null,
        [switch]$Stream
    )
    
    $body = @{
        model = $Model
        messages = $Messages
        temperature = $Temperature
        max_tokens = $MaxTokens
    }
    
    if ($Stream) {
        $body["stream"] = $true
    }
    
    $jsonBody = $body | ConvertTo-Json -Depth 10
    
    $headers = @{ "Content-Type" = "application/json" }
    if ($ApiKey) {
        $headers["Authorization"] = "Bearer $ApiKey"
    }
    
    if ($Stream) {
        # Streaming response handling
        $fullContent = ""
        $request = [System.Net.HttpWebRequest]::Create($Endpoint)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        if ($ApiKey) {
            $request.Headers.Add("Authorization", "Bearer $ApiKey")
        }
        
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        $request.ContentLength = $bytes.Length
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bytes, 0, $bytes.Length)
        $requestStream.Close()
        
        try {
            $response = $request.GetResponse()
            $responseStream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($responseStream)
            
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($line -match '^data: (.+)$') {
                    $data = $Matches[1]
                    if ($data -eq '[DONE]') { break }
                    
                    try {
                        $chunk = $data | ConvertFrom-Json
                        if ($chunk.choices -and $chunk.choices[0].delta.content) {
                            $token = $chunk.choices[0].delta.content
                            $fullContent += $token
                            Write-Host $token -NoNewline -ForegroundColor White
                        }
                    } catch {
                        # Skip malformed chunks
                    }
                }
            }
            
            $reader.Close()
            $responseStream.Close()
            $response.Close()
            
            Write-Host ""  # Newline after streaming
            
            return @{
                Content = $fullContent
                Model = $Model
                Usage = $null  # Not available in streaming
                StopReason = "stop"
                Streamed = $true
            }
        }
        catch [System.Net.WebException] {
            $errorResponse = $_.Exception.Response
            if ($errorResponse) {
                $errorReader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream())
                $errorText = $errorReader.ReadToEnd()
                throw "API Error: $errorText"
            }
            throw
        }
    }
    else {
        # Non-streaming response
        $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Body $jsonBody -Headers $headers -ErrorAction Stop
        
        if ($null -eq $response.choices -or $response.choices.Count -eq 0) {
            throw "Server returned empty or malformed response"
        }
        
        $reply = $response.choices[0].message.content
        if ([string]::IsNullOrWhiteSpace($reply)) {
            throw "Server returned empty message content"
        }
        
        return @{
            Content = $reply
            Model = $response.model
            Usage = $response.usage
            StopReason = $response.choices[0].finish_reason
            Streamed = $false
        }
    }
}

function Invoke-AnthropicChat {
    param(
        [string]$Endpoint,
        [string]$Model,
        [array]$Messages,
        [double]$Temperature = 0.7,
        [int]$MaxTokens = 4096,
        [string]$ApiKey,
        [string]$SystemPrompt = $null
    )
    
    # Anthropic uses a different message format
    # Convert from OpenAI format to Anthropic format
    $anthropicMessages = @()
    foreach ($msg in $Messages) {
        if ($msg.role -eq 'system') {
            # Anthropic handles system prompts separately
            if (-not $SystemPrompt) {
                $SystemPrompt = $msg.content
            }
            continue
        }
        $anthropicMessages += @{
            role = $msg.role
            content = $msg.content
        }
    }
    
    $body = @{
        model = $Model
        max_tokens = $MaxTokens
        messages = $anthropicMessages
    }
    
    if ($SystemPrompt) {
        $body["system"] = $SystemPrompt
    }
    
    if ($Temperature -ne 1.0) {
        $body["temperature"] = $Temperature
    }
    
    $jsonBody = $body | ConvertTo-Json -Depth 10
    
    $headers = @{
        "Content-Type" = "application/json"
        "x-api-key" = $ApiKey
        "anthropic-version" = "2023-06-01"
    }
    
    $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Body $jsonBody -Headers $headers -ErrorAction Stop
    
    if ($null -eq $response.content -or $response.content.Count -eq 0) {
        throw "Anthropic returned empty response"
    }
    
    $reply = ($response.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1).text
    if ([string]::IsNullOrWhiteSpace($reply)) {
        throw "Anthropic returned empty message content"
    }
    
    return @{
        Content = $reply
        Model = $response.model
        Usage = @{
            prompt_tokens = $response.usage.input_tokens
            completion_tokens = $response.usage.output_tokens
            total_tokens = $response.usage.input_tokens + $response.usage.output_tokens
        }
        StopReason = $response.stop_reason
    }
}

# ===== Unified Chat Function =====
function Invoke-ChatCompletion {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Messages,
        
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model = $null,
        [double]$Temperature = 0.7,
        [int]$MaxTokens = 4096,
        [string]$SystemPrompt = $null,
        [switch]$Stream
    )
    
    $config = $global:ChatProviders[$Provider]
    if (-not $config) {
        throw "Unknown provider: $Provider. Available: $($global:ChatProviders.Keys -join ', ')"
    }
    
    # Use default model if not specified
    if (-not $Model) {
        $Model = $config.DefaultModel
    }
    
    # Get API key if required
    $apiKey = $null
    if ($config.ApiKeyRequired) {
        $apiKey = Get-ChatApiKey $Provider
        if (-not $apiKey) {
            throw "API key required for $($config.Name). Set with: Set-ChatApiKey -Provider $Provider -ApiKey 'your-key'"
        }
    }
    
    # Route to appropriate API handler
    switch ($config.Format) {
        'openai' {
            return Invoke-OpenAICompatibleChat -Endpoint $config.Endpoint -Model $Model -Messages $Messages -Temperature $Temperature -MaxTokens $MaxTokens -ApiKey $apiKey -Stream:$Stream
        }
        'anthropic' {
            # Anthropic streaming not yet implemented, fall back to non-streaming
            return Invoke-AnthropicChat -Endpoint $config.Endpoint -Model $Model -Messages $Messages -Temperature $Temperature -MaxTokens $MaxTokens -ApiKey $apiKey -SystemPrompt $SystemPrompt
        }
        default {
            throw "Unknown API format: $($config.Format)"
        }
    }
}

# ===== Context Window Management =====
function Get-TrimmedMessages {
    param(
        [array]$Messages,
        [int]$MaxTokens = 4096,
        [int]$TargetTokens = 0,  # If 0, use 80% of MaxTokens
        [int]$KeepFirstN = 2     # Keep first N messages (usually system context)
    )
    
    if ($TargetTokens -eq 0) {
        $TargetTokens = [math]::Floor($MaxTokens * 0.8)
    }
    
    # Estimate current token count (rough: 4 chars per token)
    $estimatedTokens = 0
    foreach ($msg in $Messages) {
        $estimatedTokens += [math]::Ceiling($msg.content.Length / 4)
    }
    
    # If under target, no trimming needed
    if ($estimatedTokens -le $TargetTokens) {
        return @{
            Messages = $Messages
            Trimmed = $false
            EstimatedTokens = $estimatedTokens
            RemovedCount = 0
        }
    }
    
    # Need to trim - keep first N and remove oldest messages after that
    $trimmedMessages = @()
    $removedCount = 0
    
    # Always keep first N messages (system context)
    $keepFirst = [math]::Min($KeepFirstN, $Messages.Count)
    for ($i = 0; $i -lt $keepFirst; $i++) {
        $trimmedMessages += $Messages[$i]
    }
    
    # Calculate tokens used by kept first messages
    $firstTokens = 0
    foreach ($msg in $trimmedMessages) {
        $firstTokens += [math]::Ceiling($msg.content.Length / 4)
    }
    
    # Add messages from the end until we hit target
    $remainingTokens = $TargetTokens - $firstTokens
    $endMessages = @()
    
    for ($i = $Messages.Count - 1; $i -ge $keepFirst; $i--) {
        $msgTokens = [math]::Ceiling($Messages[$i].content.Length / 4)
        if ($remainingTokens - $msgTokens -ge 0) {
            $endMessages = @($Messages[$i]) + $endMessages
            $remainingTokens -= $msgTokens
        } else {
            $removedCount++
        }
    }
    
    $trimmedMessages += $endMessages
    
    # Recalculate final token count
    $finalTokens = 0
    foreach ($msg in $trimmedMessages) {
        $finalTokens += [math]::Ceiling($msg.content.Length / 4)
    }
    
    return @{
        Messages = $trimmedMessages
        Trimmed = $true
        EstimatedTokens = $finalTokens
        RemovedCount = $removedCount
    }
}

# ===== Helper Functions =====
function Show-ChatProviders {
    Write-Host "`n===== Available Chat Providers =====" -ForegroundColor Cyan
    
    foreach ($key in $global:ChatProviders.Keys | Sort-Object) {
        $config = $global:ChatProviders[$key]
        $isDefault = if ($key -eq $global:DefaultChatProvider) { " (default)" } else { "" }
        
        Write-Host "`n  $($config.Name)$isDefault" -ForegroundColor Green
        Write-Host "    Provider ID: $key" -ForegroundColor Gray
        Write-Host "    Endpoint: $($config.Endpoint)" -ForegroundColor Gray
        Write-Host "    Default Model: $($config.DefaultModel)" -ForegroundColor Gray
        Write-Host "    API Key Required: $($config.ApiKeyRequired)" -ForegroundColor Gray
        
        if ($config.ApiKeyRequired) {
            $hasKey = if (Get-ChatApiKey $key) { "Set" } else { "Not Set" }
            $keyColor = if ($hasKey -eq "Set") { "Green" } else { "Yellow" }
            Write-Host "    API Key Status: $hasKey" -ForegroundColor $keyColor
        }
    }
    
    Write-Host "`n=====================================" -ForegroundColor Cyan
    Write-Host "Use 'Set-DefaultChatProvider <name>' to change default" -ForegroundColor DarkGray
    Write-Host "Use 'Test-ChatProvider <name>' to verify connectivity" -ForegroundColor DarkGray
    Write-Host ""
}

function Set-DefaultChatProvider {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Provider
    )
    
    if (-not $global:ChatProviders.ContainsKey($Provider)) {
        Write-Host "Unknown provider: $Provider" -ForegroundColor Red
        Write-Host "Available: $($global:ChatProviders.Keys -join ', ')" -ForegroundColor Yellow
        return
    }
    
    $global:DefaultChatProvider = $Provider
    Write-Host "Default chat provider set to: $($global:ChatProviders[$Provider].Name)" -ForegroundColor Green
}

function Get-ChatModels {
    param([string]$Provider = $global:DefaultChatProvider)
    
    $config = $global:ChatProviders[$Provider]
    if (-not $config) {
        Write-Host "Unknown provider: $Provider" -ForegroundColor Red
        return
    }
    
    Write-Host "`n===== $($config.Name) Models =====" -ForegroundColor Cyan
    
    # For Ollama, we can list installed models
    if ($Provider -eq 'ollama') {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5
            if ($response.models) {
                foreach ($model in $response.models) {
                    $size = [math]::Round($model.size / 1GB, 2)
                    Write-Host "  $($model.name)" -ForegroundColor Green -NoNewline
                    Write-Host " (${size}GB)" -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Host "  Could not fetch models. Is Ollama running?" -ForegroundColor Yellow
            Write-Host "  Default: $($config.DefaultModel)" -ForegroundColor Gray
        }
    }
    elseif ($Provider -eq 'anthropic') {
        Write-Host "  claude-3-5-sonnet-20241022 (recommended)" -ForegroundColor Green
        Write-Host "  claude-3-5-haiku-20241022 (fast)" -ForegroundColor Gray
        Write-Host "  claude-3-opus-20240229 (most capable)" -ForegroundColor Gray
    }
    elseif ($Provider -eq 'openai') {
        Write-Host "  gpt-4o (recommended)" -ForegroundColor Green
        Write-Host "  gpt-4o-mini (fast, cheap)" -ForegroundColor Gray
        Write-Host "  gpt-4-turbo (legacy)" -ForegroundColor Gray
    }
    else {
        Write-Host "  Default: $($config.DefaultModel)" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# ===== Aliases =====
Set-Alias providers Show-ChatProviders -Force
Set-Alias chat-test Test-ChatProvider -Force
Set-Alias chat-models Get-ChatModels -Force
