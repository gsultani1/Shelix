# ===== IntentRouter.ps1 =====
# Intent execution router, help functions, tab completion, and aliases.
# Loaded LAST by IntentAliasSystem.ps1 — depends on all other intent files.

function Invoke-IntentAction {
    <#
    .SYNOPSIS
    Router function for intent-based actions with metadata validation, safety enforcement, and logging
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Intent,
        [string]$Param = "",
        [string]$Param2 = "",
        [hashtable]$Payload = @{},
        [switch]$AutoConfirm,
        [switch]$Force
    )
    
    $intentId = [guid]::NewGuid().ToString().Substring(0, 8)
    
    try {
        # ===== Validate intent exists =====
        if (-not $global:IntentAliases.Contains($Intent)) {
            Write-Host "[Intent-$intentId] REJECTED: Intent '$Intent' not found" -ForegroundColor Red
            return @{
                Success  = $false
                Output   = "Intent '$Intent' not found. Available: $($global:IntentAliases.Keys -join ', ')"
                Error    = $true
                IntentId = $intentId
                Reason   = "IntentNotFound"
            }
        }
        
        Write-Host "[Intent-$intentId] Validating intent: $Intent" -ForegroundColor DarkCyan
        
        # ===== Get metadata for validation =====
        $meta = $global:IntentMetadata[$Intent]
        
        # ===== Build unified parameter set from Payload and positional args =====
        $providedParams = @{}
        
        # Extract from Payload (excluding meta keys)
        foreach ($key in $Payload.Keys) {
            if ($key -notin @('intent', 'action', 'Intent', 'Action')) {
                $providedParams[$key.ToLower()] = $Payload[$key]
            }
        }
        
        # Map legacy positional params if not already in payload
        if ($Param -and -not $providedParams.ContainsKey('param')) {
            $providedParams['param'] = $Param
        }
        if ($Param2 -and -not $providedParams.ContainsKey('param2')) {
            $providedParams['param2'] = $Param2
        }
        
        # ===== Validate parameters against metadata =====
        if ($meta -and $meta.Parameters) {
            $definedParamNames = @($meta.Parameters | ForEach-Object { $_.Name.ToLower() })
            
            # Also allow 'param' and 'param2' as legacy aliases for first/second defined params
            $legacyMapping = @{}
            if ($definedParamNames.Count -ge 1) {
                $legacyMapping['param'] = $definedParamNames[0]
            }
            if ($definedParamNames.Count -ge 2) {
                $legacyMapping['param2'] = $definedParamNames[1]
            }
            
            # Normalize legacy params to real param names
            foreach ($legacy in @('param', 'param2')) {
                if ($providedParams.ContainsKey($legacy) -and $legacyMapping.ContainsKey($legacy)) {
                    $realName = $legacyMapping[$legacy]
                    if (-not $providedParams.ContainsKey($realName)) {
                        $providedParams[$realName] = $providedParams[$legacy]
                    }
                    $providedParams.Remove($legacy)
                }
            }
            
            # Check for unknown parameters
            $allowedKeys = $definedParamNames + @('param', 'param2')
            $unknownParams = @($providedParams.Keys | Where-Object { $_ -notin $allowedKeys })
            
            if ($unknownParams.Count -gt 0) {
                Write-Host "[Intent-$intentId] REJECTED: Unknown parameters: $($unknownParams -join ', ')" -ForegroundColor Red
                return @{
                    Success  = $false
                    Output   = "Unknown parameters for '$Intent': $($unknownParams -join ', '). Allowed: $($definedParamNames -join ', ')"
                    Error    = $true
                    IntentId = $intentId
                    Reason   = "UnknownParameters"
                }
            }
            
            # Check required parameters
            $missingParams = @()
            foreach ($paramDef in $meta.Parameters) {
                if ($paramDef.Required) {
                    $paramName = $paramDef.Name.ToLower()
                    if (-not $providedParams.ContainsKey($paramName) -or 
                        [string]::IsNullOrWhiteSpace($providedParams[$paramName])) {
                        $missingParams += $paramDef.Name
                    }
                }
            }
            
            if ($missingParams.Count -gt 0) {
                Write-Host "[Intent-$intentId] REJECTED: Missing required parameters: $($missingParams -join ', ')" -ForegroundColor Red
                return @{
                    Success  = $false
                    Output   = "Missing required parameters for '$Intent': $($missingParams -join ', ')"
                    Error    = $true
                    IntentId = $intentId
                    Reason   = "MissingParameters"
                }
            }
        }
        
        # ===== Safety tier enforcement =====
        if ($meta -and $meta.Safety -eq 'RequiresConfirmation') {
            if (-not $Force) {
                # AutoConfirm doesn't bypass RequiresConfirmation — force a prompt
                $AutoConfirm = $false
            }
        }
        
        # ===== Show confirmation prompt =====
        if (-not $AutoConfirm -and -not $Force) {
            Write-Host "`nIntent Action: $Intent" -ForegroundColor Yellow
            foreach ($key in $providedParams.Keys) {
                Write-Host "  $key : $($providedParams[$key])" -ForegroundColor Gray
            }
            
            $response = Read-Host "Proceed? (y/n)"
            if ($response -notin @('y', 'yes', 'Y', 'YES')) {
                Write-Host "[Intent-$intentId] Cancelled by user" -ForegroundColor Yellow
                return @{
                    Success  = $false
                    Output   = "Cancelled by user"
                    Error    = $false
                    IntentId = $intentId
                    Reason   = "UserCancelled"
                }
            }
        }
        
        # ===== Build positional arguments for scriptblock =====
        $positionalArgs = @()
        if ($meta -and $meta.Parameters) {
            foreach ($paramDef in $meta.Parameters) {
                $paramName = $paramDef.Name.ToLower()
                if ($providedParams.ContainsKey($paramName)) {
                    $positionalArgs += $providedParams[$paramName]
                }
                else {
                    $positionalArgs += $null
                }
            }
        }
        else {
            # No metadata, fall back to legacy positional
            if ($providedParams.ContainsKey('param')) { $positionalArgs += $providedParams['param'] }
            elseif ($Param) { $positionalArgs += $Param }
            
            if ($providedParams.ContainsKey('param2')) { $positionalArgs += $providedParams['param2'] }
            elseif ($Param2) { $positionalArgs += $Param2 }
        }
        
        # ===== Execute =====
        Write-Host "[Intent-$intentId] Executing: $Intent" -ForegroundColor Cyan
        $startTime = Get-Date
        
        $scriptBlock = $global:IntentAliases[$Intent]
        $result = & $scriptBlock @positionalArgs
        
        $executionTime = ((Get-Date) - $startTime).TotalSeconds
        
        # ===== Propagate actual success/failure =====
        # Handle case where result might be wrapped in array
        $actualResult = $result
        if ($result -is [array] -and $result.Count -eq 1) {
            $actualResult = $result[0]
        }
        
        # Determine success - try multiple approaches for PS5.1/PS7 compatibility
        $success = $false
        $hasError = $false
        
        if ($null -ne $actualResult) {
            # Method 1: Direct property access (works for most cases)
            try {
                if ($null -ne $actualResult.Success) {
                    $success = [bool]$actualResult.Success
                }
                if ($null -ne $actualResult.Error) {
                    $hasError = [bool]$actualResult.Error
                }
            }
            catch {
                # Method 2: Hashtable key access
                if ($actualResult -is [hashtable]) {
                    if ($actualResult.ContainsKey('Success')) {
                        $success = [bool]$actualResult['Success']
                    }
                    if ($actualResult.ContainsKey('Error')) {
                        $hasError = [bool]$actualResult['Error']
                    }
                }
            }
        }
        
        # Update result reference for return
        $result = $actualResult
        
        $statusColor = if ($success) { 'Green' } else { 'Red' }
        $statusText = if ($success) { 'Completed' } else { 'Failed' }
        Write-Host "[Intent-$intentId] $statusText ($([math]::Round($executionTime, 2))s)" -ForegroundColor $statusColor
        
        # Toast notification for meaningful intents (>1s or always-notify categories)
        if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
            $alwaysNotify = @('document', 'git', 'workflow', 'filesystem')
            $intentCategory = if ($meta) { $meta.Category } else { '' }
            if ($executionTime -gt 1.0 -or $intentCategory -in $alwaysNotify) {
                $toastMsg = if ($result.Output) { $result.Output } else { "Intent: $Intent" }
                if ($toastMsg.Length -gt 80) { $toastMsg = $toastMsg.Substring(0, 80) + '...' }
                if ($success) {
                    Send-ShелixToast -Title $Intent -Message $toastMsg -Type Success
                }
                else {
                    Send-ShелixToast -Title "$Intent failed" -Message $toastMsg -Type Error
                }
            }
        }
        
        return @{
            Success       = $success
            Output        = $result.Output
            IntentId      = $intentId
            ExecutionTime = $executionTime
            Result        = $result
            Error         = $hasError
        }
    }
    catch {
        Write-Host "[Intent-$intentId] Exception: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success   = $false
            Output    = "Exception: $($_.Exception.Message)"
            Error     = $true
            IntentId  = $intentId
            Reason    = "Exception"
            Exception = $_.Exception.Message
        }
    }
}

