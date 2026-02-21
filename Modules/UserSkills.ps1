# ============= UserSkills.ps1 — User-Defined Custom Intents =============
# Loads custom intents from UserSkills.json so users can define their own
# command sequences, triggers, and workflows without writing PowerShell.
#
# Must be loaded AFTER IntentAliasSystem.ps1 so the registries exist.

$global:UserSkillsPath = "$global:BildsyPSHome\skills\UserSkills.json"
$global:LoadedUserSkills = [ordered]@{}

function Import-UserSkills {
    <#
    .SYNOPSIS
    Load user-defined skills from UserSkills.json and register them as intents.

    .PARAMETER Quiet
    Suppress summary output (used during profile startup).
    #>
    param([switch]$Quiet)

    if (-not (Test-Path $global:UserSkillsPath)) {
        # Auto-copy example file on first run if available
        $exampleFile = "$global:BildsyPSModulePath\UserSkills.example.json"
        if (Test-Path $exampleFile) {
            Copy-Item $exampleFile $global:UserSkillsPath -Force
            if (-not $Quiet) {
                Write-Host "Created UserSkills.json from example template." -ForegroundColor DarkCyan
            }
        }
        else {
            if (-not $Quiet) {
                Write-Host "No UserSkills.json found — skipping user skills." -ForegroundColor DarkGray
            }
            return
        }
    }

    try {
        $raw = Get-Content $global:UserSkillsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "UserSkills.json parse error: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    if (-not $raw.skills) {
        if (-not $Quiet) {
            Write-Host "UserSkills.json has no 'skills' property." -ForegroundColor Yellow
        }
        return
    }

    $loaded   = 0
    $skipped  = 0
    $warnings = @()

    # Ensure 'custom' category exists
    if (-not $global:CategoryDefinitions.ContainsKey('custom')) {
        $global:CategoryDefinitions['custom'] = @{
            Name        = 'Custom User Skills'
            Description = 'User-defined intents from UserSkills.json'
        }
    }

    foreach ($prop in $raw.skills.PSObject.Properties) {
        $skillName = $prop.Name
        $skill     = $prop.Value

        # Validate: must have steps
        if (-not $skill.steps -or $skill.steps.Count -eq 0) {
            $warnings += "$skillName — no steps defined, skipping"
            $skipped++
            continue
        }

        # Conflict check
        if ($global:IntentAliases.Contains($skillName)) {
            $warnings += "$skillName — intent already registered, skipping"
            $skipped++
            continue
        }

        # Determine category
        $category = if ($skill.category) { $skill.category } else { 'custom' }

        # Register category if custom and new
        if ($category -ne 'custom' -and -not $global:CategoryDefinitions.ContainsKey($category)) {
            $global:CategoryDefinitions[$category] = @{
                Name        = $category.Substring(0,1).ToUpper() + $category.Substring(1)
                Description = "User-defined $category skills"
            }
        }

        # Build parameter metadata
        $paramMeta = @()
        $paramNames = @()
        if ($skill.parameters) {
            foreach ($p in $skill.parameters) {
                $paramMeta += @{
                    Name        = $p.name
                    Required    = if ($null -ne $p.required) { [bool]$p.required } else { $false }
                    Description = if ($p.description) { $p.description } else { $p.name }
                }
                $paramNames += $p.name
            }
        }

        # Build parameter defaults map
        $paramDefaults = @{}
        if ($skill.parameters) {
            foreach ($p in $skill.parameters) {
                if ($null -ne $p.default) {
                    $paramDefaults[$p.name] = $p.default
                }
            }
        }

        # Register metadata
        $global:IntentMetadata[$skillName] = @{
            Category    = $category
            Description = if ($skill.description) { $skill.description } else { "User skill: $skillName" }
            Parameters  = $paramMeta
            Safety      = if ($skill.confirm) { 'RequiresConfirmation' } else { $null }
        }

        # Build the scriptblock via factory pattern (avoids $using: scope issues)
        $capturedSteps    = [array]$skill.steps
        $capturedName     = $skillName
        $capturedDefaults = $paramDefaults
        $capturedParams   = $paramNames

        $global:IntentAliases[$skillName] = New-UserSkillScriptBlock -Steps $capturedSteps -ParamNames $capturedParams -Defaults $capturedDefaults -SkillName $capturedName

        # Track
        $global:LoadedUserSkills[$skillName] = @{
            Description = if ($skill.description) { $skill.description } else { '' }
            Category    = $category
            Steps       = $capturedSteps.Count
            Parameters  = $paramNames
            Confirm     = [bool]$skill.confirm
            Triggers    = if ($skill.triggers) { @($skill.triggers) } else { @() }
        }

        # Register trigger phrases as aliases to the same scriptblock
        if ($skill.triggers) {
            foreach ($trigger in $skill.triggers) {
                if (-not $global:IntentAliases.Contains($trigger)) {
                    $global:IntentAliases[$trigger] = $global:IntentAliases[$skillName]
                }
            }
        }

        # Create a shell-invocable function so the user can type the skill name directly
        $fnBody = @"
param() Invoke-IntentAction -Intent '$skillName' -Payload @{ intent = '$skillName' } -Force
"@
        Set-Item -Path "function:global:$skillName" -Value ([scriptblock]::Create($fnBody)) -Force

        $loaded++
    }

    # Rebuild IntentCategories
    foreach ($catKey in $global:CategoryDefinitions.Keys) {
        $global:IntentCategories[$catKey] = @{
            Name        = $global:CategoryDefinitions[$catKey].Name
            Description = $global:CategoryDefinitions[$catKey].Description
            Intents     = @($global:IntentMetadata.Keys | Where-Object {
                $global:IntentMetadata[$_].Category -eq $catKey
            } | Sort-Object)
        }
    }

    # Output summary
    if (-not $Quiet) {
        foreach ($w in $warnings) {
            Write-Host "  [WARN] $w" -ForegroundColor Yellow
        }
        if ($loaded -gt 0 -or $skipped -gt 0) {
            Write-Host "User skills: $loaded loaded" -ForegroundColor DarkGray -NoNewline
            if ($skipped -gt 0) {
                Write-Host ", $skipped skipped" -ForegroundColor Yellow -NoNewline
            }
            Write-Host ""
        }
    }
}

