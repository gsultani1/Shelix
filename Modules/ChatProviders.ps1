# ===== ChatProviders.ps1 =====
# Multi-provider LLM chat system supporting Ollama, Anthropic, and LM Studio
# Provides unified interface for different AI backends
# If Warp had this, they wouldn't need $73M

# ===== Provider Configuration =====

# Per-model context window sizes (tokens). Used for intelligent budget management.
# These are INPUT context limits, not response limits.
$global:ModelContextLimits = @{
    # Anthropic
    'claude-sonnet-4-6'          = 200000
    'claude-opus-4-6'            = 200000
    'claude-sonnet-4-5-20250929' = 200000
    'claude-3-5-sonnet-20241022' = 200000
    'claude-3-5-haiku-20241022'  = 200000
    'claude-3-opus-20240229'     = 200000
    # OpenAI
    'gpt-4o'                     = 128000
    'gpt-4o-mini'                = 128000
    'gpt-4-turbo'                = 128000
    'o1'                         = 200000
    'o1-mini'                    = 128000
    # Local defaults (conservative)
    'llama3.2'                   = 8192
    'mistral-7b-instruct-v0.3'   = 32768
}
# Fallback for unknown models
$global:DefaultContextLimit = 8192
$global:DefaultMaxResponseTokens = 4096
$global:ChatProviders = @{
    'ollama'    = @{
        Name           = 'Ollama'
        Endpoint       = 'http://localhost:11434/v1/chat/completions'
        DefaultModel   = 'llama3.2'
        ApiKeyRequired = $false
        ApiKeyEnvVar   = $null
        Format         = 'openai'  # OpenAI-compatible API
        Description    = 'Local Ollama server (OpenAI-compatible)'
    }
    'anthropic' = @{
        Name           = 'Anthropic'
        Endpoint       = 'https://api.anthropic.com/v1/messages'
        DefaultModel   = 'claude-sonnet-4-6'
        ApiKeyRequired = $true
        ApiKeyEnvVar   = 'ANTHROPIC_API_KEY'
        Format         = 'anthropic'  # Anthropic Messages API
        Description    = 'Anthropic Claude API (cloud)'
    }
    'lmstudio'  = @{
        Name           = 'LM Studio'
        Endpoint       = 'http://localhost:1234/v1/chat/completions'
        DefaultModel   = 'mistral-7b-instruct-v0.3'
        ApiKeyRequired = $false
        ApiKeyEnvVar   = $null
        Format         = 'openai'  # OpenAI-compatible API
        Description    = 'Local LM Studio server'
    }
    'openai'    = @{
        Name           = 'OpenAI'
        Endpoint       = 'https://api.openai.com/v1/chat/completions'
        DefaultModel   = 'gpt-4o-mini'
        ApiKeyRequired = $true
        ApiKeyEnvVar   = 'OPENAI_API_KEY'
        Format         = 'openai'
        Description    = 'OpenAI API (cloud)'
    }
    'llm'       = @{
        Name           = 'LLM CLI'
        Endpoint       = $null  # Uses CLI, not HTTP
        DefaultModel   = 'gpt-4o-mini'
        ApiKeyRequired = $false  # Managed by llm CLI
        ApiKeyEnvVar   = $null
        Format         = 'llm-cli'  # Special format for CLI wrapper
        Description    = 'Simon Willison llm CLI (100+ plugins)'
    }
}

# Default provider
$global:DefaultChatProvider = 'ollama'

