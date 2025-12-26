# ===== CommandValidation.ps1 =====
# Command safety classification and validation for AI execution
# Consolidates $Actions, $CommandSafety, and validation functions

# ===== Command Safety Classifications =====
# Safety Levels: 'ReadOnly', 'SafeWrite', 'RequiresConfirmation'

$global:CommandSafety = @{
    # Read-Only Commands (no confirmation needed)
    'ReadOnly' = @(
        'get-computerinfo', 'get-process', 'get-service', 'get-hotfix', 'get-eventlog',
        'get-wmiobject', 'get-ciminstance', 'get-date', 'get-uptime', 'get-timezone',
        'get-childitem', 'get-item', 'get-itemproperty', 'get-content', 'test-path',
        'resolve-path', 'get-location', 'get-psdrive', 'measure-object', 'select-string',
        'get-acl', 'get-filehash',
        'test-netconnection', 'get-netadapter', 'get-netipaddress', 'get-netroute',
        'resolve-dnsname', 'test-connection', 'get-nettcpconnection',
        'convertto-json', 'convertfrom-json', 'convertto-csv', 'convertfrom-csv', 'convertto-xml',
        'convertto-html', 'format-table', 'format-list', 'sort-object', 'group-object', 
        'where-object', 'select-object', 'out-string', 'get-unique', 'tee-object',
        'measure-command', 'get-random',
        'get-variable', 'get-alias', 'get-command', 'get-module', 'get-pssnapin',
        'get-executionpolicy', 'get-host', 'get-culture', 'get-history',
        'get-help', 'get-member', 'compare-object',
        'set-location', 'push-location', 'pop-location'
    )
    
    # Safe Write Operations (minimal confirmation)
    'SafeWrite' = @(
        'new-item', 'new-temporaryfile', 'out-file', 'export-csv', 'export-clixml',
        'add-content', 'set-content', 'set-clipboard', 'get-clipboard'
    )
    
    # Requires Confirmation (potentially impactful)
    'RequiresConfirmation' = @(
        'copy-item', 'move-item', 'rename-item', 'remove-item',
        'compress-archive', 'expand-archive',
        'invoke-expression', 'invoke-command', 'start-process', 'start-job',
        'set-variable', 'set-item', 'set-itemproperty', 'clear-item', 'clear-content'
    )
}