function New-UserSkillScriptBlock {
    <#
    .SYNOPSIS
    Factory function that creates a scriptblock for a user skill with captured variables.
    This avoids $using: scope issues with closures.
    #>
    param(
        [array]$Steps,
        [string[]]$ParamNames,
        [hashtable]$Defaults,
        [string]$SkillName
    )

    return {
        # Collect positional args into a hashtable keyed by parameter name
        $argValues = @{}
        for ($i = 0; $i -lt $ParamNames.Count; $i++) {
            if ($i -lt $args.Count -and $null -ne $args[$i] -and $args[$i] -ne '') {
                $argValues[$ParamNames[$i]] = $args[$i]
            }
            elseif ($Defaults.ContainsKey($ParamNames[$i])) {
                $argValues[$ParamNames[$i]] = $Defaults[$ParamNames[$i]]
            }
        }

        $results = @()
        $stepNum = 0
        foreach ($step in $Steps) {
            $stepNum++

            if ($step.intent) {
                $intentPayload = @{ intent = $step.intent }
                if ($step.params) {
                    foreach ($pk in $step.params.PSObject.Properties) {
                        $val = $pk.Value
                        foreach ($ak in $argValues.Keys) {
                            $val = $val -replace "\{$ak\}", $argValues[$ak]
                        }
                        $intentPayload[$pk.Name] = $val
                    }
                }
                try {
                    $r = Invoke-IntentAction -Intent $step.intent -Payload $intentPayload -AutoConfirm
                    $results += $r
                    if (-not $r.Success) {
                        return @{
                            Success = $false
                            Output  = "Step $stepNum ($($step.intent)) failed: $($r.Output)"
                            Error   = $true
                        }
                    }
                }
                catch {
                    return @{
                        Success = $false
                        Output  = "Step $stepNum ($($step.intent)) error: $($_.Exception.Message)"
                        Error   = $true
                    }
                }
            }
            elseif ($step.command) {
                $cmd = $step.command
                foreach ($ak in $argValues.Keys) {
                    $cmd = $cmd -replace "\{$ak\}", $argValues[$ak]
                }
                try {
                    $output = Invoke-Expression $cmd 2>&1
                    $outputStr = if ($output) { ($output | Out-String).Trim() } else { 'OK' }
                    $results += @{ Success = $true; Output = $outputStr }
                }
                catch {
                    return @{
                        Success = $false
                        Output  = "Step $stepNum command failed: $($_.Exception.Message)"
                        Error   = $true
                    }
                }
            }
        }

        $allOutput = ($results | ForEach-Object {
            if ($_.Output) { $_.Output }
        }) -join "`n"
        @{ Success = $true; Output = if ($allOutput) { $allOutput } else { "Skill '$SkillName' completed ($stepNum steps)" } }
    }.GetNewClosure()
}

