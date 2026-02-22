# ===== AppBuilder.ps1 =====
# Prompt-to-executable pipeline. Generates code via LLM, validates, compiles to .exe.
# Three lanes: powershell (default, ps2exe), python-tk (PyInstaller), python-web (PyInstaller).
# Depends on: ChatProviders.ps1, CodeArtifacts.ps1, SecretScanner.ps1, ChatStorage.ps1

$global:AppBuilderPath = "$global:BildsyPSHome\builds"
$global:AppBuilderBranding = $true  # inject "Built with BildsyPS" branding

# ===== System Prompts =====

$script:BuilderRefinePrompt = @'
You are an application specification writer. Given a user's natural language description of an app they want built, produce a structured specification. Output ZERO code.

Output format (use these exact delimiters):

---BEGIN SPECIFICATION---
APP_NAME: (short, filesystem-safe name, lowercase with hyphens)
PURPOSE: (one sentence)
FRAMEWORK: {FRAMEWORK_PLACEHOLDER}
FEATURES:
- feature 1
- feature 2
DATA_MODEL:
- describe any data storage needs (files, SQLite, in-memory)
UI_LAYOUT:
- describe windows, panels, menus, buttons, layout
STYLING:
- dark theme (#1e1e1e background, #7c3aed accent, Segoe UI font)
EDGE_CASES:
- input validation, error states, empty states
---END SPECIFICATION---

Be specific and detailed. The specification will be handed to a code generator.
'@

$script:BuilderPowerShellPrompt = @'
You are a PowerShell application code generator. Given a specification, produce a complete, runnable PowerShell script that creates a Windows GUI application using Windows Forms (System.Windows.Forms).

RULES:
1. Output a SINGLE .ps1 file. Use fenced code block with filename: ```powershell app.ps1
2. Use only assemblies available in PowerShell 7+: System.Windows.Forms, System.Drawing, PresentationFramework (WPF)
3. Do NOT use any external modules. No Install-Module calls. No NuGet packages.
4. All code must be in a single file. No dot-sourcing other scripts.
5. Use proper error handling with try/catch blocks.
6. Dark theme: Background=#1e1e1e, Foreground=#e0e0e0, Accent=#7c3aed, Font=Segoe UI
7. Add a Help menu with an "About" item that shows a MessageBox:
   "Built with BildsyPS — AI-powered shell orchestrator`nhttps://github.com/gsultani/bildsyps"
8. If the app uses data persistence, use a JSON file in: Join-Path $env:APPDATA $appName
9. Add proper form disposal and cleanup.
10. The script must work when compiled to .exe via ps2exe.
11. Start with: Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Output ONLY the code block. No explanations before or after.
'@

$script:BuilderTkinterPrompt = @'
You are a Python Tkinter application code generator. Given a specification, produce a complete, runnable Python application using Tkinter.

RULES:
1. Output a SINGLE app.py file. Use fenced code block with filename: ```python app.py
2. Use ONLY Python standard library imports. No pip packages. No external dependencies.
3. All code in a single file. No separate modules.
4. Use proper error handling with try/except blocks.
5. Dark theme: bg=#1e1e1e, fg=#e0e0e0, accent=#7c3aed, font=("Segoe UI", 10)
6. Add a mandatory startup splash screen (1.5 seconds):
   - 400x200 window, centered, no title bar (overrideredirect=True)
   - Dark background (#1e1e1e), text "Built with BildsyPS" in #7c3aed, 16pt
   - Below: app name in #e0e0e0, 12pt
   - Auto-close after 1500ms via root.after()
7. Add a Help menu with "About" that shows:
   messagebox.showinfo("About", "Built with BildsyPS\nhttps://github.com/gsultani/bildsyps")
8. If the app uses data persistence, use JSON or SQLite in:
   Path.home() / f'.{app_name}' / 'data.json'
9. Use if __name__ == '__main__': guard.
10. Use ttk widgets where possible for native look.

Also output a requirements.txt file (empty or "# stdlib only"):
```text requirements.txt
# stdlib only - no external dependencies
```

Output ONLY the code blocks. No explanations before or after.
'@

$script:BuilderPyWebViewPrompt = @'
You are a Python PyWebView application code generator. Given a specification, produce a complete, runnable Python application using pywebview with an HTML/CSS/JS frontend.

RULES:
1. Output these files, each in its own fenced code block with filename:
   ```python app.py
   ```html web/index.html
   ```css web/style.css
   ```javascript web/script.js
   ```text requirements.txt
2. app.py: import webview, create window loading web/index.html, expose Python API class via js_api
3. ALLOWED imports: stdlib + pywebview + requests. Nothing else.
4. Dark theme in CSS: background=#1e1e1e, color=#e0e0e0, accent=#7c3aed, font-family="Segoe UI"
5. Add a branded startup splash overlay in index.html:
   - Full-screen overlay div, dark bg, "Built with BildsyPS" in accent color
   - Fades out after 1.5 seconds via CSS animation + JS setTimeout
   - Footer: <footer style="text-align:center;padding:8px;color:#666;font-size:11px">Built with BildsyPS</footer>
6. If the app uses data persistence, use JSON or SQLite in:
   Path.home() / f'.{app_name}' / 'data.json'
7. Use if __name__ == '__main__': guard in app.py.
8. requirements.txt must contain: pywebview

Output ONLY the code blocks. No explanations before or after.
'@

$script:BuilderModifyPrompt = @'
You are a code modification assistant. Given existing source code and a user's change request, output surgical edits using FIND/REPLACE blocks.

FORMAT:
<<<FIND
exact lines to find in the existing code
>>>REPLACE
replacement lines
<<<END

RULES:
1. Use exact string matching. Copy the FIND block character-for-character from the source.
2. Make the MINIMUM changes needed. Do not rewrite unrelated code.
3. You may output multiple FIND/REPLACE blocks.
4. For new code that doesn't replace anything, use:
   <<<ADD_AFTER
   line after which to insert
   >>>INSERT
   new lines to insert
   <<<END
5. For file creation, use:
   <<<NEW_FILE filename.ext
   file contents
   <<<END
6. For deletions, use an empty REPLACE block.
7. Preserve all existing branding (BildsyPS splash/about).
8. If the change requires a fundamentally different approach, say FULL_REGENERATION_NEEDED on its own line.
'@

# ===== Framework Routing =====

function Get-BuildFramework {
    <#
    .SYNOPSIS
    Deterministic keyword-based framework routing. AI is NOT trusted for this decision.
    #>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Framework
    )

    # User override wins
    if ($Framework) {
        $valid = @('powershell', 'python-tk', 'python-web')
        if ($Framework -in $valid) { return $Framework }
        Write-Host "[AppBuilder] Unknown framework '$Framework'. Valid: $($valid -join ', ')" -ForegroundColor Yellow
    }

    $lower = $Prompt.ToLower()

    # Explicit triggers
    if ($lower -match '\b(pywebview|html\s*ui|web\s*app|dashboard|charts?|modern\s*ui|drag\s*and\s*drop|responsive)\b') {
        return 'python-web'
    }
    if ($lower -match '\b(tkinter|tk\s*gui|python\s*gui|matplotlib|pyplot)\b') {
        return 'python-tk'
    }
    if ($lower -match '\b(python)\b' -and $lower -notmatch '\b(powershell|ps1|winforms|wpf)\b') {
        # Complexity heuristic: many features → pywebview
        $featureIndicators = @(' and ', ' with ', ' plus ', ' also ', ',')
        $featureCount = ($featureIndicators | ForEach-Object { [regex]::Matches($lower, [regex]::Escape($_)).Count } | Measure-Object -Sum).Sum
        $wordCount = ($lower -split '\s+').Count
        if ($wordCount -gt 50 -or $featureCount -ge 3) {
            return 'python-web'
        }
        return 'python-tk'
    }

    # Default: PowerShell (fastest, no external deps)
    return 'powershell'
}