# ===== Safe Actions Table with Descriptions =====
$global:Actions = @{
    # System Information (Read-only)
    'SystemInfo' = @{
        'get-computerinfo' = 'Get detailed computer information'
        'get-process' = 'List running processes'
        'get-service' = 'List system services'
        'get-hotfix' = 'List installed updates'
        'get-eventlog' = 'Read event logs (specify -LogName)'
        'get-wmiobject' = 'Query WMI objects (read-only)'
        'get-ciminstance' = 'Query CIM instances (read-only)'
        'get-date' = 'Get current date and time'
        'get-uptime' = 'Get system uptime'
        'get-timezone' = 'Get system timezone'
        'get-history' = 'Get command history'
    }
    
    # File System (Read-only and safe writes)
    'FileSystem' = @{
        'get-childitem' = 'List directory contents'
        'get-item' = 'Get file/directory information'
        'get-itemproperty' = 'Get file/directory properties'
        'get-content' = 'Read file contents'
        'test-path' = 'Test if path exists'
        'resolve-path' = 'Resolve path to absolute'
        'get-location' = 'Get current directory'
        'get-psdrive' = 'List available drives'
        'measure-object' = 'Measure file/object properties'
        'select-string' = 'Search text in files'
        'get-acl' = 'Get file/directory permissions'
        'get-filehash' = 'Calculate file hash'
    }
    
    # Navigation (safe - just changes directory)
    'Navigation' = @{
        'set-location' = 'Change current directory'
        'push-location' = 'Push directory onto stack'
        'pop-location' = 'Pop directory from stack'
    }
    
    # File Operations (potentially destructive)
    'FileOperations' = @{
        'new-item' = 'Create new file or directory'
        'copy-item' = 'Copy files or directories'
        'move-item' = 'Move files or directories'
        'rename-item' = 'Rename file or directory'
        'remove-item' = 'Delete file or directory (requires confirmation)'
        'add-content' = 'Append content to file'
        'set-content' = 'Write content to file'
        'clear-content' = 'Clear file contents'
    }
    
    # Network (Read-only)
    'Network' = @{
        'test-netconnection' = 'Test network connectivity'
        'get-netadapter' = 'Get network adapters'
        'get-netipaddress' = 'Get IP addresses'
        'get-netroute' = 'Get routing table'
        'resolve-dnsname' = 'Resolve DNS names'
        'test-connection' = 'Ping hosts'
        'get-nettcpconnection' = 'Get TCP connections'
    }
    
    # Text Processing
    'TextProcessing' = @{
        'convertto-json' = 'Convert objects to JSON'
        'convertfrom-json' = 'Parse JSON to objects'
        'convertto-csv' = 'Convert objects to CSV'
        'convertfrom-csv' = 'Parse CSV to objects'
        'convertto-xml' = 'Convert objects to XML'
        'convertto-html' = 'Convert objects to HTML'
        'format-table' = 'Format output as table'
        'format-list' = 'Format output as list'
        'sort-object' = 'Sort objects'
        'group-object' = 'Group objects'
        'where-object' = 'Filter objects'
        'select-object' = 'Select object properties'
        'out-string' = 'Convert output to string'
        'get-unique' = 'Get unique items'
        'tee-object' = 'Split output to file and pipeline'
    }
    
    # Math and Calculations
    'Math' = @{
        'measure-command' = 'Measure command execution time'
        'get-random' = 'Generate random numbers'
    }
    
    # Environment (Read-only)
    'Environment' = @{
        'get-variable' = 'Get PowerShell variables'
        'set-variable' = 'Set PowerShell variable'
        'get-alias' = 'Get command aliases'
        'get-command' = 'Get available commands'
        'get-module' = 'Get loaded modules'
        'get-pssnapin' = 'Get PowerShell snap-ins'
        'get-executionpolicy' = 'Get execution policy'
        'get-host' = 'Get PowerShell host info'
        'get-culture' = 'Get system culture'
    }
    
    # Safe File Operations
    'SafeFileOps' = @{
        'new-temporaryfile' = 'Create temporary file'
        'out-file' = 'Write to file (specify path)'
        'export-csv' = 'Export to CSV file'
        'export-clixml' = 'Export to XML file'
        'compress-archive' = 'Create ZIP archives'
        'expand-archive' = 'Extract ZIP archives'
    }
    
    # Registry (Read-only)
    'Registry' = @{
        'get-itemproperty' = 'Read registry values'
        'test-path' = 'Test registry path exists'
    }
    
    # PowerShell Specific
    'PowerShell' = @{
        'get-help' = 'Get command help'
        'get-member' = 'Get object members'
        'compare-object' = 'Compare objects'
        'invoke-expression' = 'Execute PowerShell expressions (use carefully)'
        'invoke-command' = 'Execute commands (local only)'
    }
    
    # Application Launching
    'ApplicationLaunch' = @{
        'start-process' = 'Launch applications and executables'
    }
    
    # Clipboard
    'Clipboard' = @{
        'get-clipboard' = 'Get clipboard contents'
        'set-clipboard' = 'Set clipboard contents'
    }
}

# ===== Validation Functions =====

function Get-CommandSafetyLevel {
    <#
    .SYNOPSIS
    Get the safety level of a command
    #>
    param([Parameter(Mandatory=$true)][string]$Command)
    
    $baseCommand = ($Command -split '\s+')[0].ToLower()
    
    foreach ($level in $global:CommandSafety.Keys) {
        if ($global:CommandSafety[$level] -contains $baseCommand) {
            return $level
        }
    }
    return 'Unknown'
}