function Invoke-UserSkill {
    <#
    .SYNOPSIS
    Execute a user-defined skill by name, with optional parameter substitution.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$Parameters = @{}
    )

    if (-not $global:LoadedUserSkills.Contains($Name)) {
        return @{ Success = $false; Output = "Skill '$Name' not found"; Error = $true }
    }

    # The skill's scriptblock is already registered in IntentAliases
    $sb = $global:IntentAliases[$Name]
    if (-not $sb) {
        return @{ Success = $false; Output = "Skill '$Name' has no registered action"; Error = $true }
    }

    # Build positional args array matching the declared parameter order
    $skillMeta = $global:LoadedUserSkills[$Name]
    $posArgs = @()
    foreach ($pName in $skillMeta.Parameters) {
        if ($Parameters.ContainsKey($pName)) {
            $posArgs += $Parameters[$pName]
        }
        else {
            $posArgs += ''
        }
    }

    try {
        $result = & $sb @posArgs
        # Normalize: if the scriptblock returned a hashtable with Output, extract it
        if ($result -is [hashtable] -and $result.ContainsKey('Output')) {
            return $result
        }
        # If it returned raw output (string/array), wrap it
        $output = if ($result) { ($result | Out-String).Trim() } else { '' }
        return @{ Success = $true; Output = $output }
    }
    catch {
        return @{ Success = $false; Output = $_.Exception.Message; Error = $true }
    }
}

function Unregister-UserSkills {
    <#
    .SYNOPSIS
    Remove all user-skill intents from the global registries.
    #>
    foreach ($skillName in @($global:LoadedUserSkills.Keys)) {
        # Remove trigger aliases first
        $skillInfo = $global:LoadedUserSkills[$skillName]
        if ($skillInfo.Triggers) {
            foreach ($trigger in $skillInfo.Triggers) {
                $global:IntentAliases.Remove($trigger)
            }
        }
        $global:IntentAliases.Remove($skillName)
        $global:IntentMetadata.Remove($skillName)
        Remove-Item "function:$skillName" -Force -ErrorAction SilentlyContinue
    }
    $global:LoadedUserSkills = [ordered]@{}

    # Rebuild IntentCategories
    foreach ($catKey in $global:CategoryDefinitions.Keys) {
        $global:IntentCategories[$catKey] = @{
            Name        = $global:CategoryDefinitions[$catKey].Name
            Description = $global:CategoryDefinitions[$catKey].Description
            Intents     = @($global:IntentMetadata.Keys | Where-Object {
                $global:IntentMetadata[$_].Category -eq $catKey
            } | Sort-Object)
        }
    }
}