# ===== Token Budget =====

function Get-BuildMaxTokens {
    <#
    .SYNOPSIS
    Determine max output tokens for code generation based on the model's actual output limit.
    No artificial caps — uses the model's real max output capacity.
    #>
    param(
        [Parameter(Mandatory)][string]$Framework,
        [string]$Model,
        [int]$Override = 0
    )

    if ($Override -gt 0) { return $Override }

    # Known max OUTPUT token limits per model (not context window)
    $outputLimits = @{
        'claude-sonnet-4-6'          = 64000
        'claude-opus-4-6'            = 128000
        'claude-sonnet-4-5-20250929' = 8192
        'claude-sonnet-4-5'          = 8192
        'claude-3-5-sonnet'          = 8192
        'claude-3-opus'              = 4096
        'claude-3-haiku'             = 4096
        'claude-haiku-4-5-20251001'  = 8192
        'gpt-4o'                     = 16384
        'gpt-4o-mini'                = 16384
        'gpt-4-turbo'                = 4096
        'gpt-4'                      = 8192
        'o1'                         = 32768
        'o1-mini'                    = 65536
    }

    # Exact match
    if ($Model -and $outputLimits.ContainsKey($Model)) {
        return $outputLimits[$Model]
    }

    # Fuzzy match: check if model name contains a known key (longest key first for specificity)
    if ($Model) {
        foreach ($key in ($outputLimits.Keys | Sort-Object { $_.Length } -Descending)) {
            if ($Model -like "*$key*") {
                return $outputLimits[$key]
            }
        }
    }

    # Default: 8192 is safe for most providers
    return 8192
}

# ===== Prompt Refinement =====

function Invoke-PromptRefinement {
    <#
    .SYNOPSIS
    LLM call #1: Convert user prompt into structured specification. No code generated.
    #>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Framework,
        [string]$Provider,
        [string]$Model
    )

    $frameworkLabel = switch ($Framework) {
        'powershell' { 'POWERSHELL (Windows Forms GUI, single .ps1 file, ps2exe compatible)' }
        'python-tk'  { 'PYTHON_TKINTER (single app.py, stdlib only)' }
        'python-web' { 'PYTHON_PYWEBVIEW (app.py + web/index.html + CSS + JS)' }
    }

    $systemPrompt = $script:BuilderRefinePrompt -replace '\{FRAMEWORK_PLACEHOLDER\}', $frameworkLabel

    $messages = @(
        @{ role = 'user'; content = "Build me this app: $Prompt" }
    )

    $params = @{
        Messages     = $messages
        SystemPrompt = $systemPrompt
        MaxTokens    = 2048
        Temperature  = 0.4
    }
    if ($Provider) { $params.Provider = $Provider }
    if ($Model) { $params.Model = $Model }

    try {
        $response = Invoke-ChatCompletion @params
        $content = if ($response.Content) { $response.Content } else { "$response" }

        # Parse specification block
        if ($content -match '(?s)---BEGIN SPECIFICATION---(.+?)---END SPECIFICATION---') {
            return @{
                Success = $true
                Spec    = $Matches[1].Trim()
                Raw     = $content
            }
        }

        # Fallback: use entire response as spec
        return @{ Success = $true; Spec = $content; Raw = $content }
    }
    catch {
        return @{ Success = $false; Output = "Refinement failed: $($_.Exception.Message)" }
    }
}

# ===== Code Generation =====