function Test-PowerShellCommand {
    <#
    .SYNOPSIS
    Validate a PowerShell command against the safe actions list
    #>
    param([Parameter(Mandatory=$true)][string]$Command)
    
    $baseCommand = ($Command -split '\s+')[0].ToLower()
    
    foreach ($category in $global:Actions.Keys) {
        if ($global:Actions[$category].ContainsKey($baseCommand)) {
            $safetyLevel = Get-CommandSafetyLevel $baseCommand
            return @{
                IsValid = $true
                Category = $category
                Description = $global:Actions[$category][$baseCommand]
                Command = $baseCommand
                SafetyLevel = $safetyLevel
            }
        }
    }
    
    return @{
        IsValid = $false
        Command = $baseCommand
        SafetyLevel = 'Unknown'
    }
}

function Show-CommandConfirmation {
    <#
    .SYNOPSIS
    Show confirmation prompt for commands that require it
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(Mandatory=$true)][string]$SafetyLevel,
        [string]$Description = ""
    )
    
    switch ($SafetyLevel) {
        'SafeWrite' {
            Write-Host "`nSAFE WRITE OPERATION" -ForegroundColor Yellow
            Write-Host "Command: $Command" -ForegroundColor White
            if ($Description) { Write-Host "Description: $Description" -ForegroundColor Gray }
            Write-Host "This command will create/modify files but is considered safe." -ForegroundColor Gray
            
            do {
                $response = Read-Host "Proceed? (y/n)"
            } while ($response -notin @('y', 'n', 'yes', 'no'))
            
            return $response -in @('y', 'yes')
        }
        
        'RequiresConfirmation' {
            Write-Host "`nCONFIRMATION REQUIRED" -ForegroundColor Red
            Write-Host "Command: $Command" -ForegroundColor White
            if ($Description) { Write-Host "Description: $Description" -ForegroundColor Gray }
            Write-Host "This command can modify system state or execute code." -ForegroundColor Yellow
            Write-Host "Please review carefully before proceeding." -ForegroundColor Yellow
            
            do {
                $response = Read-Host "Are you sure you want to proceed? (yes/no)"
            } while ($response -notin @('yes', 'no'))
            
            return $response -eq 'yes'
        }
        
        default {
            return $true  # ReadOnly commands don't need confirmation
        }
    }
}

