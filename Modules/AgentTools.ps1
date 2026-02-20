# ===== AgentTools.ps1 =====
# Lightweight tool registry for the agent system.
# Tools are pure computational functions — no safety prompts, no intent router overhead.
# The agent calls tools for calculations, lookups, and data manipulation,
# and intents for actions that affect the system (files, apps, git, etc).

# ===== Tool Registry =====
$global:AgentTools = [ordered]@{}
$global:AgentMemory = @{}

function Register-AgentTool {
    <#
    .SYNOPSIS
    Register a tool for the agent to use. Plugins can call this to add custom tools.

    .PARAMETER Name
    Unique tool name (snake_case).

    .PARAMETER Description
    Short description shown to the LLM.

    .PARAMETER Parameters
    Array of @{ Name; Required; Description } hashtables.

    .PARAMETER Execute
    ScriptBlock that receives named parameters as a hashtable.
    Must return @{ Success = $bool; Output = "string" }.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Description,
        [array]$Parameters = @(),
        [Parameter(Mandatory = $true)][scriptblock]$Execute
    )

    $global:AgentTools[$Name] = [ordered]@{
        Name        = $Name
        Description = $Description
        Parameters  = $Parameters
        Execute     = $Execute
    }
}

function Invoke-AgentTool {
    <#
    .SYNOPSIS
    Execute a registered agent tool by name.

    .PARAMETER Name
    Tool name.

    .PARAMETER Params
    Hashtable of parameters to pass to the tool.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [hashtable]$Params = @{}
    )

    if (-not $global:AgentTools.Contains($Name)) {
        return @{ Success = $false; Output = "Unknown tool: $Name. Available: $($global:AgentTools.Keys -join ', ')" }
    }

    $tool = $global:AgentTools[$Name]

    # Validate required parameters
    foreach ($pDef in $tool.Parameters) {
        if ($pDef.Required -and -not $Params.ContainsKey($pDef.Name)) {
            return @{ Success = $false; Output = "Missing required parameter '$($pDef.Name)' for tool '$Name'" }
        }
    }

    try {
        $result = & $tool.Execute $Params
        if ($null -eq $result) {
            return @{ Success = $true; Output = "(no output)" }
        }
        return $result
    }
    catch {
        return @{ Success = $false; Output = "Tool error: $($_.Exception.Message)" }
    }
}

function Get-AgentTools {
    <#
    .SYNOPSIS
    List all registered agent tools with descriptions.
    #>
    Write-Host "`n===== Agent Tools =====" -ForegroundColor Cyan
    foreach ($name in $global:AgentTools.Keys) {
        $tool = $global:AgentTools[$name]
        Write-Host "  $name" -ForegroundColor Yellow -NoNewline
        Write-Host " — $($tool.Description)" -ForegroundColor Gray
        if ($tool.Parameters.Count -gt 0) {
            $paramStr = ($tool.Parameters | ForEach-Object {
                $req = if ($_.Required) { "" } else { "?" }
                "$($_.Name)$req"
            }) -join ", "
            Write-Host "    params: $paramStr" -ForegroundColor DarkGray
        }
    }
    Write-Host "========================`n" -ForegroundColor Cyan
}

