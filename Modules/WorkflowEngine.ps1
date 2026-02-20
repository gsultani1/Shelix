# ===== WorkflowEngine.ps1 =====
# Multi-step workflow definitions and execution engine.
# Loaded after IntentActions*.ps1 but before IntentRouter.ps1.

# Yes, I wrote this at 3am. No, I don't remember why it works.
$global:Workflows = @{
    "research_and_document" = @{
        Name        = "Research and Document"
        Description = "Research a topic, create a document with findings"
        Steps       = @(
            @{ Intent = "web_search"; ParamMap = @{ query = "topic" } }
            @{ Intent = "create_docx"; ParamMap = @{ name = "topic" }; Transform = { param($topic) "$topic - Research Notes" } }
        )
    }
    "daily_standup"         = @{
        Name        = "Daily Standup"
        Description = "Show calendar and git status for standup"
        Steps       = @(
            @{ Intent = "calendar_today" }
            @{ Intent = "git_status" }
        )
    }
    "project_setup"         = @{
        Name        = "Project Setup"
        Description = "Create folder, initialize git, open in editor"
        Steps       = @(
            @{ Intent = "create_folder"; ParamMap = @{ path = "project" } }
            @{ Intent = "git_init"; ParamMap = @{ path = "project" } }
        )
    }
}

function Invoke-Workflow {
    # This function is smarter than me on most days
    <#
    .SYNOPSIS
    Execute a multi-step workflow by name
    
    .EXAMPLE
    Invoke-Workflow -Name "daily_standup"
    Invoke-Workflow -Name "research_and_document" -Params @{ topic = "PowerShell MCP" }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [hashtable]$Params = @{}
    )
    
    if (-not $global:Workflows.ContainsKey($Name)) {
        Write-Host "Unknown workflow: $Name" -ForegroundColor Red
        Write-Host "Available workflows: $($global:Workflows.Keys -join ', ')" -ForegroundColor Yellow
        return @{ Success = $false; Error = "Unknown workflow" }
    }
    
    $workflow = $global:Workflows[$Name]
    Write-Host "`n===== Workflow: $($workflow.Name) =====" -ForegroundColor Cyan
    Write-Host $workflow.Description -ForegroundColor Gray
    Write-Host ""
    
    $results = @()
    $stepNum = 1
    
    foreach ($step in $workflow.Steps) {
        Write-Host "[$stepNum/$($workflow.Steps.Count)] Running: $($step.Intent)" -ForegroundColor Yellow
        
        # Build parameters for this step as a hashtable for proper multi-arg support
        $stepPayload = @{ intent = $step.Intent }
        if ($step.ParamMap) {
            foreach ($key in $step.ParamMap.Keys) {
                $sourceParam = $step.ParamMap[$key]
                if ($Params.ContainsKey($sourceParam)) {
                    $value = $Params[$sourceParam]
                    # Apply transform if exists
                    if ($step.Transform) {
                        $value = & $step.Transform $value
                    }
                    # Use the target param name (key), not source
                    $stepPayload[$key] = $value
                }
            }
        }
        
        # Execute the intent with full payload for multi-arg support
        try {
            $result = Invoke-IntentAction -Intent $step.Intent -Payload $stepPayload -AutoConfirm
            
            if ($result.Success) {
                Write-Host "  [OK] $($result.Output)" -ForegroundColor Green
            }
            else {
                Write-Host "  [FAIL] $($result.Output)" -ForegroundColor Red
            }
            $results += $result
        }
        catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
            $results += @{ Success = $false; Error = $_.Exception.Message }
        }
        
        $stepNum++
    }
    
    Write-Host "`n===== Workflow Complete =====" -ForegroundColor Cyan
    
    # Toast on workflow completion
    if (Get-Command Send-ShелixToast -ErrorAction SilentlyContinue) {
        $allOk = ($results | Where-Object { -not $_.Success }).Count -eq 0
        if ($allOk) {
            Send-ShелixToast -Title "Workflow complete" -Message $WorkflowName -Type Success
        }
        else {
            $failCount = ($results | Where-Object { -not $_.Success }).Count
            Send-ShелixToast -Title "Workflow finished with errors" -Message "$WorkflowName — $failCount step(s) failed" -Type Warning
        }
    }
    
    return @{
        Success = ($results | Where-Object { -not $_.Success }).Count -eq 0
        Results = $results
    }
}

function Get-Workflows {
    <#
    .SYNOPSIS
    List available workflows
    #>
    Write-Host "`n===== Available Workflows =====" -ForegroundColor Cyan
    foreach ($name in $global:Workflows.Keys | Sort-Object) {
        $wf = $global:Workflows[$name]
        Write-Host "`n$name" -ForegroundColor Yellow
        Write-Host "  $($wf.Description)" -ForegroundColor Gray
        Write-Host "  Steps: $($wf.Steps.Count)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

Set-Alias workflow Invoke-Workflow -Force
Set-Alias workflows Get-Workflows -Force
