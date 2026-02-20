@{
    RootModule        = 'BildsyPS.psm1'
    ModuleVersion     = '1.3.0'
    GUID              = 'cf4820d1-a29f-4454-b17f-eea35493bf40'
    Author            = 'Georg Sultani'
    CompanyName       = 'Georg Sultani'
    Copyright         = '(c) 2025 Georg Sultani. All rights reserved.'
    Description       = 'AI-powered shell orchestrator with 80+ intents, autonomous agent, vision, OCR, SQLite RAG, and plugin system for PowerShell 7+'
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @(
        # Chat session
        'Start-ChatSession', 'Save-Chat', 'Resume-Chat', 'Get-ChatSessions',
        'Search-ChatSessions', 'Remove-ChatSession', 'Export-ChatSession',
        'Import-Chat', 'Get-ChatHistory', 'Get-SessionSummary',

        # Chat providers
        'Invoke-ChatCompletion', 'Show-ChatProviders', 'Set-DefaultChatProvider',
        'Get-ChatApiKey', 'Set-ChatApiKey', 'Test-ChatProvider',
        'Get-ChatModels', 'Import-ChatConfig', 'Get-ModelContextLimit',

        # SQLite storage
        'Initialize-ChatDatabase', 'Save-ChatToDb', 'Resume-ChatFromDb',
        'Get-ChatSessionsFromDb', 'Search-ChatFTS', 'Remove-ChatSessionFromDb',
        'Rename-ChatSessionInDb', 'Export-ChatSessionFromDb', 'Import-JsonSessionsToDb',

        # Agent system
        'Invoke-AgentTask', 'Stop-AgentTask', 'Show-AgentSteps',
        'Show-AgentMemory', 'Show-AgentPlan',
        'Register-AgentTool', 'Invoke-AgentTool', 'Get-AgentTools', 'Get-AgentToolInfo',

        # Agent heartbeat
        'Invoke-AgentHeartbeat', 'Register-AgentHeartbeat', 'Unregister-AgentHeartbeat',
        'Add-AgentTask', 'Remove-AgentTask', 'Enable-AgentTask', 'Disable-AgentTask',
        'Show-AgentTaskList', 'Get-HeartbeatStatus', 'Get-AgentTaskList',

        # Intent system
        'Invoke-IntentAction', 'Test-Intent', 'Show-IntentHelp',
        'Get-IntentAliases', 'Get-IntentDescription', 'Get-IntentInfo',

        # Workflows
        'Invoke-Workflow', 'Get-Workflows',

        # Vision and OCR
        'Invoke-Vision', 'Send-ImageToAI', 'Test-VisionSupport',
        'New-VisionMessage', 'Capture-Screenshot', 'Resize-ImageBitmap',
        'Invoke-OCR', 'Invoke-OCRFile', 'ConvertFrom-PDF',
        'Send-ImageToAIWithFallback', 'Test-OCRAvailable', 'Test-PdftotextAvailable',

        # App Builder
        'New-AppBuild', 'Update-AppBuild', 'Get-AppBuilds', 'Remove-AppBuild',
        'Get-BuildFramework', 'Get-BuildMaxTokens', 'Test-GeneratedCode',
        'Build-PowerShellExecutable', 'Build-PythonExecutable',

        # Config
        'Import-EnvFile', 'Get-ConfigValue', 'Set-ConfigValue',

        # Security and safety
        'Test-PathAllowed', 'Test-UrlAllowed', 'Get-AllowedRoots',
        'Add-AllowedRoot', 'Remove-AllowedRoot',
        'Test-SafeAction', 'Invoke-SafeAction', 'Get-SafeActions',
        'Show-CommandConfirmation', 'Test-PowerShellCommand',
        'Invoke-AIExec', 'Test-RateLimit', 'Save-AIExecutionLog',
        'Get-AIExecutionLog', 'Get-FileOperationHistory', 'Undo-LastFileOperation',

        # Secret scanner
        'Invoke-SecretScan', 'Invoke-StartupSecretScan', 'Test-StartupSecrets',
        'Test-GitStagedSecrets', 'Test-GitignoreCovers', 'Show-SecretScanReport',

        # Navigation
        'Set-LocationWithHistory', 'Push-DirectoryHistory', 'Pop-DirectoryHistory',
        'Get-DirectoryHistory', 'Show-Tree',

        # System utilities
        'Get-SystemInfo', 'Get-PublicIP', 'Test-Port', 'Update-Environment',

        # Document tools
        'New-MinimalDocx', 'New-MinimalXlsx',

        # Web tools
        'Invoke-WebSearch', 'Search-Wikipedia', 'Search-News', 'Get-WebPageContent',

        # Productivity
        'Get-ClipboardContent', 'Set-ClipboardContent', 'Read-FileContent',
        'Get-GitStatus', 'Get-GitLog', 'Get-GitDiff', 'Get-OutlookCalendar',

        # Terminal tools
        'Show-Code', 'Show-Json', 'Show-Csv', 'Show-Data', 'Show-Diff', 'Show-Markdown',

        # Plugins
        'Import-BildsyPSPlugins', 'Get-BildsyPSPlugins', 'New-BildsyPSPlugin',
        'Unregister-BildsyPSPlugin', 'Test-BildsyPSPlugin',
        'Get-PluginConfig', 'Set-PluginConfig', 'Reset-PluginConfig',
        'Watch-BildsyPSPlugins', 'Stop-WatchBildsyPSPlugins',

        # Skills and aliases
        'New-UserSkill', 'Remove-UserSkill', 'Get-UserSkills', 'Import-UserSkills',
        'Add-PersistentAlias', 'Remove-PersistentAlias', 'Get-PersistentAliases',

        # Natural language
        'Import-NaturalLanguageMappings',

        # MCP
        'Register-MCPServer', 'Connect-MCPServer', 'Disconnect-MCPServer',
        'Get-MCPServers', 'Get-MCPTools', 'Get-AllMCPTools', 'Invoke-MCPTool',
        'Register-CommonMCPServers', 'Initialize-FilesystemMCP',

        # Platform utils
        'Test-IsWindows', 'Test-IsMacOS', 'Test-IsLinux',
        'Get-PlatformSeparator', 'Open-PlatformPath',

        # Code artifacts
        'Get-Artifacts', 'Save-Artifact', 'Save-AllArtifacts', 'Remove-Artifact',
        'Invoke-Artifact', 'Invoke-ArtifactFromChat', 'Show-SessionArtifacts',

        # Toast notifications
        'Send-InfoToast', 'Send-SuccessToast', 'Send-ErrorToast',

        # Folder context
        'Get-FolderContext', 'Show-FolderContext', 'Set-LocationWithContext',

        # FZF integration
        'Invoke-FzfFile', 'Invoke-FzfDirectory', 'Invoke-FzfHistory',
        'Invoke-FzfProcess', 'Invoke-FzfGitBranch',

        # Package manager
        'Install-Tool', 'Install-MissingTools', 'Get-ToolHealthReport', 'Test-ToolHealth',

        # Profile help
        'Show-ProfileTips', 'Get-ProfileTiming',

        # Install helper
        'Install-BildsyPS'
    )

    AliasesToExport = @(
        'cc', 'chat-ollama', 'chat-local', 'chat-anthropic', 'chat-llm',
        'chat-models', 'chat-test', 'providers',
        'agent', 'agent-stop', 'agent-steps', 'agent-memory', 'agent-plan', 'agent-tools',
        'heartbeat', 'heartbeat-tasks',
        'vision', 'ocr', 'builds', 'rebuild',
        'secrets', 'scan-secrets',
        'workflow', 'workflows',
        'plugins', 'new-plugin', 'test-plugin', 'watch-plugins', 'plugin-config',
        'skills', 'new-skill',
        'add-alias', 'remove-alias', 'list-aliases', 'reload-aliases',
        'tips', 'help-profile', 'profile-timing',
        'actions', 'safe-check', 'safe-run',
        'ai-exec', 'exec-log', 'file-history', 'undo', 'session-info',
        'tools', 'artifacts',
        'sysinfo', 'refreshenv',
        'health', 'install-tools',
        'back', 'dirs',
        'mcp-connect', 'mcp-disconnect', 'mcp-servers', 'mcp-tools', 'mcp-call',
        'mcp-init', 'mcp-register',
        'browser-url', 'browser-tabs', 'browser-page',
        'cleanup',
        'ff', 'fd', 'fh', 'fp', 'fgb',
        'zip', 'unzip', 'ziplist'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('AI', 'LLM', 'Claude', 'GPT', 'Ollama', 'Agent', 'Shell', 'Automation', 'Chat', 'Vision', 'OCR', 'SQLite', 'RAG')
            ProjectUri   = 'https://github.com/gsultani/bildsyps'
            LicenseUri   = 'https://github.com/gsultani/bildsyps/blob/main/LICENSE'
            ReleaseNotes = 'v1.3.0: SQLite RAG with FTS5, secret scanner, agent heartbeat, OCR integration, module packaging'
        }
    }
}