function Get-AgentToolInfo {
    <#
    .SYNOPSIS
    Show detailed info about a specific agent tool.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $global:AgentTools.ContainsKey($Name)) {
        Write-Host "Tool '$Name' not found." -ForegroundColor Red
        return
    }

    $tool = $global:AgentTools[$Name]
    Write-Host "`n===== Tool: $Name =====" -ForegroundColor Cyan
    Write-Host "  $($tool.Description)" -ForegroundColor White
    if ($tool.Parameters.Count -gt 0) {
        Write-Host "  Parameters:" -ForegroundColor Yellow
        foreach ($p in $tool.Parameters) {
            $req = if ($p.Required) { "(required)" } else { "(optional)" }
            Write-Host "    $($p.Name) $req — $($p.Description)" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

# ===== Built-in Tools =====

# --- calculator ---
Register-AgentTool -Name 'calculator' `
    -Description 'Evaluate a math expression. Supports +, -, *, /, %, [math]:: methods.' `
    -Parameters @(
        @{ Name = 'expression'; Required = $true; Description = 'Math expression, e.g. "2+2", "[math]::Sqrt(144)", "1200 * 0.08"' }
    ) `
    -Execute {
        param($p)
        $expr = $p['expression']
        # Sanitize: allow digits, operators, parens, dots, [math]:: calls, spaces
        $sanitized = $expr -replace '[^0-9+\-*/%.() ,\[\]a-zA-Z:]', ''
        if ($sanitized -ne $expr) {
            return @{ Success = $false; Output = "Expression contains disallowed characters" }
        }
        # Block anything that isn't math
        if ($sanitized -match '(Get-|Set-|Remove-|New-|Start-|Stop-|Invoke-|Import-|Export-)') {
            return @{ Success = $false; Output = "Only math expressions are allowed" }
        }
        try {
            $result = Invoke-Expression $sanitized
            return @{ Success = $true; Output = "$sanitized = $result"; Value = $result }
        }
        catch {
            return @{ Success = $false; Output = "Math error: $($_.Exception.Message)" }
        }
    }

# --- datetime ---
Register-AgentTool -Name 'datetime' `
    -Description 'Get current date/time, do date math, or convert timezones.' `
    -Parameters @(
        @{ Name = 'operation'; Required = $false; Description = 'now (default), add, diff, convert, format' }
        @{ Name = 'value'; Required = $false; Description = 'Date string or offset like "7 days", "3 hours"' }
        @{ Name = 'timezone'; Required = $false; Description = 'Target timezone ID, e.g. "Eastern Standard Time"' }
        @{ Name = 'format'; Required = $false; Description = 'Date format string, e.g. "yyyy-MM-dd"' }
    ) `
    -Execute {
        param($p)
        $op = if ($p['operation']) { $p['operation'] } else { 'now' }
        switch ($op) {
            'now' {
                $fmt = if ($p['format']) { $p['format'] } else { 'yyyy-MM-dd HH:mm:ss zzz' }
                $now = Get-Date
                return @{ Success = $true; Output = $now.ToString($fmt); Value = $now }
            }
            'add' {
                $val = $p['value']
                if (-not $val) { return @{ Success = $false; Output = "Provide 'value' like '7 days' or '3 hours'" } }
                $now = Get-Date
                if ($val -match '^(-?\d+)\s*(day|days|hour|hours|minute|minutes|second|seconds|month|months|year|years)$') {
                    $num = [int]$Matches[1]
                    $unit = $Matches[2] -replace 's$', ''
                    $result = switch ($unit) {
                        'day'    { $now.AddDays($num) }
                        'hour'   { $now.AddHours($num) }
                        'minute' { $now.AddMinutes($num) }
                        'second' { $now.AddSeconds($num) }
                        'month'  { $now.AddMonths($num) }
                        'year'   { $now.AddYears($num) }
                    }
                    return @{ Success = $true; Output = "$result"; Value = $result }
                }
                return @{ Success = $false; Output = "Cannot parse '$val'. Use format: '7 days', '-3 hours'" }
            }
            'convert' {
                $tz = $p['timezone']
                if (-not $tz) { return @{ Success = $false; Output = "Provide 'timezone' like 'Eastern Standard Time'" } }
                try {
                    $tzInfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($tz)
                    $converted = [System.TimeZoneInfo]::ConvertTime((Get-Date), $tzInfo)
                    return @{ Success = $true; Output = "$converted ($($tzInfo.DisplayName))"; Value = $converted }
                }
                catch {
                    $zones = [System.TimeZoneInfo]::GetSystemTimeZones() | Where-Object { $_.Id -like "*$tz*" -or $_.DisplayName -like "*$tz*" } | Select-Object -First 5
                    $suggestions = if ($zones) { ($zones | ForEach-Object { $_.Id }) -join ', ' } else { 'none found' }
                    return @{ Success = $false; Output = "Unknown timezone '$tz'. Similar: $suggestions" }
                }
            }
            'format' {
                $fmt = if ($p['format']) { $p['format'] } else { 'o' }
                $val = if ($p['value']) { [datetime]::Parse($p['value']) } else { Get-Date }
                return @{ Success = $true; Output = $val.ToString($fmt) }
            }
            default {
                return @{ Success = $false; Output = "Unknown operation '$op'. Use: now, add, diff, convert, format" }
            }
        }
    }

# --- web_search ---
Register-AgentTool -Name 'web_search' `
    -Description 'Search the web. Returns titles, snippets, and URLs.' `
    -Parameters @(
        @{ Name = 'query'; Required = $true; Description = 'Search query' }
        @{ Name = 'max_results'; Required = $false; Description = 'Max results (default 5)' }
    ) `
    -Execute {
        param($p)
        $max = if ($p['max_results']) { [int]$p['max_results'] } else { 5 }
        if (Get-Command Invoke-WebSearch -ErrorAction SilentlyContinue) {
            $result = Invoke-WebSearch -Query $p['query'] -MaxResults $max
            if ($result.Success) {
                $output = "Results for '$($p['query'])':`n"
                $i = 1
                foreach ($r in $result.Results) {
                    $output += "$i. $($r.Title)`n   $($r.Snippet)`n   $($r.Url)`n"
                    $i++
                }
                return @{ Success = $true; Output = $output; Results = $result.Results }
            }
            return @{ Success = $false; Output = $result.Message }
        }
        return @{ Success = $false; Output = "WebTools not loaded" }
    }

