# ===== ProfileHelp.ps1 =====
# Help, tips, and profile information display

function Show-ProfileTips {
    <#
    .SYNOPSIS
    Display quick reference for PowerShell profile commands
    #>
    Write-Host "`n===== PowerShell Profile Quick Reference =====" -ForegroundColor Cyan
    Write-Host "`nSystem & Diagnostics:" -ForegroundColor Yellow
    Write-Host "  sysinfo, hwinfo, uptime     - System information" -ForegroundColor White
    Write-Host "  devcheck                    - Verify dev tools" -ForegroundColor White
    Write-Host "  Show-Path                   - View PATH entries" -ForegroundColor White
    Write-Host "  refreshenv                  - Reload environment" -ForegroundColor White
    Write-Host "  sudo                        - Elevate to admin" -ForegroundColor White
    Write-Host "  ports [number]              - Check port usage" -ForegroundColor White
    Write-Host "  procs [name]                - List processes" -ForegroundColor White
    Write-Host "  Test-Port [host] [port]     - Test connectivity" -ForegroundColor White
    Write-Host "  Get-PublicIP                - Show public IP" -ForegroundColor White
    
    Write-Host "`nGit Shortcuts:" -ForegroundColor Yellow
    Write-Host "  gs, ga, gc [msg], gp, gl, gb, gco [branch]" -ForegroundColor White
    
    Write-Host "`nNavigation:" -ForegroundColor Yellow
    Write-Host "  .., ..., ~, docs, desktop, downloads" -ForegroundColor White
    
    Write-Host "`nDocker:" -ForegroundColor Yellow
    Write-Host "  dps, dpsa, dlog [container], dexec [container], dstop" -ForegroundColor White
    
    Write-Host "`nArchive:" -ForegroundColor Yellow
    Write-Host "  zip [source] [dest], unzip [source] [dest]" -ForegroundColor White
    
    Write-Host "`nLLM Chat:" -ForegroundColor Yellow
    Write-Host "  chat [provider]             - Start chat (default: ollama)" -ForegroundColor White
    Write-Host "  chat-ollama                 - Chat with local Ollama" -ForegroundColor White
    Write-Host "  chat-anthropic              - Chat with Claude API" -ForegroundColor White
    Write-Host "  chat-local                  - Chat with LM Studio" -ForegroundColor White
    Write-Host "  providers                   - Show available providers" -ForegroundColor White
    Write-Host "  Set-ChatApiKey              - Configure API keys" -ForegroundColor White
    Write-Host "  Get-ChatHistory             - View saved sessions" -ForegroundColor White
    Write-Host "  Import-Chat [file]          - Restore session" -ForegroundColor White
    
    Write-Host "`nAI Execution:" -ForegroundColor Yellow
    Write-Host "  AI can now execute commands automatically using:" -ForegroundColor White
    Write-Host "  - EXECUTE: [command]        - Direct execution syntax" -ForegroundColor White
    Write-Host "  - JSON: {`"action`":`"execute`",`"command`":`"...`"}" -ForegroundColor White
    Write-Host "  - All executions are logged and limited to $global:MaxExecutionsPerMessage per message" -ForegroundColor White
    
    Write-Host "`nSafe Actions:" -ForegroundColor Yellow
    Write-Host "  actions                     - View all safe command categories" -ForegroundColor White
    Write-Host "  actions -Category [name]    - View commands in category" -ForegroundColor White
    Write-Host "  safe-check [command]        - Check command safety level" -ForegroundColor White
    Write-Host "  safe-run [command]          - Execute command with confirmation" -ForegroundColor White
    Write-Host "  ai-exec [command]           - Execute command via AI dispatcher" -ForegroundColor White
    Write-Host "  exec-log                    - View AI execution log" -ForegroundColor White
    
    Write-Host "`nSafety & Undo:" -ForegroundColor Yellow
    Write-Host "  session-info                - View current session audit info" -ForegroundColor White
    Write-Host "  file-history                - View tracked file operations" -ForegroundColor White
    Write-Host "  undo                        - Undo last file operation" -ForegroundColor White
    Write-Host "  undo -Count N               - Undo last N file operations" -ForegroundColor White
    
    Write-Host "`nTerminal Tools:" -ForegroundColor Yellow
    Write-Host "  tools                       - Show installed terminal tools" -ForegroundColor White
    Write-Host "  cath [file]                 - Cat with syntax highlighting (bat)" -ForegroundColor White
    Write-Host "  md [file]                   - Render markdown (glow)" -ForegroundColor White
    Write-Host "  br                          - File explorer (broot)" -ForegroundColor White
    Write-Host "  vd [file]                   - Data viewer (visidata)" -ForegroundColor White
    Write-Host "  fh, ff, fd                  - Fuzzy history/file/dir (fzf)" -ForegroundColor White
    Write-Host "  rg [pattern]                - Fast search (ripgrep)" -ForegroundColor White
    
    Write-Host "`nPlugins:" -ForegroundColor Yellow
    Write-Host "  plugins                     - List active & disabled plugins" -ForegroundColor White
    Write-Host "  new-plugin [name]           - Scaffold a new plugin" -ForegroundColor White
    Write-Host "  Enable-ShelixPlugin [name]  - Activate a disabled plugin" -ForegroundColor White
    Write-Host "  Disable-ShelixPlugin [name] - Deactivate a loaded plugin" -ForegroundColor White
    Write-Host "  reload-plugins              - Reload all plugins" -ForegroundColor White

    Write-Host "`nModule Management:" -ForegroundColor Yellow
    Write-Host "  reload-all                  - Reload all modules" -ForegroundColor White
    Write-Host "  reload-intents              - Reload intent system" -ForegroundColor White
    Write-Host "  reload-providers            - Reload chat providers" -ForegroundColor White

    Write-Host "`n==============================================`n" -ForegroundColor Cyan
}

