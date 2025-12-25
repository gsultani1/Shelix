# ===== MCPClient.ps1 =====
# MCP (Model Context Protocol) Client for PowerShell
# Connects to MCP servers via stdio transport and calls tools

# ===== MCP Server Registry =====
$global:MCPServers = @{}
$global:MCPConnections = @{}

# ===== JSON-RPC Message Helpers =====
function New-JsonRpcRequest {
    param(
        [string]$Method,
        [hashtable]$Params = @{},
        [int]$Id = (Get-Random -Maximum 999999)
    )
    
    @{
        jsonrpc = "2.0"
        id = $Id
        method = $Method
        params = $Params
    } | ConvertTo-Json -Depth 10 -Compress
}

function New-JsonRpcNotification {
    param(
        [string]$Method,
        [hashtable]$Params = @{}
    )
    
    @{
        jsonrpc = "2.0"
        method = $Method
        params = $Params
    } | ConvertTo-Json -Depth 10 -Compress
}

# ===== MCP Server Management =====
function Register-MCPServer {
    <#
    .SYNOPSIS
    Register an MCP server configuration
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Command,
        [string[]]$Args = @(),
        [string]$Description = "",
        [hashtable]$Env = @{}
    )
    
    $global:MCPServers[$Name] = @{
        Name = $Name
        Command = $Command
        Args = $Args
        Description = $Description
        Env = $Env
        Registered = Get-Date
    }
    
    Write-Host "Registered MCP server: $Name" -ForegroundColor Green
    return $global:MCPServers[$Name]
}

function Get-MCPServers {
    <#
    .SYNOPSIS
    List all registered MCP servers
    #>
    $global:MCPServers.Values | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Command = $_.Command
            Args = $_.Args -join " "
            Description = $_.Description
            Connected = $global:MCPConnections.ContainsKey($_.Name)
        }
    }
}

# ===== MCP Connection Management =====
function Connect-MCPServer {
    <#
    .SYNOPSIS
    Connect to a registered MCP server
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    if (-not $global:MCPServers.ContainsKey($Name)) {
        Write-Error "MCP server '$Name' not registered. Use Register-MCPServer first."
        return $null
    }
    
    $server = $global:MCPServers[$Name]
    
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $server.Command
        $psi.Arguments = $server.Args -join " "
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        foreach ($key in $server.Env.Keys) {
            $psi.EnvironmentVariables[$key] = $server.Env[$key]
        }
        
        $process = [System.Diagnostics.Process]::Start($psi)
        
        if (-not $process) {
            Write-Error "Failed to start MCP server process"
            return $null
        }
        
        $connection = @{
            Name = $Name
            Process = $process
            Writer = $process.StandardInput
            Reader = $process.StandardOutput
            ErrorReader = $process.StandardError
            Connected = Get-Date
            Tools = @()
            RequestId = 1
        }
        
        $global:MCPConnections[$Name] = $connection
        
        $initResult = Initialize-MCPConnection -Name $Name
        
        if ($initResult.Success) {
            Write-Host "Connected to MCP server: $Name" -ForegroundColor Green
            
            $toolsResult = Get-MCPTools -Name $Name
            if ($toolsResult.Success) {
                $connection.Tools = $toolsResult.Tools
                Write-Host "  Available tools: $($toolsResult.Tools.Count)" -ForegroundColor Cyan
                foreach ($tool in $toolsResult.Tools) {
                    Write-Host "    - $($tool.name): $($tool.description)" -ForegroundColor Gray
                }
            }
            
            return $connection
        }
        else {
            Write-Error "Failed to initialize MCP connection: $($initResult.Error)"
            Disconnect-MCPServer -Name $Name
            return $null
        }
    }
    catch {
        Write-Error "Failed to connect to MCP server: $($_.Exception.Message)"
        return $null
    }
}

function Disconnect-MCPServer {
    <#
    .SYNOPSIS
    Disconnect from an MCP server
    #>
    param([string]$Name)
    
    if ($global:MCPConnections.ContainsKey($Name)) {
        $conn = $global:MCPConnections[$Name]
        
        try {
            if ($conn.Process -and -not $conn.Process.HasExited) {
                $conn.Writer.Close()
                $conn.Process.Kill()
                $conn.Process.Dispose()
            }
        }
        catch { }
        
        $global:MCPConnections.Remove($Name)
        Write-Host "Disconnected from MCP server: $Name" -ForegroundColor Yellow
    }
}

function Disconnect-AllMCPServers {
    $names = @($global:MCPConnections.Keys)
    foreach ($name in $names) {
        Disconnect-MCPServer -Name $name
    }
}