function Get-IntentAliases {
    <#
    .SYNOPSIS
    List all available intent aliases
    #>
    Write-Host "`n===== Available Intent Aliases =====" -ForegroundColor Cyan
    $global:IntentAliases.Keys | Sort-Object | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Green
    }
    Write-Host ""
}

function Test-Intent {
    <#
    .SYNOPSIS
    Test an intent manually
    
    .PARAMETER JsonPayload
    JSON payload like {"intent":"open_file","param":"C:\path\file.txt"}
    #>
    param([Parameter(Mandatory = $true)][string]$JsonPayload)
    
    try {
        $payload = $JsonPayload | ConvertFrom-Json
        Invoke-IntentAction -Intent $payload.intent -Param $payload.param -Param2 $payload.param2 -AutoConfirm
    }
    catch {
        Write-Host "Invalid JSON payload: $_" -ForegroundColor Red
    }
}

function Get-IntentDescription {
    <#
    .SYNOPSIS
    Display detailed information about a specific intent
    
    .PARAMETER Name
    Intent name to describe
    #>
    param([Parameter(Mandatory = $true)][string]$Name)
    
    if ($global:IntentAliases.Contains($Name)) {
        Write-Host "`nIntent: $Name" -ForegroundColor Cyan
        Write-Host "Status: Available" -ForegroundColor Green
        Write-Host "Type: Script Block" -ForegroundColor Gray
        Write-Host ""
    }
    else {
        Write-Host "Intent '$Name' not found" -ForegroundColor Red
        Write-Host "Available intents: $($global:IntentAliases.Keys -join ', ')" -ForegroundColor Yellow
    }
}