# ===== Config File Loading =====
$global:ChatConfigPath = "$global:BildsyPSHome\config\ChatConfig.json"
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

            # Apply defaults from config
            if ($global:ChatConfig.defaults) {
                $d = $global:ChatConfig.defaults
                if ($d.provider -and $global:ChatProviders.Contains($d.provider)) {
                    $global:DefaultChatProvider = $d.provider
                }
            }

            # Apply provider overrides from ChatConfig.json
            # Override DefaultModel and Endpoint from providers.* entries
            # so ChatConfig.json is the single source of truth.
            if ($global:ChatConfig.providers) {
                foreach ($providerName in $global:ChatConfig.providers.PSObject.Properties.Name) {
                    $providerOverride = $global:ChatConfig.providers.$providerName
                    if ($global:ChatProviders.ContainsKey($providerName)) {
                        if ($providerOverride.defaultModel) {
                            $global:ChatProviders[$providerName].DefaultModel = $providerOverride.defaultModel
                            Write-Verbose "ChatConfig override: $providerName DefaultModel → $($providerOverride.defaultModel)"
                        }
                        if ($providerOverride.endpoint) {
                            $global:ChatProviders[$providerName].Endpoint = $providerOverride.endpoint
                            Write-Verbose "ChatConfig override: $providerName Endpoint → $($providerOverride.endpoint)"
                        }
                    }
                }
            }

            return $true
        }
        catch {
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
        [Parameter(Mandatory = $true)]
        [ValidateSet('anthropic', 'openai')]
        [string]$Provider,
        
        [Parameter(Mandatory = $true)]
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
    }
    else {
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
                model      = $config.DefaultModel
                messages   = @(@{ role = "user"; content = "Hi" })
                max_tokens = 5
            } | ConvertTo-Json -Depth 5
            
            $headers = @{ "Content-Type" = "application/json" }
            if ($config.ApiKeyRequired) {
                $headers["Authorization"] = "Bearer $(Get-ChatApiKey $Provider)"
            }
            
            $null = Invoke-RestMethod -Uri $config.Endpoint -Method Post -Body $testBody -Headers $headers -TimeoutSec 10
            Write-Host "  Endpoint responding" -ForegroundColor Green
            Write-Host "  Model: $($config.DefaultModel)" -ForegroundColor Gray
            return $true
        }
        elseif ($config.Format -eq 'anthropic') {
            $testBody = @{
                model      = $config.DefaultModel
                max_tokens = 5
                messages   = @(@{ role = "user"; content = "Hi" })
            } | ConvertTo-Json -Depth 5
            
            $headers = @{
                "Content-Type"      = "application/json"
                "x-api-key"         = (Get-ChatApiKey $Provider)
                "anthropic-version" = "2023-06-01"
            }
            
            $null = Invoke-RestMethod -Uri $config.Endpoint -Method Post -Body $testBody -Headers $headers -TimeoutSec 10
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
        [switch]$Stream,
        [int]$TimeoutSec = 300
    )
    
    $body = @{
        model       = $Model
        messages    = $Messages
        temperature = $Temperature
        max_tokens  = $MaxTokens
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
        $request.Timeout = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
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
                    }
                    catch {
                        # Skip malformed chunks
                    }
                }
            }
            
            $reader.Close()
            $responseStream.Close()
            $response.Close()
            
            Write-Host ""  # Newline after streaming
            
            return @{
                Content    = $fullContent
                Model      = $Model
                Usage      = $null  # Not available in streaming
                StopReason = "stop"
                Streamed   = $true
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
        # Non-streaming response with retry
        $maxRetries = 3
        $attempt = 0
        $lastError = $null

        while ($attempt -lt $maxRetries) {
            $attempt++
            try {
                $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonBody)) -Headers $headers -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec -ErrorAction Stop

                if ($null -eq $response.choices -or $response.choices.Count -eq 0) {
                    throw "Server returned empty or malformed response"
                }

                $reply = $response.choices[0].message.content
                if ([string]::IsNullOrWhiteSpace($reply)) {
                    throw "Server returned empty message content"
                }

                return @{
                    Content    = $reply
                    Model      = $response.model
                    Usage      = $response.usage
                    StopReason = $response.choices[0].finish_reason
                    Streamed   = $false
                }
            }
            catch {
                $lastError = $_
                $ex = $_.Exception
                $detail = $ex.Message
                while ($ex.InnerException) {
                    $ex = $ex.InnerException
                    $detail += " -> [$($ex.GetType().Name)] $($ex.Message)"
                }

                if ($attempt -lt $maxRetries) {
                    $wait = $attempt * 5
                    Write-Host "[OpenAI] Attempt $attempt/$maxRetries failed: $detail" -ForegroundColor Yellow
                    Write-Host "[OpenAI] Retrying in ${wait}s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $wait
                }
                else {
                    throw $lastError
                }
            }
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
        [string]$SystemPrompt = $null,
        [int]$TimeoutSec = 300
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
        # Pass content through as-is: string for text, array for multimodal (vision)
        $anthropicMessages += @{
            role    = $msg.role
            content = $msg.content
        }
    }
    
    # Always use streaming to keep the connection alive during long generations.
    # Non-streaming requests fail with ResponseEnded on large outputs (64K+ tokens)
    # because intermediate infrastructure drops idle HTTP connections.
    $body = @{
        model      = $Model
        max_tokens = $MaxTokens
        messages   = $anthropicMessages
        stream     = $true
    }
    
    if ($SystemPrompt) {
        $body["system"] = $SystemPrompt
    }
    
    if ($Temperature -ne 1.0) {
        $body["temperature"] = $Temperature
    }
    
    $jsonBody = $body | ConvertTo-Json -Depth 10
    
    $maxRetries = 5
    $attempt = 0
    $lastError = $null

    # Use HttpClient with SocketsHttpHandler for reliable streaming
    $handler = $null
    $client = $null
    try {
        $handler = [System.Net.Http.SocketsHttpHandler]::new()
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        $handler.PooledConnectionLifetime = [TimeSpan]::FromMinutes(15)
        $handler.PooledConnectionIdleTimeout = [TimeSpan]::FromMinutes(10)
        $handler.KeepAlivePingPolicy = [System.Net.Http.HttpKeepAlivePingPolicy]::WithActiveRequests
        $handler.KeepAlivePingDelay = [TimeSpan]::FromSeconds(15)
        $handler.KeepAlivePingTimeout = [TimeSpan]::FromSeconds(10)
    }
    catch {
        # Fallback for older runtimes without SocketsHttpHandler
        if ($handler) { $handler.Dispose() }
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    }
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

    try {
        while ($attempt -lt $maxRetries) {
            $attempt++
            try {
                $requestContent = [System.Net.Http.StringContent]::new($jsonBody, [System.Text.Encoding]::UTF8, 'application/json')
                $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $Endpoint)
                $request.Content = $requestContent
                $request.Headers.Add('x-api-key', $ApiKey)
                $request.Headers.Add('anthropic-version', '2023-06-01')

                # ResponseHeadersRead: start reading as soon as headers arrive (required for SSE streaming)
                $httpResponse = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()

                if (-not $httpResponse.IsSuccessStatusCode) {
                    $errBody = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    $statusCode = [int]$httpResponse.StatusCode
                    if ($statusCode -ge 429) {
                        throw "HTTP $statusCode`: $errBody"
                    }
                    throw "Anthropic API error (HTTP $statusCode`): $errBody"
                }

                # Read SSE stream: accumulate text deltas from content_block_delta events
                $responseStream = $httpResponse.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $reader = [System.IO.StreamReader]::new($responseStream, [System.Text.Encoding]::UTF8)

                $textBuilder = [System.Text.StringBuilder]::new(65536)
                $responseModel = $Model
                $stopReason = 'stop'
                $inputTokens = 0
                $outputTokens = 0

                while (-not $reader.EndOfStream) {
                    $line = $reader.ReadLine()

                    # SSE format: "event: <type>" then "data: <json>" then blank line
                    if (-not $line -or -not $line.StartsWith('data: ')) { continue }

                    $data = $line.Substring(6)
                    if ($data -eq '[DONE]') { break }

                    try { $evt = $data | ConvertFrom-Json } catch { continue }

                    switch ($evt.type) {
                        'message_start' {
                            if ($evt.message.model) { $responseModel = $evt.message.model }
                            if ($evt.message.usage) {
                                $inputTokens = [int]$evt.message.usage.input_tokens
                            }
                        }
                        'content_block_delta' {
                            if ($evt.delta.type -eq 'text_delta' -and $evt.delta.text) {
                                $null = $textBuilder.Append($evt.delta.text)
                            }
                        }
                        'message_delta' {
                            if ($evt.delta.stop_reason) { $stopReason = $evt.delta.stop_reason }
                            if ($evt.usage.output_tokens) {
                                $outputTokens = [int]$evt.usage.output_tokens
                            }
                        }
                    }
                }

                $reader.Dispose()
                $responseStream.Dispose()

                $reply = $textBuilder.ToString()
                if ([string]::IsNullOrWhiteSpace($reply)) {
                    throw "Anthropic returned empty message content (streamed)"
                }

                return @{
                    Content    = $reply
                    Model      = $responseModel
                    Usage      = @{
                        prompt_tokens     = $inputTokens
                        completion_tokens = $outputTokens
                        total_tokens      = $inputTokens + $outputTokens
                    }
                    StopReason = $stopReason
                }
            }
            catch {
                $lastError = $_
                $ex = $_.Exception
                $detail = $ex.Message
                while ($ex.InnerException) {
                    $ex = $ex.InnerException
                    $detail += " -> [$($ex.GetType().Name)] $($ex.Message)"
                }

                if ($attempt -lt $maxRetries) {
                    $base = [math]::Pow(2, $attempt) * 2
                    $jitter = Get-Random -Minimum 0 -Maximum ([math]::Max(1, [int]($base * 0.3)))
                    $wait = [int]$base + $jitter
                    Write-Host "[Anthropic] Attempt $attempt/$maxRetries failed: $detail" -ForegroundColor Yellow
                    Write-Host "[Anthropic] Retrying in ${wait}s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $wait
                }
                else {
                    Write-Host "[Anthropic] All $maxRetries attempts failed: $detail" -ForegroundColor Red
                    throw $lastError
                }
            }
        }
    }
    finally {
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }
}