# --- fetch_url ---
Register-AgentTool -Name 'fetch_url' `
    -Description 'Fetch and extract text content from a web page.' `
    -Parameters @(
        @{ Name = 'url'; Required = $true; Description = 'URL to fetch' }
        @{ Name = 'max_length'; Required = $false; Description = 'Max chars to return (default 3000)' }
    ) `
    -Execute {
        param($p)
        $max = if ($p['max_length']) { [int]$p['max_length'] } else { 3000 }
        if (Get-Command Get-WebPageContent -ErrorAction SilentlyContinue) {
            $result = Get-WebPageContent -Url $p['url'] -MaxLength $max
            if ($result.Success) {
                return @{ Success = $true; Output = $result.Content; Length = $result.Length }
            }
            return @{ Success = $false; Output = $result.Message }
        }
        return @{ Success = $false; Output = "WebTools not loaded" }
    }

# --- wikipedia ---
Register-AgentTool -Name 'wikipedia' `
    -Description 'Search Wikipedia and return article summaries.' `
    -Parameters @(
        @{ Name = 'query'; Required = $true; Description = 'Topic to search' }
    ) `
    -Execute {
        param($p)
        if (Get-Command Search-Wikipedia -ErrorAction SilentlyContinue) {
            $result = Search-Wikipedia -Query $p['query']
            if ($result.Success -and $result.Results.Count -gt 0) {
                $output = ""
                foreach ($r in $result.Results) {
                    $output += "$($r.Title)`n"
                    if ($r.FullSummary) { $output += "$($r.FullSummary)`n" }
                    elseif ($r.Summary) { $output += "$($r.Summary)`n" }
                    $output += "URL: $($r.Url)`n`n"
                }
                return @{ Success = $true; Output = $output.Trim() }
            }
            return @{ Success = $false; Output = "No Wikipedia results for '$($p['query'])'" }
        }
        return @{ Success = $false; Output = "WebTools not loaded" }
    }