function Get-UserSkills {
    <#
    .SYNOPSIS
    List all user-defined skills and their configuration.
    #>
    if ($global:LoadedUserSkills.Count -eq 0) {
        Write-Host "No user skills loaded." -ForegroundColor DarkGray
        Write-Host "Create UserSkills.json (see UserSkills.example.json) and run 'reload-skills'." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n===== User Skills =====" -ForegroundColor Cyan

    foreach ($name in $global:LoadedUserSkills.Keys) {
        $skill = $global:LoadedUserSkills[$name]
        Write-Host "`n  $name" -ForegroundColor Yellow -NoNewline
        Write-Host " ($($skill.Steps) steps)" -ForegroundColor DarkGray
        if ($skill.Description) {
            Write-Host "    $($skill.Description)" -ForegroundColor Gray
        }
        if ($skill.Parameters.Count -gt 0) {
            Write-Host "    Params:   $($skill.Parameters -join ', ')" -ForegroundColor DarkGray
        }
        if ($skill.Triggers.Count -gt 0) {
            Write-Host "    Triggers: $($skill.Triggers -join ', ')" -ForegroundColor DarkGray
        }
        if ($skill.Confirm) {
            Write-Host "    Safety:   RequiresConfirmation" -ForegroundColor DarkCyan
        }
    }

    Write-Host ""
}

function New-UserSkill {
    <#
    .SYNOPSIS
    Interactive helper to create a new user skill and save it to UserSkills.json.

    .PARAMETER Name
    The intent name for the skill (e.g. deploy_staging).

    .PARAMETER Description
    Short description of what the skill does.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Description = ''
    )

    $safeName = $Name -replace '[^a-zA-Z0-9_]', '_'

    # Load existing file or create skeleton
    $data = $null
    if (Test-Path $global:UserSkillsPath) {
        try {
            $data = Get-Content $global:UserSkillsPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Host "Error reading existing UserSkills.json: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    if (-not $data) {
        $data = [PSCustomObject]@{ skills = [PSCustomObject]@{} }
    }

    if ($data.skills.PSObject.Properties.Name -contains $safeName) {
        Write-Host "Skill '$safeName' already exists in UserSkills.json." -ForegroundColor Yellow
        return
    }

    # Collect steps interactively
    Write-Host "`nAdding skill: $safeName" -ForegroundColor Cyan
    if (-not $Description) {
        $Description = Read-Host "Description"
    }

    $steps = @()
    $stepNum = 1
    Write-Host "Enter steps (type 'done' when finished):" -ForegroundColor DarkGray
    Write-Host "  Prefix with 'intent:' for intent calls, otherwise treated as PowerShell command." -ForegroundColor DarkGray

    while ($true) {
        $userInput = Read-Host "  Step $stepNum"
        if ($userInput -eq 'done' -or $userInput -eq '') { break }

        if ($userInput -like 'intent:*') {
            $intentName = ($userInput -replace '^intent:\s*', '').Trim()
            $steps += [PSCustomObject]@{ intent = $intentName }
        }
        else {
            $steps += [PSCustomObject]@{ command = $userInput }
        }
        $stepNum++
    }

    if ($steps.Count -eq 0) {
        Write-Host "No steps provided. Skill not created." -ForegroundColor Yellow
        return
    }

    # Build skill object
    $newSkill = [PSCustomObject]@{
        description = $Description
        steps       = $steps
    }

    # Add to data
    $data.skills | Add-Member -NotePropertyName $safeName -NotePropertyValue $newSkill -Force

    # Save
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $global:UserSkillsPath -Encoding UTF8
    Write-Host "Skill '$safeName' saved to UserSkills.json ($($steps.Count) steps)." -ForegroundColor Green
    Write-Host "Run 'reload-skills' to load it." -ForegroundColor DarkGray
}

function Remove-UserSkill {
    <#
    .SYNOPSIS
    Remove a user skill from UserSkills.json and unregister it.

    .PARAMETER Name
    The skill name to remove.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-Path $global:UserSkillsPath)) {
        Write-Host "No UserSkills.json found." -ForegroundColor Yellow
        return
    }

    try {
        $data = Get-Content $global:UserSkillsPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "Error reading UserSkills.json: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    if (-not ($data.skills.PSObject.Properties.Name -contains $Name)) {
        Write-Host "Skill '$Name' not found in UserSkills.json." -ForegroundColor Yellow
        return
    }

    # Remove from JSON
    $data.skills.PSObject.Properties.Remove($Name)
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $global:UserSkillsPath -Encoding UTF8

    # Remove trigger aliases
    if ($global:LoadedUserSkills.Contains($Name)) {
        $skillInfo = $global:LoadedUserSkills[$Name]
        if ($skillInfo.Triggers) {
            foreach ($trigger in $skillInfo.Triggers) {
                $global:IntentAliases.Remove($trigger)
            }
        }
    }

    # Remove from registries
    if ($global:IntentAliases.Contains($Name)) {
        $global:IntentAliases.Remove($Name)
    }
    if ($global:IntentMetadata.ContainsKey($Name)) {
        $global:IntentMetadata.Remove($Name)
    }
    if ($global:LoadedUserSkills.Contains($Name)) {
        $global:LoadedUserSkills.Remove($Name)
    }
    Remove-Item "function:$Name" -Force -ErrorAction SilentlyContinue

    # Rebuild IntentCategories
    foreach ($catKey in $global:CategoryDefinitions.Keys) {
        $global:IntentCategories[$catKey] = @{
            Name        = $global:CategoryDefinitions[$catKey].Name
            Description = $global:CategoryDefinitions[$catKey].Description
            Intents     = @($global:IntentMetadata.Keys | Where-Object {
                $global:IntentMetadata[$_].Category -eq $catKey
            } | Sort-Object)
        }
    }

    Write-Host "Skill '$Name' removed." -ForegroundColor Green
}

function Get-UserSkillsPrompt {
    <#
    .SYNOPSIS
    Generate an AI system prompt section listing user-defined skill intents
    for inclusion in Get-SafeCommandsPrompt.
    #>
    if ($global:LoadedUserSkills.Count -eq 0) { return "" }

    $lines = @("USER SKILLS:")
    foreach ($skillName in $global:LoadedUserSkills.Keys) {
        $example = @{ intent = $skillName }
        if ($global:IntentMetadata.ContainsKey($skillName)) {
            $meta = $global:IntentMetadata[$skillName]
            foreach ($p in $meta.Parameters) {
                $example[$p.Name] = $p.Description
            }
        }
        $lines += ($example | ConvertTo-Json -Compress)
    }

    return ($lines -join "`n")
}

# ===== Tab Completion =====
$_userSkillNameCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $global:LoadedUserSkills.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Skill: $_")
    }
}

Register-ArgumentCompleter -CommandName Remove-UserSkill  -ParameterName Name -ScriptBlock $_userSkillNameCompleter
Register-ArgumentCompleter -CommandName Invoke-UserSkill  -ParameterName Name -ScriptBlock $_userSkillNameCompleter

# ===== Aliases =====
Set-Alias skills     Get-UserSkills    -Force
Set-Alias new-skill  New-UserSkill     -Force

# Auto-load on module import
Import-UserSkills -Quiet