# ===== LLM CLI Wrapper =====
function Invoke-LLMCliChat {
    <#
    .SYNOPSIS
    Wrapper for Simon Willison's llm CLI tool
    Provides access to 100+ plugins and models
    #>
    param(
        [string]$Model = "gpt-4o-mini",
        [array]$Messages,
        [string]$SystemPrompt = $null
    )
    
    # Check if llm is available
    $llmPath = Get-Command llm -ErrorAction SilentlyContinue
    if (-not $llmPath) {
        throw "llm CLI not found. Install with: pip install llm"
    }
    
    # Build the prompt from messages
    $prompt = ""
    foreach ($msg in $Messages) {
        if ($msg.role -eq "user") {
            $prompt += $msg.content + "`n"
        }
    }
    $prompt = $prompt.Trim()
    
    # Build command arguments
    $llmArgs = @()
    if ($Model) {
        $llmArgs += "-m"
        $llmArgs += $Model
    }
    if ($SystemPrompt) {
        $llmArgs += "-s"
        $llmArgs += $SystemPrompt
    }
    
    try {
        # Execute llm CLI and capture output
        $output = $prompt | llm @llmArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "llm CLI error: $output"
        }
        
        return @{
            Content    = $output -join "`n"
            Model      = $Model
            Usage      = @{
                prompt_tokens     = 0  # llm CLI doesn't report tokens
                completion_tokens = 0
                total_tokens      = 0
            }
            StopReason = "stop"
        }
    }
    catch {
        throw "LLM CLI error: $($_.Exception.Message)"
    }
}