# --- stock_quote ---
Register-AgentTool -Name 'stock_quote' `
    -Description 'Get current stock price, change, and volume for a ticker symbol.' `
    -Parameters @(
        @{ Name = 'symbol'; Required = $true; Description = 'Stock ticker symbol, e.g. AAPL, MSFT, TSLA' }
    ) `
    -Execute {
        param($p)
        $symbol = $p['symbol'].ToUpper().Trim()
        try {
            $url = "https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=1d"
            $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
            $response = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 10
            $meta = $response.chart.result[0].meta
            $price = $meta.regularMarketPrice
            $prevClose = $meta.chartPreviousClose
            $change = [math]::Round($price - $prevClose, 2)
            $changePct = [math]::Round(($change / $prevClose) * 100, 2)
            $sign = if ($change -ge 0) { '+' } else { '' }
            $currency = $meta.currency
            $name = $meta.shortName
            if (-not $name) { $name = $symbol }
            $volume = $meta.regularMarketVolume
            $volStr = if ($volume -gt 1000000) { "$([math]::Round($volume/1000000, 1))M" } elseif ($volume -gt 1000) { "$([math]::Round($volume/1000, 0))K" } else { "$volume" }
            $output = "$name ($symbol): $currency $price (${sign}$change, ${sign}$changePct%) | Vol: $volStr"
            return @{
                Success = $true
                Output  = $output
                Price   = $price
                Change  = $change
                Percent = $changePct
                Volume  = $volume
                Symbol  = $symbol
            }
        }
        catch {
            return @{ Success = $false; Output = "Failed to fetch quote for '$symbol': $($_.Exception.Message)" }
        }
    }

# --- json_parse ---
Register-AgentTool -Name 'json_parse' `
    -Description 'Parse JSON text and optionally extract a value by dot-path.' `
    -Parameters @(
        @{ Name = 'json'; Required = $true; Description = 'JSON string to parse' }
        @{ Name = 'path'; Required = $false; Description = 'Dot-notation path, e.g. "data.items[0].name"' }
    ) `
    -Execute {
        param($p)
        try {
            $obj = $p['json'] | ConvertFrom-Json
            if ($p['path']) {
                $value = $obj
                foreach ($segment in ($p['path'] -split '\.')) {
                    if ($segment -match '^(\w+)\[(\d+)\]$') {
                        $value = $value.($Matches[1])[$Matches[2]]
                    }
                    else {
                        $value = $value.$segment
                    }
                }
                return @{ Success = $true; Output = ($value | ConvertTo-Json -Depth 5 -Compress); Value = $value }
            }
            return @{ Success = $true; Output = ($obj | ConvertTo-Json -Depth 5); Value = $obj }
        }
        catch {
            return @{ Success = $false; Output = "JSON parse error: $($_.Exception.Message)" }
        }
    }

# --- regex_match ---
Register-AgentTool -Name 'regex_match' `
    -Description 'Test a regex pattern against text. Returns matches.' `
    -Parameters @(
        @{ Name = 'pattern'; Required = $true; Description = 'Regex pattern' }
        @{ Name = 'text'; Required = $true; Description = 'Text to search' }
    ) `
    -Execute {
        param($p)
        try {
            $regexMatches = [regex]::Matches($p['text'], $p['pattern'])
            if ($regexMatches.Count -eq 0) {
                return @{ Success = $true; Output = "No matches found"; MatchCount = 0 }
            }
            $output = "Found $($regexMatches.Count) match(es):`n"
            $i = 1
            foreach ($m in $regexMatches | Select-Object -First 20) {
                $output += "  $i. '$($m.Value)' at position $($m.Index)`n"
                if ($m.Groups.Count -gt 1) {
                    for ($g = 1; $g -lt $m.Groups.Count; $g++) {
                        $output += "     Group $g`: '$($m.Groups[$g].Value)'`n"
                    }
                }
                $i++
            }
            return @{ Success = $true; Output = $output.Trim(); MatchCount = $regexMatches.Count }
        }
        catch {
            return @{ Success = $false; Output = "Regex error: $($_.Exception.Message)" }
        }
    }