function Get-SafeActions {
    <#
    .SYNOPSIS
    List safe actions by category or search for a specific command
    #>
    param(
        [string]$Category = '',
        [string]$Command = ''
    )
    
    if ($Command) {
        # Search for specific command across all categories
        foreach ($cat in $global:Actions.Keys) {
            if ($global:Actions[$cat].ContainsKey($Command.ToLower())) {
                return @{
                    Category = $cat
                    Command = $Command.ToLower()
                    Description = $global:Actions[$cat][$Command.ToLower()]
                    SafetyLevel = Get-CommandSafetyLevel $Command
                }
            }
        }
        Write-Host "Command '$Command' not found in safe actions" -ForegroundColor Yellow
        return $null
    }
    
    if ($Category) {
        # Show commands in specific category
        if ($global:Actions.ContainsKey($Category)) {
            Write-Host "`n===== $Category Commands =====" -ForegroundColor Cyan
            $global:Actions[$Category].GetEnumerator() | Sort-Object Key | ForEach-Object {
                $safety = Get-CommandSafetyLevel $_.Key
                $safetyColor = switch ($safety) {
                    'ReadOnly' { 'Green' }
                    'SafeWrite' { 'Yellow' }
                    'RequiresConfirmation' { 'Red' }
                    default { 'Gray' }
                }
                Write-Host "  $($_.Key)" -ForegroundColor $safetyColor -NoNewline
                Write-Host " - $($_.Value)" -ForegroundColor Gray
            }
            Write-Host ""
        } else {
            Write-Host "Category '$Category' not found" -ForegroundColor Red
            Write-Host "Available categories: $($global:Actions.Keys -join ', ')" -ForegroundColor Yellow
        }
    } else {
        # Show all categories
        Write-Host "`n===== Safe Actions Categories =====" -ForegroundColor Cyan
        $global:Actions.Keys | Sort-Object | ForEach-Object {
            $count = $global:Actions[$_].Count
            Write-Host "  $_" -ForegroundColor Green -NoNewline
            Write-Host " ($count commands)" -ForegroundColor Gray
        }
        Write-Host "`nUse 'Get-SafeActions -Category <name>' to see commands in a category" -ForegroundColor DarkGray
        Write-Host "Use 'Get-SafeActions -Command <name>' to check if a command is safe" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Test-SafeAction {
    <#
    .SYNOPSIS
    Test if a command is in the safe actions list
    #>
    param([Parameter(Mandatory=$true)][string]$Command)
    
    $validation = Test-PowerShellCommand $Command
    if ($validation.IsValid) {
        $safetyIcon = switch ($validation.SafetyLevel) {
            'ReadOnly' { 'READ-ONLY' }
            'SafeWrite' { 'SAFE-WRITE' }
            'RequiresConfirmation' { 'CONFIRM' }
            default { '?' }
        }
        
        Write-Host "$safetyIcon '$Command' is a safe action ($($validation.SafetyLevel))" -ForegroundColor Green
        Write-Host "   Category: $($validation.Category)" -ForegroundColor Gray
        Write-Host "   Description: $($validation.Description)" -ForegroundColor Gray
        
        if ($validation.SafetyLevel -ne 'ReadOnly') {
            Write-Host "   WARNING: Requires confirmation before execution" -ForegroundColor Yellow
        }
        
        return $true
    } else {
        Write-Host "WARNING: '$Command' is not in the safe actions list" -ForegroundColor Red
        return $false
    }
}

function Invoke-SafeAction {
    <#
    .SYNOPSIS
    Execute a command after validating it's in the safe actions list
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [switch]$Force
    )
    
    $validation = Test-PowerShellCommand $Command
    
    if (-not $validation.IsValid) {
        Write-Host "WARNING: Command '$Command' is not in the safe actions list" -ForegroundColor Red
        return @{ Success = $false; Output = "Command not in safe actions list"; Error = $true }
    }
    
    # Check if confirmation is needed
    if (-not $Force -and $validation.SafetyLevel -ne 'ReadOnly') {
        $confirmed = Show-CommandConfirmation $Command $validation.SafetyLevel $validation.Description
        if (-not $confirmed) {
            Write-Host "Command execution cancelled by user." -ForegroundColor Yellow
            return @{ Success = $false; Output = "Cancelled by user"; Error = $false }
        }
    }
    
    try {
        Write-Host "Executing: $Command" -ForegroundColor Cyan
        $output = Invoke-Expression $Command | Out-String
        Write-Host "Command completed successfully." -ForegroundColor Green
        return @{ Success = $true; Output = $output; Error = $false }
    } catch {
        Write-Host "Error executing command: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; Output = $_.Exception.Message; Error = $true }
    }
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
    Execute a safe command with proper validation and confirmation (alias for Invoke-SafeAction)
    #>
    param([Parameter(Mandatory=$true)][string]$Command)
    
    $validation = Test-PowerShellCommand $Command
    
    if (-not $validation.IsValid) {
        return @{
            Success = $false
            Output = "Command '$Command' is not in the safe actions list"
            Error = $true
        }
    }
    
    # Check if confirmation is needed
    if ($validation.SafetyLevel -ne 'ReadOnly') {
        Write-Host "`nCommand requires confirmation: $Command" -ForegroundColor Yellow
        $confirmed = Show-CommandConfirmation $Command $validation.SafetyLevel $validation.Description
        if (-not $confirmed) {
            return @{
                Success = $false
                Output = "Command execution cancelled by user"
                Error = $false
            }
        }
    }
    
    try {
        Write-Host "Executing: $Command" -ForegroundColor Cyan
        $output = Invoke-Expression $Command | Out-String
        Write-Host "Command completed successfully." -ForegroundColor Green
        
        return @{
            Success = $true
            Output = $output
            Error = $false
        }
    } catch {
        return @{
            Success = $false
            Output = "Error: $($_.Exception.Message)"
            Error = $true
        }
    }
}

# ===== Aliases =====
Set-Alias actions Get-SafeActions -Force
Set-Alias safe-check Test-SafeAction -Force
Set-Alias safe-run Invoke-SafeAction -Force

Write-Verbose "CommandValidation loaded: Get-SafeActions, Test-SafeAction, Invoke-SafeAction"
