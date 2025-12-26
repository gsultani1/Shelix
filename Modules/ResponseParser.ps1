# ===== ResponseParser.ps1 =====
# Parse AI responses for intents, commands, and format markdown output

function Convert-JsonIntent {
    <#
    .SYNOPSIS
    Enhanced parser for JSON content and PowerShell command validation with automatic execution
    #>
    param([string]$text)
    
    $lines = $text -split "`n"
    $result = @()
    $inJsonBlock = $false
    $inCodeBlock = $false
    $jsonBuffer = @()
    $braceCount = 0
    $codeBlockType = ''
    $executionResults = @()
    $executionCount = 0
    
    foreach ($line in $lines) {
        # Handle code blocks
        if ($line -match '^```(\w*)') {
            if (-not $inCodeBlock) {
                $inCodeBlock = $true
                $codeBlockType = $Matches[1].ToLower()
                $result += $line
            } else {
                $inCodeBlock = $false
                $codeBlockType = ''
                $result += $line
            }
            continue
        }
        
        # Process PowerShell commands in code blocks
        if ($inCodeBlock -and ($codeBlockType -eq 'powershell' -or $codeBlockType -eq 'ps1' -or $codeBlockType -eq '')) {
            # Check if line looks like a PowerShell command
            if ($line -match '^\s*([a-zA-Z][a-zA-Z0-9-]*)(\s|$)') {
                $validation = Test-PowerShellCommand $line.Trim()
                if ($validation.IsValid) {
                    $safetyIcon = switch ($validation.SafetyLevel) {
                        'ReadOnly' { 'READONLY' }
                        'SafeWrite' { 'SAFEWRITE' }
                        'RequiresConfirmation' { 'CONFIRM' }
                        default { 'UNKNOWN' }
                    }
                    $result += "$line  # $safetyIcon $($validation.SafetyLevel): $($validation.Category) - $($validation.Description)"
                } else {
                    $result += "$line  #  Not in safe actions list"
                }
            } else {
                $result += $line
            }
            continue
        }
        
        # Handle JSON execution requests and intent actions
        if (-not $inCodeBlock -and -not $inJsonBlock) {
            # Check for JSON intent action request
            if ($line -match '^\s*\{.*"intent".*:.*\}\s*$') {
                try {
                    $jsonRequest = $line | ConvertFrom-Json
                    if ($jsonRequest.intent -and $executionCount -lt $global:MaxExecutionsPerMessage) {
                        $executionCount++
                        $result += "**Intent Action**: ``$($jsonRequest.intent)``"
                        $result += ""
                        
                        # Extract first parameter - AI may use 'param', 'query', 'path', 'url', 'name', etc.
                        $param1 = if ($jsonRequest.param) { $jsonRequest.param }
                                  elseif ($jsonRequest.query) { $jsonRequest.query }
                                  elseif ($jsonRequest.path) { $jsonRequest.path }
                                  elseif ($jsonRequest.url) { $jsonRequest.url }
                                  elseif ($jsonRequest.name) { $jsonRequest.name }
                                  elseif ($jsonRequest.topic) { $jsonRequest.topic }
                                  elseif ($jsonRequest.text) { $jsonRequest.text }
                                  else { "" }
                        
                        # Use the intent router
                        $intentResult = Invoke-IntentAction -Intent $jsonRequest.intent -Param $param1 -Param2 $jsonRequest.param2 -AutoConfirm
                        $executionResults += $intentResult
                        
                        if ($intentResult.Success) {
                            $result += "**Intent Executed** (ID: $($intentResult.IntentId))"
                            if ($intentResult.Output) {
                                $result += "$($intentResult.Output)"
                            }
                            if ($intentResult.ExecutionTime) {
                                $result += "*Execution time: $([math]::Round($intentResult.ExecutionTime, 2))s*"
                            }
                        } else {
                            $result += "**Intent Failed** (ID: $($intentResult.IntentId))"
                            $result += "``$($intentResult.Output)``"
                        }
                        $result += ""
                        continue
                    }
                } catch {
                    # Not valid intent JSON, continue with normal processing
                }
            }
            
            # Check for JSON execution request
            if ($line -match '^\s*\{.*"action".*:.*"execute".*\}\s*$' -or $line -match '^\s*\{.*"execute".*:.*\}\s*$') {
                try {
                    $jsonRequest = $line | ConvertFrom-Json
                    $commandToExecute = ""
                    
                    # Support different JSON formats
                    if ($jsonRequest.action -eq "execute" -and $jsonRequest.command) {
                        $commandToExecute = $jsonRequest.command
                    } elseif ($jsonRequest.execute) {
                        $commandToExecute = $jsonRequest.execute
                    }
                    
                    if ($commandToExecute -and $executionCount -lt $global:MaxExecutionsPerMessage) {
                        $executionCount++
                        $result += "**JSON Execution Request**: ``$commandToExecute``"
                        $result += ""
                        
                        # Use the AI dispatcher
                        $execResult = Invoke-AIExec -Command $commandToExecute -RequestSource "AI-JSON"
                        $executionResults += $execResult
                        
                        if ($execResult.Success) {
                            $result += "**Execution Successful** (ID: $($execResult.ExecutionId))"
                            if ($execResult.Output -and $execResult.Output.Length -gt 0) {
                                $result += '```'
                                $result += $execResult.Output
                                $result += '```'
                            }
                            if ($execResult.ExecutionTime) {
                                $result += "*Execution time: $([math]::Round($execResult.ExecutionTime, 2))s*"
                            }
                        } else {
                            if ($execResult.Error) {
                                $result += "**Execution Failed** (ID: $($execResult.ExecutionId))"
                            } else {
                                $result += "**Execution Cancelled** (ID: $($execResult.ExecutionId))"
                            }
                            $result += "``$($execResult.Output)``"
                        }
                        $result += ""
                        continue
                    } elseif ($executionCount -ge $global:MaxExecutionsPerMessage) {
                        $result += "**Execution limit reached** ($global:MaxExecutionsPerMessage per message)"
                        $result += ""
                    }
                } catch {
                    # Not valid JSON, continue with normal processing
                }
            }
            
            # Check for execution request syntax: EXECUTE: command or RUN: command
            if ($line -match '^\s*(EXECUTE|RUN):\s*(.+)$') {
                $commandToExecute = $Matches[2].Trim()
                
                if ($executionCount -lt $global:MaxExecutionsPerMessage) {
                    $executionCount++
                    $result += "**Executing Command**: ``$commandToExecute``"
                    $result += ""
                    
                    # Use the AI dispatcher
                    $execResult = Invoke-AIExec -Command $commandToExecute -RequestSource "AI-EXECUTE"
                    $executionResults += $execResult
                    
                    if ($execResult.Success) {
                        $result += "**Execution Successful** (ID: $($execResult.ExecutionId))"
                        if ($execResult.Output -and $execResult.Output.Length -gt 0) {
                            $result += '```'
                            $result += $execResult.Output
                            $result += '```'
                        }
                        if ($execResult.ExecutionTime) {
                            $result += "*Execution time: $([math]::Round($execResult.ExecutionTime, 2))s*"
                        }
                    } else {
                        if ($execResult.Error) {
                            $result += "**Execution Failed** (ID: $($execResult.ExecutionId))"
                        } else {
                            $result += "**Execution Cancelled** (ID: $($execResult.ExecutionId))"
                        }
                        $result += "``$($execResult.Output)``"
                    }
                    $result += ""
                    continue
                } else {
                    $result += "**Execution limit reached** ($global:MaxExecutionsPerMessage per message)"
                    $result += "Command: ``$commandToExecute``"
                    $result += ""
                    continue
                }
            }
            # Regular command suggestion (no execution)
            elseif ($line -match '^\s*([a-zA-Z][a-zA-Z0-9-]*)(\s|$)' -and $line -notmatch '^\s*#') {
                $validation = Test-PowerShellCommand $line.Trim()
                if ($validation.IsValid) {
                    $safetyIcon = switch ($validation.SafetyLevel) {
                        'ReadOnly' { 'Read Only' }
                        'SafeWrite' { 'Safe Write' }
                        'RequiresConfirmation' { 'Confirmation Required' }
                        default { 'Clarification Required' }
                    }

                    $result += '```powershell'
                    $result += "$($line.Trim())  # $safetyIcon $($validation.SafetyLevel): $($validation.Category)"
                    $result += '```'
                    $result += "Description: $($validation.Description)"
                    $result += "**To execute this command, use**: ``EXECUTE: $($line.Trim())``"

                    # Add confirmation prompt for non-read-only commands
                    if ($validation.SafetyLevel -ne 'ReadOnly') {
                        $result += ""
                        $result += "Confirmation Required: This command requires user confirmation before execution."
                        if ($validation.SafetyLevel -eq 'RequiresConfirmation') {
                            $result += "High Impact: Please review this command carefully as it can modify system state."
                        }
                    }
                    continue
                }
            }
        }

        # Handle JSON detection (existing logic)
        if (-not $inCodeBlock) {
            # Detect potential JSON start
            if ($line -match '^\s*\{' -or ($line -match '\{.*:.*\}' -and $line -match '".*"')) {
                $inJsonBlock = $true
                $jsonBuffer = @($line)
                $braceCount = ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count - ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count

                # Check if it's a single-line JSON
                if ($braceCount -eq 0) {
                    try {
                        $jsonObj = $line | ConvertFrom-Json -ErrorAction Stop
                        $result += '```json'
                        $result += ($jsonObj | ConvertTo-Json -Depth 10)
                        $result += '```'
                        $inJsonBlock = $false
                        $jsonBuffer = @()
                    } catch {
                        # Not valid JSON, treat as regular text
                        $result += $line
                        $inJsonBlock = $false
                        $jsonBuffer = @()
                    }
                }
            }
            elseif ($inJsonBlock) {
                $jsonBuffer += $line
                $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count - ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count

                # Check if JSON block is complete
                if ($braceCount -le 0) {
                    $jsonText = $jsonBuffer -join "`n"
                    try {
                        $jsonObj = $jsonText | ConvertFrom-Json -ErrorAction Stop
                        $result += '```json'
                        $result += ($jsonObj | ConvertTo-Json -Depth 10)
                        $result += '```'
                    } catch {
                        # Not valid JSON, add as regular text
                        $result += $jsonBuffer
                    }
                    $inJsonBlock = $false
                    $jsonBuffer = @()
                    $braceCount = 0
                }
            }
            else {
                # Regular text line
                $result += $line
            }
        } else {
            # Inside code block, add as-is
            $result += $line
        }
    }
    
    # Handle incomplete JSON blocks (add as regular text)
    if ($inJsonBlock -and $jsonBuffer.Count -gt 0) {
        $result += $jsonBuffer
    }
    
    # Add execution results to chat history for AI feedback loop
    if ($executionResults.Count -gt 0) {
        $executionSummary = "`n`n--- Execution Summary ---`n"
        foreach ($execResult in $executionResults) {
            $status = if ($execResult.Success) { "SUCCESS" } elseif ($execResult.Error) { "ERROR" } else { "CANCELLED" }
            $outputPreview = if ($execResult.Output.Length -gt 100) { $execResult.Output.Substring(0, 100) } else { $execResult.Output }
            $executionSummary += "$status (ID: $($execResult.ExecutionId)): $outputPreview`n"
        }
        $executionSummary += "--- End Summary ---"
        
        # Add to chat history so AI can see execution results
        $global:ChatSessionHistory += @{ role = "system"; content = $executionSummary }
    }
    
    return $result -join "`n"
}