function Show-IntentHelp {
    <#
    .SYNOPSIS
    Display help for all intents with usage examples, organized by category
    
    .PARAMETER Category
    Optional: Show only intents in a specific category
    #>
    param([string]$Category = "")
    
    Write-Host "`n===== Intent Alias System Help ====="  -ForegroundColor Cyan
    
    # Filter categories if specified
    $categoriesToShow = if ($Category) {
        if ($global:IntentCategories.Contains($Category)) {
            @{ $Category = $global:IntentCategories[$Category] }
        }
        else {
            Write-Host "Unknown category: $Category" -ForegroundColor Red
            Write-Host "Available categories: $($global:IntentCategories.Keys -join ', ')" -ForegroundColor Yellow
            return
        }
    }
    else {
        $global:IntentCategories
    }
    
    foreach ($catKey in $categoriesToShow.Keys | Sort-Object) {
        $cat = $categoriesToShow[$catKey]
        Write-Host "`n$($cat.Name) [$catKey]" -ForegroundColor Green
        Write-Host "  $($cat.Description)" -ForegroundColor DarkGray
        
        foreach ($intentName in $cat.Intents) {
            if ($global:IntentMetadata.Contains($intentName)) {
                $meta = $global:IntentMetadata[$intentName]
                $paramStr = ""
                if ($meta.Parameters.Count -gt 0) {
                    $paramNames = $meta.Parameters | ForEach-Object {
                        if ($_.Required) { "[$($_.Name)]" } else { "[$($_.Name)?]" }
                    }
                    $paramStr = " " + ($paramNames -join " ")
                }
                $intentDisplay = "  $intentName$paramStr"
                Write-Host $intentDisplay.PadRight(35) -NoNewline -ForegroundColor White
                Write-Host "- $($meta.Description)" -ForegroundColor Gray
            }
            elseif ($global:IntentAliases.Contains($intentName)) {
                Write-Host "  $intentName" -ForegroundColor White
            }
        }
    }
    
    Write-Host "`n===== Usage Examples =====" -ForegroundColor Yellow
    Write-Host "  Manual test:  intent '{\"intent\":\"open_file\",\"param\":\"C:\\report.docx\"}'"
    Write-Host "  With browser: intent '{\"intent\":\"open_url\",\"param\":\"google.com\",\"param2\":\"chrome\"}'"
    Write-Host "  Workflow:     intent '{\"intent\":\"research_topic\",\"param\":\"PowerShell automation\"}'"
    Write-Host "  AI JSON:      {\"intent\":\"browse_web\",\"param\":\"https://google.com\"}"
    
    Write-Host "`n===== Categories =====" -ForegroundColor Yellow
    Write-Host "  View specific: intent-help -Category workflow"
    Write-Host "  Available: $($global:IntentCategories.Keys -join ', ')" -ForegroundColor Gray
    
    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Get-IntentInfo {
    <#
    .SYNOPSIS
    Get detailed information about a specific intent including parameters
    #>
    param([Parameter(Mandatory = $true)][string]$Name)
    
    if (-not $global:IntentAliases.Contains($Name)) {
        Write-Host "Intent '$Name' not found" -ForegroundColor Red
        Write-Host "Available intents: $($global:IntentAliases.Keys -join ', ')" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n===== Intent: $Name =====" -ForegroundColor Cyan

    # Source attribution: user-skill, plugin, or core?
    $source = "core"
    if ($global:LoadedUserSkills -and $global:LoadedUserSkills.Contains($Name)) {
        $source = "user-skill"
    }
    elseif ($global:LoadedPlugins) {
        foreach ($pName in $global:LoadedPlugins.Keys) {
            if ($global:LoadedPlugins[$pName].Intents -contains $Name) {
                $source = "plugin: $pName"
                break
            }
        }
    }
    Write-Host "Source: $source" -ForegroundColor DarkCyan

    if ($global:IntentMetadata.Contains($Name)) {
        $meta = $global:IntentMetadata[$Name]
        Write-Host "Category: $($meta.Category)" -ForegroundColor Gray
        Write-Host "Description: $($meta.Description)" -ForegroundColor White
        
        if ($meta.Parameters.Count -gt 0) {
            Write-Host "`nParameters:" -ForegroundColor Yellow
            foreach ($param in $meta.Parameters) {
                $reqStr = if ($param.Required) { "(required)" } else { "(optional)" }
                Write-Host "  $($param.Name) $reqStr" -ForegroundColor Green
                Write-Host "    $($param.Description)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "`nParameters: None" -ForegroundColor Gray
        }
        
        # Check if it's a workflow
        if ($meta.Category -eq 'workflow') {
            Write-Host "`nType: Composite/Workflow Intent" -ForegroundColor Magenta
            Write-Host "  This intent chains multiple actions together." -ForegroundColor Gray
        }
    }
    else {
        Write-Host "Status: Available (no metadata)" -ForegroundColor Yellow
    }
    
    Write-Host "`nExample:" -ForegroundColor Yellow
    if ($global:IntentMetadata.Contains($Name) -and $global:IntentMetadata[$Name].Parameters.Count -gt 0) {
        $exampleParams = $global:IntentMetadata[$Name].Parameters | ForEach-Object { "`"$($_.Name)`":`"example`"" }
        Write-Host "  {`"intent`":`"$Name`",$($exampleParams -join ',')}" -ForegroundColor Gray
    }
    else {
        Write-Host "  {`"intent`":`"$Name`"}" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# Alias for quick testing
Set-Alias -Name intent -Value Test-Intent -Force
Set-Alias -Name intent-help -Value Show-IntentHelp -Force

# ===== Tab Completion for Intents =====
Register-ArgumentCompleter -CommandName Invoke-IntentAction -ParameterName Intent -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $global:IntentAliases.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        $description = if ($global:IntentMetadata.Contains($_)) { $global:IntentMetadata[$_].Description } else { "Intent action" }
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
    }
}

# Tab completion for Test-Intent (intent alias) - complete JSON payloads
Register-ArgumentCompleter -CommandName Test-Intent -ParameterName JsonPayload -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $global:IntentAliases.Keys | Sort-Object | ForEach-Object {
        $json = "{`"intent`":`"$_`"}"
        $description = if ($global:IntentMetadata.Contains($_)) { $global:IntentMetadata[$_].Description } else { "Intent action" }
        [System.Management.Automation.CompletionResult]::new("'$json'", $_, 'ParameterValue', $description)
    }
}

# Tab completion for Get-IntentInfo
Register-ArgumentCompleter -CommandName Get-IntentInfo -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $global:IntentAliases.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# Tab completion for Show-IntentHelp -Category
Register-ArgumentCompleter -CommandName Show-IntentHelp -ParameterName Category -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:IntentCategories.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        $desc = $global:IntentCategories[$_].Name
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
    }
}

Write-Host "BildsyPS loaded. Run 'intent-help' for usage." -ForegroundColor Green