function Get-ProfileTiming {
    <#
    .SYNOPSIS
    Display profile load timing information
    #>
    Write-Host "`n===== Profile Load Timing =====" -ForegroundColor Cyan
    Write-Host "  Total load time: $([math]::Round($global:ProfileLoadTime.TotalMilliseconds))ms" -ForegroundColor White
    Write-Host "  Session ID: $($global:SessionId)" -ForegroundColor Gray
    Write-Host "  Session started: $($global:SessionStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    
    Write-Host "`nLazy-loaded modules:" -ForegroundColor Yellow
    foreach ($mod in $global:LazyModules.Keys) {
        $status = if ($global:LazyModules[$mod]) { "Loaded" } else { "Not loaded (on-demand)" }
        $color = if ($global:LazyModules[$mod]) { "Green" } else { "DarkGray" }
        Write-Host "  $mod : $status" -ForegroundColor $color
    }
    
    # Show plugin load times
    if ($global:LoadedPlugins -and $global:LoadedPlugins.Count -gt 0) {
        Write-Host "`nPlugins:" -ForegroundColor Yellow
        foreach ($name in $global:LoadedPlugins.Keys) {
            $p = $global:LoadedPlugins[$name]
            $vStr = if ($p.Version) { " v$($p.Version)" } else { "" }
            Write-Host "  $name$vStr : $($p.LoadTimeMs)ms ($($p.Intents.Count) intents)" -ForegroundColor Green
        }
    }

    Write-Host "`nTo load modules manually:" -ForegroundColor Yellow
    Write-Host "  Enable-TerminalIcons  - Load Terminal-Icons" -ForegroundColor Gray
    Write-Host "  Enable-PoshGit        - Load posh-git" -ForegroundColor Gray
    Write-Host "================================`n" -ForegroundColor Cyan
}

