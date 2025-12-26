# ===== NaturalLanguage.ps1 =====
# Natural language to command translation and token estimation

# ===== Data-Driven Natural Language Mappings =====
$global:NLMappingsPath = "$PSScriptRoot\..\NaturalLanguageMappings.json"
$global:NLMappings = $null

function Import-NaturalLanguageMappings {
    <#
    .SYNOPSIS
    Load natural language mappings from JSON file
    #>
    if (Test-Path $global:NLMappingsPath) {
        try {
            $global:NLMappings = Get-Content $global:NLMappingsPath -Raw | ConvertFrom-Json
            return $true
        } catch {
            Write-Host "Warning: Failed to load NL mappings: $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }
    return $false
}

# Load mappings on module import
Import-NaturalLanguageMappings | Out-Null

function Convert-NaturalLanguageToCommand {
    <#
    .SYNOPSIS
    Convert natural language input to PowerShell commands
    #>
    param([string]$InputText)
    
    $lowerInput = $InputText.ToLower().Trim()
    
    # Try data-driven mappings first if loaded
    if ($global:NLMappings) {
        # Check exact command mappings
        $commands = $global:NLMappings.mappings.commands
        if ($commands.PSObject.Properties.Name -contains $lowerInput) {
            $command = $commands.$lowerInput
            Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
            return "EXECUTE: $command"
        }
        
        # Check for "please" variants
        $cleanInput = $lowerInput -replace '^please\s+', '' -replace '\s+please$', ''
        if ($commands.PSObject.Properties.Name -contains $cleanInput) {
            $command = $commands.$cleanInput
            Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
            return "EXECUTE: $command"
        }
        
        # Check application shortcuts (e.g., "open word" -> "Start-Process winword")
        $apps = $global:NLMappings.mappings.applications
        foreach ($verb in @('open', 'start', 'launch', 'run')) {
            if ($lowerInput -match "^$verb\s+(.+)$") {
                $appName = $Matches[1].Trim()
                if ($apps.PSObject.Properties.Name -contains $appName) {
                    $executable = $apps.$appName
                    $command = "Start-Process $executable"
                    Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
                    return "EXECUTE: $command"
                }
            }
        }
        
        # Check regex patterns
        $patterns = $global:NLMappings.mappings.patterns
        foreach ($pattern in $patterns.PSObject.Properties) {
            if ($lowerInput -match $pattern.Name) {
                $command = $pattern.Value
                # Replace capture groups
                for ($i = 1; $i -le 9; $i++) {
                    if ($Matches[$i]) {
                        $command = $command -replace "\`$$i", $Matches[$i]
                    }
                }
                Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
                return "EXECUTE: $command"
            }
        }
    }
    
    # Fallback: hardcoded mappings for reliability
    $fallbackMappings = @{
        'open word' = 'Start-Process winword'
        'open excel' = 'Start-Process excel'
        'open notepad' = 'Start-Process notepad'
        'open calculator' = 'Start-Process calc'
        'list files' = 'Get-ChildItem'
        'show files' = 'Get-ChildItem'
        'show processes' = 'Get-Process'
        'list processes' = 'Get-Process'
    }
    
    foreach ($phrase in $fallbackMappings.Keys) {
        if ($lowerInput -eq $phrase -or $lowerInput -match [regex]::Escape($phrase)) {
            $command = $fallbackMappings[$phrase]
            Write-Host "Translating '$InputText' → '$command'" -ForegroundColor DarkCyan
            return "EXECUTE: $command"
        }
    }
    
    # No translation needed
    return $InputText
}

function Get-TokenEstimate {
    <#
    .SYNOPSIS
    Get chars-per-token estimate for a provider from config
    #>
    param([string]$Provider = 'default')
    
    if ($global:NLMappings -and $global:NLMappings.tokenEstimates) {
        $estimates = $global:NLMappings.tokenEstimates
        if ($estimates.providers.PSObject.Properties.Name -contains $Provider) {
            return $estimates.providers.$Provider
        }
        return $estimates.default
    }
    return 4.0  # Default fallback
}

function Get-EstimatedTokenCount {
    <#
    .SYNOPSIS
    Estimate token count for current chat session
    #>
    $totalChars = ($global:ChatSessionHistory | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum
    return [math]::Ceiling($totalChars / 4)
}

Write-Verbose "NaturalLanguage loaded: Convert-NaturalLanguageToCommand, Get-TokenEstimate, Get-EstimatedTokenCount"