# ===== Unified Chat Function =====
function Invoke-ChatCompletion {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Messages,
        
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model = $null,
        [double]$Temperature = 0.7,
        [int]$MaxTokens = 4096,
        [string]$SystemPrompt = $null,
        [switch]$Stream,
        [int]$TimeoutSec = 300
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
            return Invoke-OpenAICompatibleChat -Endpoint $config.Endpoint -Model $Model -Messages $Messages -Temperature $Temperature -MaxTokens $MaxTokens -ApiKey $apiKey -Stream:$Stream -TimeoutSec $TimeoutSec
        }
        'anthropic' {
            # Anthropic streaming not yet implemented, fall back to non-streaming
            return Invoke-AnthropicChat -Endpoint $config.Endpoint -Model $Model -Messages $Messages -Temperature $Temperature -MaxTokens $MaxTokens -ApiKey $apiKey -SystemPrompt $SystemPrompt -TimeoutSec $TimeoutSec
        }
        'llm-cli' {
            return Invoke-LLMCliChat -Model $Model -Messages $Messages -SystemPrompt $SystemPrompt
        }
        default {
            throw "Unknown API format: $($config.Format)"
        }
    }
}

# ===== Context Window Management =====

function Get-ModelContextLimit {
    <#
    .SYNOPSIS
    Look up the context window size for a model. Returns token count.
    #>
    param([string]$Model)
    
    if ($global:ModelContextLimits.ContainsKey($Model)) {
        return $global:ModelContextLimits[$Model]
    }
    # Fuzzy match: if model contains a known key as substring
    foreach ($key in $global:ModelContextLimits.Keys) {
        if ($Model -like "*$key*") {
            return $global:ModelContextLimits[$key]
        }
    }
    return $global:DefaultContextLimit
}