function Get-SafeCommandsPrompt {
    $prompt = @'
You are a PowerShell assistant that executes user requests using intents.

RULES:
1. When user asks you to DO something, use the appropriate intent
2. Output JSON intents as PLAIN TEXT on their own line
   WRONG: ```{"intent":"..."}``` or ```json{"intent":"..."}```
   RIGHT: {"intent":"create_docx","name":"file"}
   Never wrap intents in code blocks, backticks, or markdown formatting
3. One intent per action
4. For conversation/questions without action requests, respond normally

INTENTS:

DOCUMENTS:
{"intent":"create_docx","name":"filename"}
{"intent":"create_xlsx","name":"filename"}
{"intent":"create_csv","name":"filename","headers":"col1,col2"}

FILES:
{"intent":"open_file","path":"C:\\file.txt"}
{"intent":"read_file","path":"C:\\file.txt"}
{"intent":"read_file_content","path":"C:\\file.txt","lines":10}
{"intent":"file_stats","path":"C:\\file.txt"}
{"intent":"search_file","term":"keyword","path":"C:\\folder"}
{"intent":"open_recent","count":5}
{"intent":"open_folder","path":"C:\\folder"}

FILESYSTEM:
{"intent":"create_folder","path":"C:\\newfolder"}
{"intent":"rename_file","path":"C:\\old.txt","newname":"new.txt"}
{"intent":"move_file","source":"C:\\a.txt","destination":"C:\\b.txt"}
{"intent":"copy_file","source":"C:\\a.txt","destination":"C:\\b.txt"}
{"intent":"delete_file","path":"C:\\file.txt"}
{"intent":"list_files","path":"C:\\folder"}
{"intent":"write_to_file","path":"C:\\file.txt","content":"text"}
{"intent":"append_to_file","path":"C:\\file.txt","content":"more text"}

APPS:
{"intent":"open_word"}
{"intent":"open_excel"}
{"intent":"open_powerpoint"}
{"intent":"open_notepad"}
{"intent":"open_calculator"}
{"intent":"open_browser","browser":"chrome"}
{"intent":"open_terminal","path":"C:\\folder"}

WEB:
{"intent":"open_url","url":"https://google.com"}
{"intent":"open_browser_search","query":"search terms"}
{"intent":"browse_web","url":"https://example.com"}
{"intent":"web_search","query":"terms"}
{"intent":"wikipedia","query":"topic"}
{"intent":"fetch_url","url":"https://api.example.com"}

CLIPBOARD:
{"intent":"clipboard_read"}
{"intent":"clipboard_write","text":"content"}
{"intent":"clipboard_format_json"}
{"intent":"clipboard_case","case":"upper"}

GIT:
{"intent":"git_status"}
{"intent":"git_log","count":10}
{"intent":"git_commit","message":"msg"}
{"intent":"git_push","message":"msg"}
{"intent":"git_pull"}
{"intent":"git_diff"}
{"intent":"git_init","path":"C:\\project"}

CALENDAR:
{"intent":"calendar_today"}
{"intent":"calendar_week"}
{"intent":"calendar_create","subject":"Meeting","start":"2024-01-15 10:00","duration":60}

MCP:
{"intent":"mcp_servers"}
{"intent":"mcp_connect","server":"filesystem"}
{"intent":"mcp_tools","server":"filesystem"}
{"intent":"mcp_call","server":"filesystem","tool":"read_file","toolArgs":"{\"path\":\"C:\\\\file.txt\"}"}

SYSTEM:
{"intent":"system_info"}
{"intent":"network_status"}
{"intent":"process_list","filter":"chrome"}
{"intent":"process_kill","name":"notepad"}
{"intent":"service_status","name":"spooler"}
{"intent":"service_start","name":"spooler"}
{"intent":"service_stop","name":"spooler"}
{"intent":"service_restart","name":"spooler"}
{"intent":"services_list","filter":"print"}
{"intent":"scheduled_tasks","filter":"backup"}
{"intent":"scheduled_task_run","name":"MyTask"}
{"intent":"scheduled_task_enable","name":"MyTask"}
{"intent":"scheduled_task_disable","name":"MyTask"}

WORKFLOWS:
{"intent":"list_workflows"}
{"intent":"run_workflow","name":"daily_standup"}
{"intent":"run_workflow","name":"research_and_document","params":"{\"topic\":\"AI\"}"}
{"intent":"create_and_open_doc","name":"Report"}
{"intent":"research_topic","topic":"PowerShell automation"}
{"intent":"daily_standup"}

EXAMPLE:
User: "create a csv called inventory" -> {"intent":"create_csv","name":"inventory"}
User: "what time is it" -> (just answer, no intent needed)
'@
    
    if ($global:MCPConnections -and $global:MCPConnections.Count -gt 0) {
        $prompt += "`n`n" + (Get-MCPToolsPrompt)
    }

    if ($global:LoadedPlugins -and $global:LoadedPlugins.Count -gt 0) {
        $pluginPrompt = Get-PluginIntentsPrompt
        if ($pluginPrompt) {
            $prompt += "`n`n" + $pluginPrompt
        }
    }

    return $prompt
}

# ===== Aliases =====
Set-Alias tips Show-ProfileTips -Force
Set-Alias help-profile Show-ProfileTips -Force
Set-Alias profile-timing Get-ProfileTiming -Force

Write-Verbose "ProfileHelp loaded: Show-ProfileTips, Get-ProfileTiming, Get-SafeCommandsPrompt"