function Invoke-CodeGeneration {
    <#
    .SYNOPSIS
    LLM call #2: Generate actual code files from the refined specification.
    #>
    param(
        [Parameter(Mandatory)][string]$Spec,
        [Parameter(Mandatory)][string]$Framework,
        [int]$MaxTokens,
        [string]$Provider,
        [string]$Model
    )

    $systemPrompt = switch ($Framework) {
        'powershell' { $script:BuilderPowerShellPrompt }
        'python-tk'  { $script:BuilderTkinterPrompt }
        'python-web' { $script:BuilderPyWebViewPrompt }
    }

    $messages = @(
        @{ role = 'user'; content = "Generate the application from this specification:`n`n$Spec" }
    )

    $params = @{
        Messages     = $messages
        SystemPrompt = $systemPrompt
        MaxTokens    = $MaxTokens
        Temperature  = 0.3
    }
    if ($Provider) { $params.Provider = $Provider }
    if ($Model) { $params.Model = $Model }

    try {
        Write-Host "[AppBuilder] Generating code ($Framework, max $MaxTokens tokens)..." -ForegroundColor Cyan
        $response = Invoke-ChatCompletion @params
        $content = if ($response.Content) { $response.Content } else { "$response" }

        # Always save the raw LLM response for debugging
        $logDir = Join-Path $global:AppBuilderPath '_logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $logFile = Join-Path $logDir "codegen_${timestamp}.md"
        $logContent = "# Code Generation Response`n"
        $logContent += "# Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        $logContent += "# Framework: $Framework`n"
        $logContent += "# MaxTokens: $MaxTokens`n"
        $logContent += "# StopReason: $($response.StopReason)`n"
        $logContent += "# Model: $($response.Model)`n`n"
        $logContent += $content
        Set-Content -Path $logFile -Value $logContent -Encoding UTF8
        Write-Host "[AppBuilder] Raw response saved to: $logFile" -ForegroundColor DarkGray

        # Fail early on truncated code — prevents misleading syntax errors downstream
        if ($response.StopReason -eq 'max_tokens' -or $response.StopReason -eq 'length') {
            return @{
                Success    = $false
                Output     = "Code generation was truncated (hit max_tokens). The model ran out of output budget before completing the code. Raw response saved to: $logFile. Consider using a model with a higher output limit or simplifying the prompt."
                LogPath    = $logFile
                StopReason = "max_tokens"
            }
        }

        # Parse code blocks using CodeArtifacts
        $files = @{}
        $blocks = Get-CodeBlocks -Text $content

        foreach ($block in $blocks) {
            # Try to extract filename from the code block context
            $fileName = $null

            # Check for filename in the fence line (```python app.py)
            $lines = $content -split "`n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match "^``````\w+\s+(.+\.\w+)" -and $i -lt $lines.Count - 1) {
                    $candidateName = $Matches[1].Trim()
                    # Check if the next lines match this block's code
                    $blockFirstLine = ($block.Code -split "`n")[0].Trim()
                    if ($i + 1 -lt $lines.Count -and $lines[$i + 1].Trim() -eq $blockFirstLine) {
                        $fileName = $candidateName
                        break
                    }
                }
            }

            if (-not $fileName) {
                # Infer filename from language
                $fileName = switch ($block.Language) {
                    'powershell' { 'app.ps1' }
                    'ps1'        { 'app.ps1' }
                    'python'     { if ($files.ContainsKey('app.py')) { "module_$($block.Index).py" } else { 'app.py' } }
                    'py'         { if ($files.ContainsKey('app.py')) { "module_$($block.Index).py" } else { 'app.py' } }
                    'html'       { 'web/index.html' }
                    'css'        { 'web/style.css' }
                    'javascript' { 'web/script.js' }
                    'js'         { 'web/script.js' }
                    'text'       { 'requirements.txt' }
                    default      { "file_$($block.Index).txt" }
                }
            }

            $files[$fileName] = $block.Code
        }

        if ($files.Count -eq 0) {
            return @{ Success = $false; Output = "No code blocks found in LLM response. Raw response saved for debugging." }
        }

        # Validate we got the primary file
        $primaryFile = switch ($Framework) {
            'powershell' { 'app.ps1' }
            default      { 'app.py' }
        }
        if (-not $files.ContainsKey($primaryFile)) {
            # Try to find the closest match
            $candidate = $files.Keys | Where-Object { $_ -match '\.(ps1|py)$' } | Select-Object -First 1
            if ($candidate) {
                $files[$primaryFile] = $files[$candidate]
                if ($candidate -ne $primaryFile) { $files.Remove($candidate) }
            }
            else {
                return @{ Success = $false; Output = "Generated code missing primary file ($primaryFile)." }
            }
        }

        return @{ Success = $true; Files = $files; Raw = $content }
    }
    catch {
        return @{ Success = $false; Output = "Code generation failed: $($_.Exception.Message)" }
    }
}

# ===== Code Validation =====