function Get-TrimmedMessages {
    param(
        [array]$Messages,
        [int]$ContextLimit = 0,       # Total context window (0 = use default)
        [int]$MaxResponseTokens = 0,  # Reserve for response (0 = use default)
        [int]$KeepFirstN = 2,         # Keep first N messages (system context)
        [switch]$Summarize            # Summarize evicted messages instead of dropping
    )
    
    if ($ContextLimit -le 0) { $ContextLimit = $global:DefaultContextLimit }
    if ($MaxResponseTokens -le 0) { $MaxResponseTokens = $global:DefaultMaxResponseTokens }
    
    # Budget = context window minus response reservation
    $budget = $ContextLimit - $MaxResponseTokens
    
    # Estimate current token count (rough: 4 chars per token)
    $estimatedTokens = 0
    foreach ($msg in $Messages) {
        $estimatedTokens += [math]::Ceiling($msg.content.Length / 4)
    }
    
    # If under budget, no trimming needed
    if ($estimatedTokens -le $budget) {
        return @{
            Messages        = $Messages
            Trimmed         = $false
            EstimatedTokens = $estimatedTokens
            RemovedCount    = 0
            Budget          = $budget
            ContextLimit    = $ContextLimit
        }
    }
    
    # Need to trim — keep first N (system context) and fill from the end
    $trimmedMessages = @()
    $evictedMessages = @()
    $removedCount = 0
    
    # Always keep first N messages (system context / safe commands)
    $keepFirst = [math]::Min($KeepFirstN, $Messages.Count)
    for ($i = 0; $i -lt $keepFirst; $i++) {
        $trimmedMessages += $Messages[$i]
    }
    
    $firstTokens = 0
    foreach ($msg in $trimmedMessages) {
        $firstTokens += [math]::Ceiling($msg.content.Length / 4)
    }
    
    # Reserve ~200 tokens for the summary message if summarizing
    $summaryReserve = if ($Summarize) { 200 } else { 0 }
    $remainingBudget = $budget - $firstTokens - $summaryReserve
    $endMessages = @()
    
    # Fill from the end (most recent messages first)
    for ($i = $Messages.Count - 1; $i -ge $keepFirst; $i--) {
        $msgTokens = [math]::Ceiling($Messages[$i].content.Length / 4)
        if ($remainingBudget - $msgTokens -ge 0) {
            $endMessages = @($Messages[$i]) + $endMessages
            $remainingBudget -= $msgTokens
        }
        else {
            $evictedMessages += $Messages[$i]
            $removedCount++
        }
    }
    
    # Build summary of evicted messages so model retains topic awareness
    if ($Summarize -and $evictedMessages.Count -gt 0) {
        $topics = @()
        foreach ($msg in $evictedMessages) {
            if ($msg.role -eq 'user') {
                $snippet = ($msg.content -replace '\s+', ' ').Trim()
                if ($snippet.Length -gt 80) { $snippet = $snippet.Substring(0, 80) + '...' }
                $topics += $snippet
            }
        }
        if ($topics.Count -gt 0) {
            $recapText = "[Earlier in this conversation ($removedCount messages trimmed for context), you discussed: $($topics -join '; ')]"
            $trimmedMessages += @{ role = 'user'; content = $recapText }
            $trimmedMessages += @{ role = 'assistant'; content = 'Understood, I recall those earlier topics.' }
        }
    }
    
    $trimmedMessages += $endMessages
    
    # Recalculate final token count
    $finalTokens = 0
    foreach ($msg in $trimmedMessages) {
        $finalTokens += [math]::Ceiling($msg.content.Length / 4)
    }
    
    return @{
        Messages        = $trimmedMessages
        Trimmed         = $true
        EstimatedTokens = $finalTokens
        RemovedCount    = $removedCount
        Budget          = $budget
        ContextLimit    = $ContextLimit
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
        [Parameter(Mandatory = $true)]
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
        Write-Host "  claude-sonnet-4-6 (recommended)" -ForegroundColor Green
        Write-Host "  claude-opus-4-6 (most capable)" -ForegroundColor Gray
        Write-Host "  claude-haiku-4-5-20251001 (fast)" -ForegroundColor Gray
        Write-Host "  claude-sonnet-4-5-20250929 (legacy)" -ForegroundColor Gray
    }
    elseif ($Provider -eq 'openai') {
        Write-Host "  gpt-4o (recommended)" -ForegroundColor Green
        Write-Host "  gpt-4o-mini (fast, cheap)" -ForegroundColor Gray
        Write-Host "  gpt-4-turbo (legacy)" -ForegroundColor Gray
    }
    elseif ($Provider -eq 'llm') {
        Write-Host "  Run 'llm models' to see all available models" -ForegroundColor Cyan
        Write-Host "  Install plugins with: llm install <plugin>" -ForegroundColor Gray
        Write-Host "  Plugin directory: https://llm.datasette.io/en/stable/plugins/directory.html" -ForegroundColor Gray
    }
    else {
        Write-Host "  Default: $($config.DefaultModel)" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# ===== LLM CLI Helper =====
function Get-LLMModels {
    <#
    .SYNOPSIS
    List available models from llm CLI
    #>
    $llmPath = Get-Command llm -ErrorAction SilentlyContinue
    if (-not $llmPath) {
        Write-Host "llm CLI not installed. Install with: pip install llm" -ForegroundColor Red
        return
    }
    llm models
}

function Install-LLMPlugin {
    <#
    .SYNOPSIS
    Install an llm plugin
    #>
    param([Parameter(Mandatory = $true)][string]$Plugin)
    llm install $Plugin
}

# ===== Tab Completion =====
$_chatProviderCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:ChatProviders.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        $desc = $global:ChatProviders[$_].Name
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
    }
}

Register-ArgumentCompleter -CommandName Set-DefaultChatProvider -ParameterName Provider -ScriptBlock $_chatProviderCompleter
Register-ArgumentCompleter -CommandName Get-ChatModels          -ParameterName Provider -ScriptBlock $_chatProviderCompleter
Register-ArgumentCompleter -CommandName Test-ChatProvider       -ParameterName Provider -ScriptBlock $_chatProviderCompleter

# ===== Aliases =====
Set-Alias providers Show-ChatProviders -Force
Set-Alias chat-test Test-ChatProvider -Force
Set-Alias chat-models Get-ChatModels -Force
Set-Alias llm-models Get-LLMModels -Force
Set-Alias llm-install Install-LLMPlugin -Force