function Format-Markdown {
    <#
    .SYNOPSIS
    Format and display markdown text with ANSI colors
    #>
    param([string]$text)
    
    # Ensure we have a string
    if ($null -eq $text -or $text -isnot [string]) {
        if ($text) { Write-Host $text }
        return
    }
    
    # Use glow if available for beautiful markdown rendering
    if ($global:UseGlowForMarkdown -and (Get-Command glow -ErrorAction SilentlyContinue)) {
        try {
            Write-Output $text | glow -
            return
        } catch {
            # Fall through to ANSI rendering
        }
    }
    
    # Fallback: ANSI escape sequence rendering
    $lines = $text -split "`n"
    $inCode = $false
    
    foreach ($line in $lines) {
        if ($line -match '^```') {
            $inCode = -not $inCode
            Write-Host '```' -ForegroundColor DarkGray
            continue
        }

        if ($inCode) {
            if ($line -match '^(#|//)') {
                Write-Host $line -ForegroundColor DarkGreen
            } elseif ($line -match '(\$|\w+\s*=)') {
                Write-Host $line -ForegroundColor Yellow
            } elseif ($line -match 'function|def|class|import|from|if|else|return|for|while|const|let|var') {
                Write-Host $line -ForegroundColor Magenta
            } else {
                Write-Host $line -ForegroundColor Gray
            }
        } else {
            # Handle headers
            if ($line -match '^#{1,3}\s+(.+)$') {
                Write-Host $Matches[1] -ForegroundColor Cyan
            }
            # Handle bold **text** - strip markers and print
            elseif ($line -match '\*\*(.+?)\*\*') {
                $cleaned = $line -replace '\*\*(.+?)\*\*', '$1'
                Write-Host $cleaned -ForegroundColor White
            }
            # Handle inline code `text` - strip markers and print in yellow
            elseif ($line -match '`(.+?)`') {
                $cleaned = $line -replace '`(.+?)`', '$1'
                Write-Host $cleaned -ForegroundColor Yellow
            }
            else {
                Write-Host $line -ForegroundColor White
            }
        }
    }
}

Write-Verbose "ResponseParser loaded: Convert-JsonIntent, Format-Markdown"