function Test-GeneratedCode {
    <#
    .SYNOPSIS
    Validate generated code: syntax check, security scan, import validation.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Files,
        [Parameter(Mandatory)][string]$Framework
    )

    $errors = @()

    foreach ($fileName in $Files.Keys) {
        $code = $Files[$fileName]
        $ext = [System.IO.Path]::GetExtension($fileName).ToLower()

        # Syntax check
        if ($ext -eq '.ps1') {
            $tempFile = Join-Path $env:TEMP "bildsyps_validate_$(Get-Random).ps1"
            try {
                $code | Set-Content $tempFile -Encoding UTF8
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($tempFile, [ref]$tokens, [ref]$parseErrors) | Out-Null
                if ($parseErrors.Count -gt 0) {
                    foreach ($pe in $parseErrors) {
                        $errors += "[$fileName] Syntax error line $($pe.Extent.StartLineNumber): $($pe.Message)"
                    }
                }
            }
            finally { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
        elseif ($ext -eq '.py') {
            if (Get-Command python -ErrorAction SilentlyContinue) {
                $tempFile = Join-Path $env:TEMP "bildsyps_validate_$(Get-Random).py"
                try {
                    $code | Set-Content $tempFile -Encoding UTF8
                    $result = & python -c "import ast; ast.parse(open(r'$tempFile', encoding='utf-8').read()); print('OK')" 2>&1
                    $resultStr = $result | Out-String
                    if ($resultStr -notmatch 'OK') {
                        $errors += "[$fileName] Python syntax error: $resultStr"
                    }
                }
                finally { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }

        # Security scan: dangerous patterns
        $dangerousPatterns = @(
            @{ Pattern = '\beval\s*\(';        Name = 'eval()' }
            @{ Pattern = '\bexec\s*\(';        Name = 'exec()' }
            @{ Pattern = '\b__import__\s*\(';  Name = '__import__()' }
            @{ Pattern = '\bpickle\.loads\s*\('; Name = 'pickle.loads()' }
            @{ Pattern = '\bmarshal\.loads\s*\('; Name = 'marshal.loads()' }
            @{ Pattern = '\bos\.popen\s*\(';   Name = 'os.popen()' }
            @{ Pattern = '\bos\.system\s*\(';  Name = 'os.system()' }
            @{ Pattern = '\bsubprocess\b';     Name = 'subprocess' }
            @{ Pattern = '\bInvoke-Expression\b'; Name = 'Invoke-Expression' }
            @{ Pattern = '\biex\s';            Name = 'iex (Invoke-Expression alias)' }
            @{ Pattern = 'Remove-Item\b.*-Recurse'; Name = 'Remove-Item -Recurse' }
            @{ Pattern = 'Start-Process\b.*-Verb\s+RunAs'; Name = 'Start-Process -Verb RunAs' }
        )

        foreach ($dp in $dangerousPatterns) {
            if ($code -match $dp.Pattern) {
                $errors += "[$fileName] Security: contains $($dp.Name)"
            }
        }

        # Secret scan — exclude 'Generic Secret Assign' for generated code because
        # apps with API integration naturally contain $ApiKey/$Password/$Token
        # variables with placeholder values. Specific-format patterns (Anthropic,
        # AWS, GitHub, etc.) still catch real leaked keys.
        if (Get-Command Invoke-SecretScan -ErrorAction SilentlyContinue) {
            $tempScan = Join-Path $env:TEMP "bildsyps_secretscan_$(Get-Random)$ext"
            try {
                $code | Set-Content $tempScan -Encoding UTF8
                $findings = Invoke-SecretScan -Paths @($tempScan) -ExcludePatterns @('Generic Secret Assign')
                foreach ($f in $findings) {
                    $errors += "[$fileName] Secret detected (line $($f.Line)): $($f.Pattern) -- $($f.Masked)"
                }
            }
            finally { Remove-Item $tempScan -Force -ErrorAction SilentlyContinue }
        }
    }

    if ($errors.Count -gt 0) {
        return @{ Success = $false; Errors = $errors }
    }
    return @{ Success = $true; Errors = @() }
}

# ===== Branding Injection =====

function Invoke-BildsyPSBranding {
    <#
    .SYNOPSIS
    Verify branding is present in generated code. Patch it in if LLM omitted it.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Files,
        [Parameter(Mandatory)][string]$Framework,
        [switch]$NoBranding
    )

    $brandingText = 'Built with BildsyPS'

    # Strip branding from all files when -NoBranding (LLM prompts include branding instructions)
    if ($NoBranding) {
        foreach ($key in @($Files.Keys)) {
            $Files[$key] = $Files[$key] -replace [regex]::Escape($brandingText) + '[^\r\n]*', ''
        }
        return $Files
    }

    switch ($Framework) {
        'powershell' {
            $key = 'app.ps1'
            if ($Files.ContainsKey($key) -and $Files[$key] -notmatch [regex]::Escape($brandingText)) {
                # Inject About dialog before the last closing brace or at the end
                $aboutSnippet = @'

# --- BildsyPS Branding ---
$aboutItem = New-Object System.Windows.Forms.ToolStripMenuItem("About")
$aboutItem.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "Built with BildsyPS — AI-powered shell orchestrator`nhttps://github.com/gsultani/bildsyps",
        "About", [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
})
if ($form.MainMenuStrip) {
    $helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Help")
    $helpMenu.DropDownItems.Add($aboutItem)
    $form.MainMenuStrip.Items.Add($helpMenu)
}
'@
                # Insert before [Application]::Run or at the end
                if ($Files[$key] -match '(\[System\.Windows\.Forms\.Application\]::Run)') {
                    $Files[$key] = $Files[$key] -replace '(\[System\.Windows\.Forms\.Application\]::Run)', "$aboutSnippet`n`$1"
                }
                else {
                    $Files[$key] += "`n$aboutSnippet"
                }
            }
        }
        'python-tk' {
            $key = 'app.py'
            if ($Files.ContainsKey($key) -and $Files[$key] -notmatch [regex]::Escape($brandingText)) {
                # Add About menu import and function before mainloop
                $aboutSnippet = @'

# --- BildsyPS Branding ---
def _bildsyps_about():
    from tkinter import messagebox
    messagebox.showinfo("About", "Built with BildsyPS\nhttps://github.com/gsultani/bildsyps")
'@
                if ($Files[$key] -match '\.mainloop\(\)') {
                    $Files[$key] = $Files[$key] -replace '(\.mainloop\(\))', "$aboutSnippet`n`$1"
                }
                else {
                    $Files[$key] += "`n$aboutSnippet"
                }
            }
        }
        'python-web' {
            $key = 'web/index.html'
            if ($Files.ContainsKey($key) -and $Files[$key] -notmatch [regex]::Escape($brandingText)) {
                # Add branded footer before </body>
                $footer = '<footer style="text-align:center;padding:8px;color:#666;font-size:11px">Built with BildsyPS</footer>'
                if ($Files[$key] -match '</body>') {
                    $Files[$key] = $Files[$key] -replace '</body>', "$footer`n</body>"
                }
                else {
                    $Files[$key] += "`n$footer"
                }
            }
        }
    }

    return $Files
}

# ===== Name Sanitization =====

function Get-SafeBuildName {
    <#
    .SYNOPSIS
    Sanitize a build name for safe filesystem use.
    Strips invalid characters, trims whitespace, lowercases, and caps length at 40.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Name
    )
    if (-not $Name -or $Name.Trim() -eq '') { return '' }
    $safe = $Name.Trim()
    $safe = $safe -replace '[<>:"/\\|?*]', ''
    $safe = ($safe -replace '[^\w\-]', '-').Trim('-').ToLower()
    if ($safe.Length -gt 40) { $safe = $safe.Substring(0, 40).TrimEnd('-') }
    return $safe
}

# ===== Build Functions =====

function Build-PowerShellExecutable {
    <#
    .SYNOPSIS
    Compile a .ps1 file to .exe using ps2exe. Auto-installs ps2exe if needed.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$AppName,
        [string]$OutputDir,
        [string]$IconPath
    )

    if (-not $OutputDir) { $OutputDir = Join-Path $global:AppBuilderPath $AppName }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    # Ensure ps2exe is available
    if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
        if (-not (Get-Module -ListAvailable -Name ps2exe)) {
            Write-Host "[AppBuilder] Installing ps2exe from PSGallery..." -ForegroundColor Cyan
            Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
        }
        Import-Module ps2exe -ErrorAction Stop
    }

    $inputFile = Join-Path $SourceDir 'app.ps1'
    $outputFile = Join-Path $OutputDir "$AppName.exe"

    if (-not (Test-Path $inputFile)) {
        return @{ Success = $false; Output = "Source file not found: $inputFile" }
    }

    $ps2exeParams = @{
        inputFile  = $inputFile
        outputFile = $outputFile
        noConsole  = $true
        title      = $AppName
    }
    if ($IconPath -and (Test-Path $IconPath)) {
        $ps2exeParams.iconFile = $IconPath
    }

    try {
        Write-Host "[AppBuilder] Compiling $AppName.exe via ps2exe..." -ForegroundColor Cyan
        $startTime = Get-Date
        Invoke-ps2exe @ps2exeParams 2>&1 | Out-Null
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

        if (Test-Path $outputFile) {
            $size = (Get-Item $outputFile).Length
            $sizeStr = if ($size -lt 1MB) { "$([math]::Round($size/1KB))KB" } else { "$([math]::Round($size/1MB, 1))MB" }
            return @{
                Success   = $true
                ExePath   = $outputFile
                Size      = $sizeStr
                BuildTime = $elapsed
                Output    = "Built $AppName.exe ($sizeStr) in ${elapsed}s"
            }
        }
        return @{ Success = $false; Output = "ps2exe completed but .exe not found at $outputFile" }
    }
    catch {
        return @{ Success = $false; Output = "ps2exe failed: $($_.Exception.Message)" }
    }
}