# --- read_file (lightweight, no intent overhead) ---
Register-AgentTool -Name 'read_file' `
    -Description 'Read contents of a local text file.' `
    -Parameters @(
        @{ Name = 'path'; Required = $true; Description = 'File path' }
        @{ Name = 'max_lines'; Required = $false; Description = 'Max lines to read (default 100)' }
    ) `
    -Execute {
        param($p)
        $path = $p['path']
        if (-not (Test-Path $path)) {
            return @{ Success = $false; Output = "File not found: $path" }
        }
        $maxLines = if ($p['max_lines']) { [int]$p['max_lines'] } else { 100 }
        try {
            $content = Get-Content $path -TotalCount $maxLines -ErrorAction Stop
            $totalLines = (Get-Content $path | Measure-Object -Line).Lines
            $text = $content -join "`n"
            $shown = [math]::Min($maxLines, $totalLines)
            return @{ Success = $true; Output = $text; LinesShown = $shown; TotalLines = $totalLines }
        }
        catch {
            return @{ Success = $false; Output = "Read error: $($_.Exception.Message)" }
        }
    }

# --- shell (gated through safety system) ---
Register-AgentTool -Name 'shell' `
    -Description 'Execute a PowerShell command. Only commands in the safe actions list are allowed.' `
    -Parameters @(
        @{ Name = 'command'; Required = $true; Description = 'PowerShell command to execute' }
    ) `
    -Execute {
        param($p)
        $cmd = $p['command']
        # Gate through safety system
        if (Get-Command Test-PowerShellCommand -ErrorAction SilentlyContinue) {
            $validation = Test-PowerShellCommand $cmd
            if (-not $validation.IsValid) {
                return @{ Success = $false; Output = "Command '$cmd' is not in the safe actions list" }
            }
        }
        if (Get-Command Invoke-AIExec -ErrorAction SilentlyContinue) {
            $result = Invoke-AIExec -Command $cmd -RequestSource "AgentTool"
            return @{ Success = $result.Success; Output = $result.Output }
        }
        return @{ Success = $false; Output = "Safety system not loaded" }
    }

# --- store (working memory) ---
Register-AgentTool -Name 'store' `
    -Description 'Store a named value in agent working memory for later use.' `
    -Parameters @(
        @{ Name = 'key'; Required = $true; Description = 'Name for the stored value' }
        @{ Name = 'value'; Required = $true; Description = 'Value to store' }
    ) `
    -Execute {
        param($p)
        $global:AgentMemory[$p['key']] = $p['value']
        return @{ Success = $true; Output = "Stored '$($p['key'])' = $($p['value'])" }
    }

# --- recall (working memory) ---
Register-AgentTool -Name 'recall' `
    -Description 'Retrieve a value from agent working memory.' `
    -Parameters @(
        @{ Name = 'key'; Required = $true; Description = 'Name of the stored value' }
    ) `
    -Execute {
        param($p)
        $key = $p['key']
        if ($global:AgentMemory.ContainsKey($key)) {
            return @{ Success = $true; Output = $global:AgentMemory[$key]; Value = $global:AgentMemory[$key] }
        }
        $available = if ($global:AgentMemory.Count -gt 0) { $global:AgentMemory.Keys -join ', ' } else { '(empty)' }
        return @{ Success = $false; Output = "Key '$key' not found in memory. Available: $available" }
    }

# ===== Aliases =====
Set-Alias agent-tools Get-AgentTools -Force

# Tab completion for tool names
Register-ArgumentCompleter -CommandName Invoke-AgentTool -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:AgentTools.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        $desc = $global:AgentTools[$_].Description
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
    }
}

Register-ArgumentCompleter -CommandName Get-AgentToolInfo -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:AgentTools.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Write-Verbose "AgentTools loaded: $($global:AgentTools.Count) tools registered (Register-AgentTool, Invoke-AgentTool, Get-AgentTools)"