# ===== MCP Protocol Implementation =====
function Send-MCPMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [int]$TimeoutSeconds = 30
    )
    
    if (-not $global:MCPConnections.ContainsKey($Name)) {
        return @{ Success = $false; Error = "Not connected to server '$Name'" }
    }
    
    $conn = $global:MCPConnections[$Name]
    
    try {
        $conn.Writer.WriteLine($Message)
        $conn.Writer.Flush()
        
        $task = $conn.Reader.ReadLineAsync()
        $completed = $task.Wait($TimeoutSeconds * 1000)
        
        if (-not $completed) {
            return @{ Success = $false; Error = "Timeout waiting for response" }
        }
        
        $response = $task.Result
        
        if (-not $response) {
            return @{ Success = $false; Error = "Empty response from server" }
        }
        
        $parsed = $response | ConvertFrom-Json
        
        if ($parsed.error) {
            return @{
                Success = $false
                Error = $parsed.error.message
                Code = $parsed.error.code
            }
        }
        
        return @{
            Success = $true
            Result = $parsed.result
            Id = $parsed.id
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Initialize-MCPConnection {
    param([string]$Name)
    
    $initRequest = New-JsonRpcRequest -Method "initialize" -Params @{
        protocolVersion = "2024-11-05"
        capabilities = @{
            roots = @{ listChanged = $true }
        }
        clientInfo = @{
            name = "PowerShell-MCP-Client"
            version = "1.0.0"
        }
    }
    
    $result = Send-MCPMessage -Name $Name -Message $initRequest
    
    if ($result.Success) {
        $notification = New-JsonRpcNotification -Method "notifications/initialized"
        $conn = $global:MCPConnections[$Name]
        $conn.Writer.WriteLine($notification)
        $conn.Writer.Flush()
        
        return @{
            Success = $true
            ServerInfo = $result.Result.serverInfo
            Capabilities = $result.Result.capabilities
        }
    }
    
    return $result
}

function Get-MCPTools {
    param([string]$Name)
    
    $request = New-JsonRpcRequest -Method "tools/list" -Params @{}
    $result = Send-MCPMessage -Name $Name -Message $request
    
    if ($result.Success) {
        return @{
            Success = $true
            Tools = $result.Result.tools
        }
    }
    
    return $result
}

function Invoke-MCPTool {
    <#
    .SYNOPSIS
    Call a tool on an MCP server
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerName,
        [Parameter(Mandatory=$true)]
        [string]$ToolName,
        [hashtable]$Arguments = @{}
    )
    
    if (-not $global:MCPConnections.ContainsKey($ServerName)) {
        return @{
            Success = $false
            Error = "Not connected to server '$ServerName'"
        }
    }
    
    $request = New-JsonRpcRequest -Method "tools/call" -Params @{
        name = $ToolName
        arguments = $Arguments
    }
    
    $result = Send-MCPMessage -Name $ServerName -Message $request
    
    if ($result.Success) {
        $content = $result.Result.content
        $output = ""
        
        foreach ($item in $content) {
            if ($item.type -eq "text") {
                $output += $item.text
            }
        }
        
        return @{
            Success = $true
            Output = $output
            Content = $content
            IsError = $result.Result.isError
        }
    }
    
    return $result
}

# ===== Pre-configured Popular MCP Servers =====
function Register-CommonMCPServers {
    <#
    .SYNOPSIS
    Register commonly used MCP servers (requires npx/node)
    #>
    
    # Filesystem server
    Register-MCPServer -Name "filesystem" `
        -Command "npx" `
        -Args @("-y", "@modelcontextprotocol/server-filesystem", $env:USERPROFILE) `
        -Description "File system access and operations"
    
    # Brave Search
    if ($env:BRAVE_API_KEY) {
        Register-MCPServer -Name "brave-search" `
            -Command "npx" `
            -Args @("-y", "@modelcontextprotocol/server-brave-search") `
            -Description "Web search via Brave Search API" `
            -Env @{ BRAVE_API_KEY = $env:BRAVE_API_KEY }
    }
    
    # GitHub
    if ($env:GITHUB_TOKEN) {
        Register-MCPServer -Name "github" `
            -Command "npx" `
            -Args @("-y", "@modelcontextprotocol/server-github") `
            -Description "GitHub repository operations" `
            -Env @{ GITHUB_PERSONAL_ACCESS_TOKEN = $env:GITHUB_TOKEN }
    }
    
    # Memory/Knowledge Graph
    Register-MCPServer -Name "memory" `
        -Command "npx" `
        -Args @("-y", "@modelcontextprotocol/server-memory") `
        -Description "Persistent memory and knowledge graph"
    
    # Fetch (web fetching)
    Register-MCPServer -Name "fetch" `
        -Command "npx" `
        -Args @("-y", "@modelcontextprotocol/server-fetch") `
        -Description "Fetch and parse web content"
    
    Write-Host "Registered common MCP servers. Use Get-MCPServers to list." -ForegroundColor Cyan
}

# ===== AI Integration =====
function Format-MCPToolsForAI {
    <#
    .SYNOPSIS
    Format available MCP tools for AI system prompt
    #>
    $output = "MCP TOOLS AVAILABLE:`n"
    
    foreach ($serverName in $global:MCPConnections.Keys) {
        $conn = $global:MCPConnections[$serverName]
        $output += "`n[$serverName]`n"
        
        foreach ($tool in $conn.Tools) {
            $output += "  - $($tool.name): $($tool.description)`n"
        }
    }
    
    return $output
}

# ===== Cleanup on Exit =====
try {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        Disconnect-AllMCPServers
    } -SupportEvent -ErrorAction SilentlyContinue
} catch { }

# ===== Aliases =====
Set-Alias mcp-servers Get-MCPServers -Force
Set-Alias mcp-connect Connect-MCPServer -Force
Set-Alias mcp-disconnect Disconnect-MCPServer -Force
Set-Alias mcp-call Invoke-MCPTool -Force
Set-Alias mcp-register Register-CommonMCPServers -Force

# ===== Export =====
$global:MCPClientAvailable = $true