function Build-PythonExecutable {
    <#
    .SYNOPSIS
    Build a Python app to .exe via venv + PyInstaller.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string]$Framework,
        [string]$OutputDir,
        [string]$IconPath
    )

    if (-not $OutputDir) { $OutputDir = Join-Path $global:AppBuilderPath $AppName }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    # Check Python
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        return @{ Success = $false; Output = "Python not found on PATH. Install Python 3.8+ for Python build lanes." }
    }

    $startTime = Get-Date

    try {
        # Create venv
        Write-Host "[AppBuilder] Creating Python virtual environment..." -ForegroundColor Cyan
        $venvPath = Join-Path $SourceDir 'venv'
        & python -m venv $venvPath 2>&1 | Out-Null
        $venvPip = Join-Path $venvPath 'Scripts\pip.exe'
        # venv python at: Join-Path $venvPath 'Scripts\python.exe'

        if (-not (Test-Path $venvPip)) {
            return @{ Success = $false; Output = "Failed to create Python venv" }
        }

        # Install dependencies
        $reqFile = Join-Path $SourceDir 'requirements.txt'
        if (Test-Path $reqFile) {
            $reqContent = Get-Content $reqFile -Raw
            if ($reqContent -match '\S' -and $reqContent -notmatch '^\s*#') {
                Write-Host "[AppBuilder] Installing dependencies..." -ForegroundColor Cyan
                & $venvPip install -r $reqFile --quiet 2>&1 | Out-Null
            }
        }

        # Install PyInstaller
        Write-Host "[AppBuilder] Installing PyInstaller..." -ForegroundColor Cyan
        & $venvPip install pyinstaller --quiet 2>&1 | Out-Null

        $venvPyInstaller = Join-Path $venvPath 'Scripts\pyinstaller.exe'
        if (-not (Test-Path $venvPyInstaller)) {
            return @{ Success = $false; Output = "PyInstaller installation failed" }
        }

        # Build command
        $buildArgs = @('--onefile', '--windowed', '--name', $AppName, '--clean', '--noconfirm')
        if ($IconPath -and (Test-Path $IconPath)) {
            $buildArgs += @('--icon', $IconPath)
        }

        # Framework-specific args
        if ($Framework -eq 'python-web') {
            $webDir = Join-Path $SourceDir 'web'
            if (Test-Path $webDir) {
                $buildArgs += @('--add-data', "$webDir;web")
            }
            $buildArgs += @(
                '--hidden-import', 'webview',
                '--hidden-import', 'webview.platforms.winforms',
                '--hidden-import', 'clr',
                '--hidden-import', 'pythonnet'
            )
        }

        $buildArgs += (Join-Path $SourceDir 'app.py')

        Write-Host "[AppBuilder] Running PyInstaller ($Framework)..." -ForegroundColor Cyan
        Start-Process $venvPyInstaller -ArgumentList $buildArgs -WorkingDirectory $SourceDir `
            -Wait -NoNewWindow -RedirectStandardError (Join-Path $SourceDir 'build_errors.log')

        # Timeout handled by -Wait (Start-Process doesn't have a native timeout, but builds rarely exceed limits)
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

        $distExe = Join-Path $SourceDir "dist\$AppName.exe"
        if (Test-Path $distExe) {
            $finalExe = Join-Path $OutputDir "$AppName.exe"
            Copy-Item $distExe $finalExe -Force
            $size = (Get-Item $finalExe).Length
            $sizeStr = if ($size -lt 1MB) { "$([math]::Round($size/1KB))KB" } else { "$([math]::Round($size/1MB, 1))MB" }
            return @{
                Success   = $true
                ExePath   = $finalExe
                Size      = $sizeStr
                BuildTime = $elapsed
                Output    = "Built $AppName.exe ($sizeStr) in ${elapsed}s"
            }
        }

        $errLog = Join-Path $SourceDir 'build_errors.log'
        $errContent = if (Test-Path $errLog) { Get-Content $errLog -Raw -ErrorAction SilentlyContinue } else { 'Unknown error' }
        return @{ Success = $false; Output = "PyInstaller failed (${elapsed}s): $errContent" }
    }
    catch {
        return @{ Success = $false; Output = "Build error: $($_.Exception.Message)" }
    }
}

# ===== SQLite Build Tracking =====

function Initialize-BuildsTable {
    if (-not $global:ChatDbReady) { return $false }
    if (-not (Get-Command Get-ChatDbConnection -ErrorAction SilentlyContinue)) { return $false }

    try {
        $conn = Get-ChatDbConnection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS builds (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL,
    framework    TEXT NOT NULL,
    prompt       TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'queued',
    exe_path     TEXT,
    source_dir   TEXT,
    provider     TEXT,
    model        TEXT,
    branded      INTEGER DEFAULT 1,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT,
    error        TEXT,
    build_time_s REAL
)
"@
        $cmd.ExecuteNonQuery() | Out-Null
        $cmd.Dispose()
        $conn.Close()
        $conn.Dispose()
        return $true
    }
    catch { return $false }
}

function Save-BuildRecord {
    param(
        [string]$Name, [string]$Framework, [string]$Prompt,
        [string]$Status, [string]$ExePath, [string]$SourceDir,
        [string]$Provider, [string]$Model, [bool]$Branded = $true,
        [string]$ErrorMsg, [double]$BuildTime
    )

    if (-not (Initialize-BuildsTable)) { return }

    try {
        $conn = Get-ChatDbConnection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO builds (name, framework, prompt, status, exe_path, source_dir, provider, model, branded, completed_at, error, build_time_s) VALUES (@n, @fw, @p, @s, @ep, @sd, @prov, @mod, @br, datetime('now'), @err, @bt)"
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@n", $Name)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@fw", $Framework)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@p", $Prompt)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@s", $Status)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@ep", $(if ($ExePath) { $ExePath } else { [DBNull]::Value }))) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@sd", $(if ($SourceDir) { $SourceDir } else { [DBNull]::Value }))) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@prov", $(if ($Provider) { $Provider } else { [DBNull]::Value }))) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@mod", $(if ($Model) { $Model } else { [DBNull]::Value }))) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@br", [int]$Branded)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@err", $(if ($ErrorMsg) { $ErrorMsg } else { [DBNull]::Value }))) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@bt", $BuildTime)) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null
        $cmd.Dispose()
        $conn.Close()
        $conn.Dispose()
    }
    catch {
        Write-Verbose "AppBuilder: Failed to save build record: $($_.Exception.Message)"
    }
}

function Get-AppBuilds {
    <#
    .SYNOPSIS
    List all builds, most recent first.
    #>

    # Try SQLite first
    if (Initialize-BuildsTable) {
        try {
            $conn = Get-ChatDbConnection
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT id, name, framework, status, exe_path, branded, created_at, build_time_s, error FROM builds ORDER BY created_at DESC LIMIT 20"
            $reader = $cmd.ExecuteReader()
            $builds = @()
            while ($reader.Read()) {
                $builds += [PSCustomObject]@{
                    Id        = $reader['id']
                    Name      = $reader['name']
                    Framework = $reader['framework']
                    Status    = $reader['status']
                    ExePath   = $reader['exe_path']
                    Branded   = [bool][int]$reader['branded']
                    CreatedAt = $reader['created_at']
                    BuildTime = $reader['build_time_s']
                    Error     = $reader['error']
                }
            }
            $reader.Close()
            $cmd.Dispose()
            $conn.Close()
            $conn.Dispose()

            if ($builds.Count -eq 0) {
                Write-Host "No builds yet. Use: build `"description of your app`"" -ForegroundColor DarkGray
                return @()
            }

            Write-Host "`n===== App Builds =====" -ForegroundColor Cyan
            foreach ($b in $builds) {
                $statusColor = switch ($b.Status) { 'completed' { 'Green' }; 'failed' { 'Red' }; default { 'Yellow' } }
                $brandTag = if ($b.Branded) { '' } else { ' [unbranded]' }
                $timeTag = if ($b.BuildTime) { " ($($b.BuildTime)s)" } else { '' }
                Write-Host "  $($b.Name) " -ForegroundColor Yellow -NoNewline
                Write-Host "[$($b.Framework)] " -ForegroundColor DarkGray -NoNewline
                Write-Host "$($b.Status)$brandTag$timeTag" -ForegroundColor $statusColor
                if ($b.ExePath -and (Test-Path $b.ExePath)) {
                    Write-Host "    $($b.ExePath)" -ForegroundColor DarkGray
                }
                if ($b.Error) {
                    $preview = if ($b.Error.Length -gt 80) { $b.Error.Substring(0, 80) + '...' } else { $b.Error }
                    Write-Host "    Error: $preview" -ForegroundColor Red
                }
            }
            Write-Host ""
            return $builds
        }
        catch { }
    }

    # Filesystem fallback
    if (-not (Test-Path $global:AppBuilderPath)) {
        Write-Host "No builds yet. Use: build `"description of your app`"" -ForegroundColor DarkGray
        return
    }

    $dirs = Get-ChildItem $global:AppBuilderPath -Directory -ErrorAction SilentlyContinue
    if ($dirs.Count -eq 0) {
        Write-Host "No builds yet." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n===== App Builds =====" -ForegroundColor Cyan
    foreach ($d in $dirs | Sort-Object LastWriteTime -Descending) {
        $exe = Get-ChildItem $d.FullName -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        $exeInfo = if ($exe) { "$($exe.Name) ($([math]::Round($exe.Length/1KB))KB)" } else { '(no .exe)' }
        Write-Host "  $($d.Name) " -ForegroundColor Yellow -NoNewline
        Write-Host "-- $exeInfo" -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Remove-AppBuild {
    <#
    .SYNOPSIS
    Delete a build by name.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $buildDir = Join-Path $global:AppBuilderPath $Name
    if (Test-Path $buildDir) {
        Remove-Item $buildDir -Recurse -Force
        Write-Host "Removed build: $Name" -ForegroundColor Green
    }

    # Remove from SQLite
    if (Initialize-BuildsTable) {
        try {
            $conn = Get-ChatDbConnection
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "DELETE FROM builds WHERE name = @n"
            $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@n", $Name)) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
            $cmd.Dispose()
            $conn.Close()
            $conn.Dispose()
        }
        catch { }
    }
}

# ===== Main Entry Point =====

function New-AppBuild {
    <#
    .SYNOPSIS
    Build a standalone .exe from a natural language prompt.

    .PARAMETER Prompt
    Natural language description of the app to build.

    .PARAMETER Framework
    Force a specific framework: powershell (default), python-tk, python-web.

    .PARAMETER Name
    App name for the executable. Auto-generated from spec if omitted.

    .PARAMETER MaxTokens
    Override auto-detected max tokens for code generation.

    .PARAMETER Provider
    LLM provider override.

    .PARAMETER Model
    LLM model override.

    .PARAMETER NoBranding
    Skip BildsyPS branding injection.

    .PARAMETER IconPath
    Path to .ico file for the executable.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [string]$Framework,
        [string]$Name,
        [int]$MaxTokens = 0,
        [string]$Provider,
        [string]$Model,
        [switch]$NoBranding,
        [string]$IconPath
    )

    $totalStart = Get-Date

    # Validate prompt early — don't waste an LLM call on empty input
    if (-not $Prompt -or $Prompt.Trim() -eq '') {
        return @{ Success = $false; Output = "Prompt cannot be empty" }
    }

    # Ensure builds directory exists
    if (-not (Test-Path $global:AppBuilderPath)) {
        New-Item -ItemType Directory -Path $global:AppBuilderPath -Force | Out-Null
    }

    # Step 1: Framework routing
    $framework = Get-BuildFramework -Prompt $Prompt -Framework $Framework
    Write-Host "`n[AppBuilder] Framework: $framework" -ForegroundColor Cyan

    # Resolve model for token budget
    $resolvedModel = $Model
    if (-not $resolvedModel) {
        $prov = if ($Provider) { $Provider } else { $global:DefaultChatProvider }
        $provConfig = $global:ChatProviders[$prov]
        if ($provConfig) { $resolvedModel = $provConfig.DefaultModel }
    }

    # Step 2: Prompt refinement
    Write-Host "[AppBuilder] Refining prompt..." -ForegroundColor Cyan
    $refineResult = Invoke-PromptRefinement -Prompt $Prompt -Framework $framework -Provider $Provider -Model $Model
    if (-not $refineResult.Success) {
        Write-Host "[AppBuilder] FAILED: $($refineResult.Output)" -ForegroundColor Red
        return $refineResult
    }

    # Extract app name from spec if not provided
    if (-not $Name) {
        if ($refineResult.Spec -match 'APP_NAME:\s*(.+)') {
            $Name = ($Matches[1].Trim() -replace '[^\w\-]', '-').Trim('-')
            if ($Name.Length -gt 40) { $Name = $Name.Substring(0, 40) }
        }
        if (-not $Name) { $Name = "bildsyps-app-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
    }
    $Name = Get-SafeBuildName -Name $Name

    Write-Host "[AppBuilder] App name: $Name" -ForegroundColor Cyan

    # Step 3: Code generation
    $codeMaxTokens = Get-BuildMaxTokens -Framework $framework -Model $resolvedModel -Override $MaxTokens
    $codeResult = Invoke-CodeGeneration -Spec $refineResult.Spec -Framework $framework `
        -MaxTokens $codeMaxTokens -Provider $Provider -Model $Model
    if (-not $codeResult.Success) {
        Write-Host "[AppBuilder] FAILED: $($codeResult.Output)" -ForegroundColor Red
        Save-BuildRecord -Name $Name -Framework $framework -Prompt $Prompt -Status 'failed' `
            -Provider $Provider -Model $Model -ErrorMsg $codeResult.Output -BuildTime 0
        return $codeResult
    }

    Write-Host "[AppBuilder] Generated $($codeResult.Files.Count) file(s)" -ForegroundColor Cyan

    # Step 4: Validate
    Write-Host "[AppBuilder] Validating code..." -ForegroundColor Cyan
    $validation = Test-GeneratedCode -Files $codeResult.Files -Framework $framework
    if (-not $validation.Success) {
        Write-Host "[AppBuilder] Validation FAILED:" -ForegroundColor Red
        foreach ($err in $validation.Errors) { Write-Host "  $err" -ForegroundColor Yellow }
        Save-BuildRecord -Name $Name -Framework $framework -Prompt $Prompt -Status 'failed' `
            -Provider $Provider -Model $Model -ErrorMsg ($validation.Errors -join '; ') -BuildTime 0
        return @{ Success = $false; Output = "Validation failed"; Errors = $validation.Errors }
    }

    # Step 4b: Branding injection
    $codeResult.Files = Invoke-BildsyPSBranding -Files $codeResult.Files -Framework $framework -NoBranding:$NoBranding

    # Step 5: Write source files
    $sourceDir = Join-Path $global:AppBuilderPath "$Name\source"
    if (-not (Test-Path $sourceDir)) { New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null }

    foreach ($fileName in $codeResult.Files.Keys) {
        $filePath = Join-Path $sourceDir $fileName
        $fileDir = Split-Path $filePath -Parent
        if (-not (Test-Path $fileDir)) { New-Item -ItemType Directory -Path $fileDir -Force | Out-Null }
        $codeResult.Files[$fileName] | Set-Content $filePath -Encoding UTF8
    }
    Write-Host "[AppBuilder] Source written to $sourceDir" -ForegroundColor DarkGray

    # Step 6: Build
    $outputDir = Join-Path $global:AppBuilderPath $Name
    $buildResult = if ($framework -eq 'powershell') {
        Build-PowerShellExecutable -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir -IconPath $IconPath
    }
    else {
        Build-PythonExecutable -SourceDir $sourceDir -AppName $Name -Framework $framework -OutputDir $outputDir -IconPath $IconPath
    }

    $totalElapsed = [math]::Round(((Get-Date) - $totalStart).TotalSeconds, 1)

    if ($buildResult.Success) {
        Write-Host "`n[AppBuilder] SUCCESS: $($buildResult.Output)" -ForegroundColor Green
        Write-Host "  Executable: $($buildResult.ExePath)" -ForegroundColor White
        Write-Host "  Source:     $sourceDir" -ForegroundColor DarkGray
        Write-Host "  Total time: ${totalElapsed}s" -ForegroundColor DarkGray

        Save-BuildRecord -Name $Name -Framework $framework -Prompt $Prompt -Status 'completed' `
            -ExePath $buildResult.ExePath -SourceDir $sourceDir -Provider $Provider -Model $Model `
            -Branded:(-not $NoBranding) -BuildTime $totalElapsed

        return @{
            Success   = $true
            ExePath   = $buildResult.ExePath
            SourceDir = $sourceDir
            Framework = $framework
            AppName   = $Name
            BuildTime = $totalElapsed
            Output    = $buildResult.Output
        }
    }
    else {
        Write-Host "`n[AppBuilder] BUILD FAILED: $($buildResult.Output)" -ForegroundColor Red
        Save-BuildRecord -Name $Name -Framework $framework -Prompt $Prompt -Status 'failed' `
            -SourceDir $sourceDir -Provider $Provider -Model $Model `
            -ErrorMsg $buildResult.Output -BuildTime $totalElapsed

        return @{ Success = $false; Output = $buildResult.Output; SourceDir = $sourceDir }
    }
}

# ===== Rebuild (Diff-Based Modification) =====

function Update-AppBuild {
    <#
    .SYNOPSIS
    Modify an existing build using FIND/REPLACE diff-based edits, then rebuild.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Changes,
        [string]$Provider,
        [string]$Model
    )

    $sourceDir = Join-Path $global:AppBuilderPath "$Name\source"
    if (-not (Test-Path $sourceDir)) {
        Write-Host "[AppBuilder] Build '$Name' not found." -ForegroundColor Red
        return @{ Success = $false; Output = "Build not found: $Name" }
    }

    # Load existing source
    $files = @{}
    Get-ChildItem $sourceDir -File -Recurse | ForEach-Object {
        $relPath = $_.FullName.Substring($sourceDir.Length + 1).Replace('\', '/')
        $files[$relPath] = Get-Content $_.FullName -Raw -Encoding UTF8
    }

    # Detect framework from files
    $framework = if ($files.ContainsKey('app.ps1')) { 'powershell' }
                 elseif ($files.ContainsKey('web/index.html')) { 'python-web' }
                 else { 'python-tk' }

    # Check if user wants full regeneration
    $fullRegenTriggers = @('rewrite', 'redesign', 'from scratch', 'start over', 'completely new')
    $needsFullRegen = $fullRegenTriggers | Where-Object { $Changes -match $_ }

    if ($needsFullRegen) {
        Write-Host "[AppBuilder] Full regeneration requested..." -ForegroundColor Cyan
        # Extract original prompt from SQLite if available
        $originalPrompt = $Changes
        if (Initialize-BuildsTable) {
            try {
                $conn = Get-ChatDbConnection
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "SELECT prompt FROM builds WHERE name = @n ORDER BY created_at DESC LIMIT 1"
                $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@n", $Name)) | Out-Null
                $result = $cmd.ExecuteScalar()
                if ($result) { $originalPrompt = "$result. Additional requirements: $Changes" }
                $cmd.Dispose()
                $conn.Close()
                $conn.Dispose()
            }
            catch { }
        }
        return New-AppBuild -Prompt $originalPrompt -Framework $framework -Name $Name -Provider $Provider -Model $Model
    }

    # Diff-based modification
    Write-Host "[AppBuilder] Applying modifications to '$Name'..." -ForegroundColor Cyan

    $sourceContext = ($files.Keys | ForEach-Object {
        "--- $_ ---`n$($files[$_])`n"
    }) -join "`n"

    $messages = @(
        @{ role = 'user'; content = "Here is the current source code:`n`n$sourceContext`n`nUser's change request: $Changes" }
    )

    $params = @{
        Messages     = $messages
        SystemPrompt = $script:BuilderModifyPrompt
        MaxTokens    = 8192
        Temperature  = 0.3
    }
    if ($Provider) { $params.Provider = $Provider }
    if ($Model) { $params.Model = $Model }

    try {
        $response = Invoke-ChatCompletion @params
        $content = if ($response.Content) { $response.Content } else { "$response" }

        if ($content -match 'FULL_REGENERATION_NEEDED') {
            Write-Host "[AppBuilder] LLM recommends full regeneration. Switching..." -ForegroundColor Yellow
            return Update-AppBuild -Name $Name -Changes "rewrite: $Changes" -Provider $Provider -Model $Model
        }

        # Apply FIND/REPLACE edits
        $editCount = 0

        # Process FIND/REPLACE blocks
        $findReplacePattern = '(?s)<<<FIND\r?\n(.+?)>>>REPLACE\r?\n(.*?)<<<END'
        $frMatches = [regex]::Matches($content, $findReplacePattern)
        foreach ($m in $frMatches) {
            $findText = $m.Groups[1].Value.TrimEnd()
            $replaceText = $m.Groups[2].Value.TrimEnd()
            foreach ($fn in @($files.Keys)) {
                if ($files[$fn].Contains($findText)) {
                    $files[$fn] = $files[$fn].Replace($findText, $replaceText)
                    $editCount++
                    break
                }
            }
        }

        # Process ADD_AFTER blocks
        $addAfterPattern = '(?s)<<<ADD_AFTER\r?\n(.+?)>>>INSERT\r?\n(.+?)<<<END'
        $aaMatches = [regex]::Matches($content, $addAfterPattern)
        foreach ($m in $aaMatches) {
            $afterLine = $m.Groups[1].Value.TrimEnd()
            $insertText = $m.Groups[2].Value.TrimEnd()
            foreach ($fn in @($files.Keys)) {
                if ($files[$fn].Contains($afterLine)) {
                    $files[$fn] = $files[$fn].Replace($afterLine, "$afterLine`n$insertText")
                    $editCount++
                    break
                }
            }
        }

        # Process NEW_FILE blocks
        $newFilePattern = '(?s)<<<NEW_FILE\s+(\S+)\r?\n(.+?)<<<END'
        $nfMatches = [regex]::Matches($content, $newFilePattern)
        foreach ($m in $nfMatches) {
            $newFileName = $m.Groups[1].Value.Trim()
            $newFileContent = $m.Groups[2].Value.TrimEnd()
            $files[$newFileName] = $newFileContent
            $editCount++
        }

        if ($editCount -eq 0) {
            Write-Host "[AppBuilder] No edits could be applied. LLM response may not have followed the edit format." -ForegroundColor Yellow
            return @{ Success = $false; Output = "No edits applied" }
        }

        Write-Host "[AppBuilder] Applied $editCount edit(s). Rebuilding..." -ForegroundColor Cyan

        # Write modified files
        foreach ($fn in $files.Keys) {
            $filePath = Join-Path $sourceDir $fn
            $fileDir = Split-Path $filePath -Parent
            if (-not (Test-Path $fileDir)) { New-Item -ItemType Directory -Path $fileDir -Force | Out-Null }
            $files[$fn] | Set-Content $filePath -Encoding UTF8
        }

        # Validate
        $validation = Test-GeneratedCode -Files $files -Framework $framework
        if (-not $validation.Success) {
            Write-Host "[AppBuilder] Modified code has errors:" -ForegroundColor Red
            foreach ($err in $validation.Errors) { Write-Host "  $err" -ForegroundColor Yellow }
            return @{ Success = $false; Output = "Validation failed after modification"; Errors = $validation.Errors }
        }

        # Rebuild
        $outputDir = Join-Path $global:AppBuilderPath $Name
        $buildResult = if ($framework -eq 'powershell') {
            Build-PowerShellExecutable -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir
        }
        else {
            Build-PythonExecutable -SourceDir $sourceDir -AppName $Name -Framework $framework -OutputDir $outputDir
        }

        if ($buildResult.Success) {
            Write-Host "[AppBuilder] Rebuild SUCCESS: $($buildResult.Output)" -ForegroundColor Green
            Save-BuildRecord -Name $Name -Framework $framework -Prompt "rebuild: $Changes" -Status 'completed' `
                -ExePath $buildResult.ExePath -SourceDir $sourceDir -Provider $Provider -Model $Model `
                -BuildTime $buildResult.BuildTime
        }
        else {
            Write-Host "[AppBuilder] Rebuild FAILED: $($buildResult.Output)" -ForegroundColor Red
        }

        return $buildResult
    }
    catch {
        return @{ Success = $false; Output = "Modification failed: $($_.Exception.Message)" }
    }
}

# ===== Tab Completion =====
$_appBuildNameCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    if (Test-Path $global:AppBuilderPath) {
        Get-ChildItem $global:AppBuilderPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$wordToComplete*" } | Sort-Object Name | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', "Build: $($_.Name)")
        }
    }
}

Register-ArgumentCompleter -CommandName Remove-AppBuild -ParameterName Name -ScriptBlock $_appBuildNameCompleter
Register-ArgumentCompleter -CommandName Update-AppBuild -ParameterName Name -ScriptBlock $_appBuildNameCompleter

Register-ArgumentCompleter -CommandName New-AppBuild -ParameterName Framework -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    @('powershell', 'python-tk', 'python-web') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Framework: $_")
    }
}

# ===== Aliases =====
Set-Alias builds Get-AppBuilds -Force
Set-Alias rebuild Update-AppBuild -Force

Write-Verbose "AppBuilder loaded: New-AppBuild, Update-AppBuild, Get-AppBuilds, Remove-AppBuild"
