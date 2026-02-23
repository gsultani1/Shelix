# ===== AppBuilder.ps1 =====
# Prompt-to-executable pipeline. Generates code via LLM, validates, compiles to .exe.
# Three lanes: powershell (default, ps2exe), python-tk (PyInstaller), python-web (PyInstaller).
# Depends on: ChatProviders.ps1, CodeArtifacts.ps1, SecretScanner.ps1, ChatStorage.ps1

$global:AppBuilderPath = "$global:BildsyPSHome\builds"
$global:AppBuilderBranding = $true  # inject "Built with BildsyPS" branding

# ═══════════════════════════════════════════════════════════════════════════════
# Extracted Data Tables (script-scope)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Dangerous pattern definitions (split by language) ──
$script:DangerousPythonPatterns = @(
    @{ Pattern = '\beval\s*\(';          Name = 'eval()' }
    @{ Pattern = '\bexec\s*\(';          Name = 'exec()' }
    @{ Pattern = '\b__import__\s*\(';    Name = '__import__()' }
    @{ Pattern = '\bpickle\.loads\s*\('; Name = 'pickle.loads()' }
    @{ Pattern = '\bmarshal\.loads\s*\('; Name = 'marshal.loads()' }
    @{ Pattern = '\bos\.popen\s*\(';     Name = 'os.popen()' }
    @{ Pattern = '\bos\.system\s*\(';    Name = 'os.system()' }
    @{ Pattern = '\bsubprocess\b';       Name = 'subprocess' }
)

$script:DangerousPowerShellPatterns = @(
    @{ Pattern = '\bInvoke-Expression\b'; Name = 'Invoke-Expression' }
    @{ Pattern = '\biex\s';              Name = 'iex (Invoke-Expression alias)' }
    @{ Pattern = 'Remove-Item\b.*-Recurse'; Name = 'Remove-Item -Recurse' }
    @{ Pattern = 'Start-Process\b.*-Verb\s+RunAs'; Name = 'Start-Process -Verb RunAs' }
)

$script:DangerousJavaScriptPatterns = @(
    @{ Pattern = '\beval\s*\(';           Name = 'eval()' }
    @{ Pattern = 'new\s+Function\s*\(';   Name = 'new Function()' }
    @{ Pattern = '\bdocument\.write\s*\('; Name = 'document.write()' }
    @{ Pattern = '\.innerHTML\s*=';        Name = 'innerHTML assignment' }
    @{ Pattern = '\bsetTimeout\s*\(\s*["'']'; Name = 'setTimeout with string argument' }
    @{ Pattern = '\bsetInterval\s*\(\s*["'']'; Name = 'setInterval with string argument' }
)

# ── PS7+ compatibility patterns (applied to .ps1 files only) ──
$script:PS7CompatPatterns = @(
    @{ Pattern = '\?\?';  Name = 'null-coalescing operator ?? (PS7+ only, breaks ps2exe)' }
    @{ Pattern = '\?\.';  Name = 'null-conditional operator ?. (PS7+ only, breaks ps2exe)' }
    @{ Pattern = '\?\[';  Name = 'null-conditional index ?[] (PS7+ only, breaks ps2exe)' }
)

# ── Theme presets (per-framework rule text, keyed by theme name) ──
$script:ThemePresets = @{
    dark = @{
        powershell   = '6. Dark theme: Background=#1e1e1e, Foreground=#e0e0e0, Accent=#4A90E2, Font=Segoe UI'
        'python-tk'  = '5. Dark theme: bg=#1e1e1e, fg=#e0e0e0, accent=#4A90E2, font=("Segoe UI", 10)'
        'python-web' = '4. Dark theme in CSS: background=#1e1e1e, color=#e0e0e0, accent=#4A90E2, font-family="Segoe UI"'
        tauri        = '7. Dark theme in CSS: background=#1e1e1e, color=#e0e0e0, accent=#4A90E2, font-family="Segoe UI".'
        refine       = '- dark theme (#1e1e1e background, #4A90E2 accent, Segoe UI font)'
    }
    light = @{
        powershell   = '6. Light theme: Background=#f5f5f5, Foreground=#1e1e1e, Accent=#0078d4, Font=Segoe UI'
        'python-tk'  = '5. Light theme: bg=#f5f5f5, fg=#1e1e1e, accent=#0078d4, font=("Segoe UI", 10)'
        'python-web' = '4. Light theme in CSS: background=#f5f5f5, color=#1e1e1e, accent=#0078d4, font-family="Segoe UI"'
        tauri        = '7. Light theme in CSS: background=#f5f5f5, color=#1e1e1e, accent=#0078d4, font-family="Segoe UI".'
        refine       = '- light theme (#f5f5f5 background, #0078d4 blue accent, Segoe UI font)'
    }
    system = @{
        powershell   = '6. Use Windows native system colors. Do NOT hardcode Background, Foreground, or Accent hex values. Let WinForms inherit SystemColors defaults. Font=Segoe UI'
        'python-tk'  = '5. Use the OS native theme. Do NOT override bg/fg colors. Let ttk themed widgets use default system appearance. font=("Segoe UI", 10)'
        'python-web' = '4. System-adaptive CSS: use @media (prefers-color-scheme) for dark/light mode. Default to light with CSS system colors (Canvas, CanvasText, Highlight). font-family="Segoe UI"'
        tauri        = '7. System-adaptive CSS: use @media (prefers-color-scheme) for dark/light mode. Default to light with CSS system colors (Canvas, CanvasText, Highlight). font-family="Segoe UI".'
        refine       = '- native OS theme (respect system light/dark preference, no hardcoded colors, Segoe UI font)'
    }
}

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
{THEME_STYLE}
EDGE_CASES:
- input validation, error states, empty states
---END SPECIFICATION---

Be specific and detailed. The specification will be handed to a code generator.
'@

$script:BuilderPowerShellPrompt = @'
You are a PowerShell application code generator. Given a specification, produce a complete, runnable PowerShell application using Windows Forms (System.Windows.Forms).

RULES:
1. Output MULTIPLE .ps1 files, each in its own fenced code block with the filepath after the
   language tag. Structure the app into logical files:
   ```powershell source/data.ps1      — data models, load/save functions, business logic
   ```powershell source/ui.ps1        — form creation, controls, layout, theming
   ```powershell source/events.ps1    — event handlers, user interaction logic
   ```powershell app.ps1              — entry point: dot-sources the above, initializes, runs the form
   For simple apps (fewer than 5 features), a single app.ps1 is acceptable.
2. Use only assemblies available in PowerShell 7+: System.Windows.Forms, System.Drawing, PresentationFramework (WPF)
3. Do NOT use any external modules. No Install-Module calls. No NuGet packages.
4. The entry point (app.ps1) dot-sources the other files using: . "$PSScriptRoot\source\data.ps1"
   At build time, all files are merged into one for compilation. Keep each file self-contained
   with no circular dependencies. Order: data.ps1 first, then ui.ps1, then events.ps1, then app.ps1.
5. Use proper error handling with try/catch blocks.
{THEME_RULE}
6b. Use structured layout controls: TableLayoutPanel for grid alignment, SplitContainer for
    resizable panes, MenuStrip for menus (not manual button bars). Dock and Anchor controls
    so the UI scales correctly when resized.
7. Add a Help menu with an "About" item that shows a MessageBox:
   "Built with BildsyPS — AI-powered shell orchestrator`nhttps://github.com/gsultani/bildsyps"
8. If the app uses data persistence, store ALL data files (JSON, SQLite, logs, config) in:
   $appDataDir = Join-Path $env:APPDATA $appName
   Create the directory if it does not exist. NEVER store data files alongside the script or exe.
9. Add proper form disposal and cleanup.
10. The script must work when compiled to .exe via ps2exe.
10b. Do NOT use PowerShell 7+ only operators: ?? (null-coalescing), ??= (null-coalescing
    assignment), or ?. / ?[] (null-conditional). These break ps2exe which targets Windows
    PowerShell 5.1. Use if ($null -ne $x) { $x } else { $default } instead.
11. The FIRST file that contains UI code must start with:
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
12. NEVER hardcode or generate placeholder API keys, tokens, passwords, or secrets in the code.
    If the app needs API credentials, create a Settings dialog where the user can enter their own
    key at runtime. Persist settings to the app's JSON config file (see rule 8). Mask the key
    in the UI with PasswordChar='*'.
13. Variables assigned inside WinForms event handler scriptblocks (Add_Click, Add_PrintPage,
    etc.) are scoped locally. To share data between a handler and its parent function, store
    values on the Form's .Tag property, a hashtable, or an ArrayList (reference types).
    NEVER rely on bare $variable = value inside handlers to update parent-scope variables.
14. CRITICAL: When programmatically setting SelectedIndex on a ComboBox or ListBox (e.g. during
    init or grid refresh), use a $global:suppressEvents flag to prevent infinite recursion.
    Set $global:suppressEvents = $true BEFORE the change, $false AFTER. Check the flag at the
    top of every SelectedIndexChanged handler: if ($global:suppressEvents) { return }.
15. When a variable is followed by a colon inside a double-quoted string, PowerShell interprets
    it as a drive/scope qualifier (e.g. "$statusCode:" is parsed as $statusCode: drive).
    Always use the subexpression operator: "$($statusCode):" or braces "${statusCode}:".
16. NEVER use empty catch blocks (catch { }). Always log or display the error. At minimum use:
    catch { Write-Host "Error: $_" -ForegroundColor Red } or show a MessageBox.
17. NEVER use array += in a loop. It copies the entire array every iteration and is O(n²).
    Use [System.Collections.ArrayList]::new() with .Add(), or [System.Collections.Generic.List[string]]::new().

Output ONLY the code blocks. No explanations before or after.
'@

$script:BuilderTkinterPrompt = @'
You are a Python Tkinter application code generator. Given a specification, produce a complete, runnable Python application using Tkinter.

RULES:
1. Output a SINGLE app.py file. Use fenced code block with filename: ```python app.py
2. Use ONLY Python standard library imports. No pip packages. No external dependencies.
3. All code in a single file. No separate modules.
4. Use proper error handling with try/except blocks.
{THEME_RULE}
6. Add a mandatory startup splash screen (1.5 seconds):
   - 400x200 window, centered, no title bar (overrideredirect=True)
   - Use the app's theme background, text "Built with BildsyPS" in the accent color, 16pt
   - Below: app name in the foreground color, 12pt
   - Auto-close after 1500ms via root.after()
7. Add a Help menu with "About" that shows:
   messagebox.showinfo("About", "Built with BildsyPS\nhttps://github.com/gsultani/bildsyps")
8. If the app uses data persistence, use JSON or SQLite in:
   Path.home() / f'.{app_name}' / 'data.json'
9. Use if __name__ == '__main__': guard.
10. Use ttk widgets where possible for native look.
10b. Use grid() geometry manager for all widget placement (not pack() or place()). Define
    row/column weights so the UI resizes proportionally.
11. NEVER hardcode or generate placeholder API keys, tokens, passwords, or secrets in the code.
    If the app needs API credentials, create a Settings window where the user can enter their own
    key at runtime. Persist settings to the app's JSON config file (see rule 8). Mask the key
    in the UI with show='*'.

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
{THEME_RULE}
5. Add a branded startup splash overlay in index.html:
   - Full-screen overlay div using the app's theme background, "Built with BildsyPS" in accent color
   - Fades out after 1.5 seconds via CSS animation + JS setTimeout
   - Footer: <footer style="text-align:center;padding:8px;color:#666;font-size:11px">Built with BildsyPS</footer>
6. If the app uses data persistence, use JSON or SQLite in:
   Path.home() / f'.{app_name}' / 'data.json'
7. Use if __name__ == '__main__': guard in app.py.
8. requirements.txt must contain: pywebview
9. NEVER hardcode or generate placeholder API keys, tokens, passwords, or secrets in the code.
   If the app needs API credentials, create a Settings panel in the HTML UI where the user can
   enter their own key at runtime. Persist settings via the Python js_api to the app's JSON
   config file (see rule 6). Use <input type="password"> for key fields.

Output ONLY the code blocks. No explanations before or after.
'@

$script:BuilderTauriPrompt = @'
You are a Tauri v2 desktop application code generator. Given a specification, produce a complete, buildable Tauri project with a Rust backend and plain HTML/CSS/JS frontend.

RULES:
1. Output these files, each in its own fenced code block with filename:
   ```toml src-tauri/Cargo.toml
   ```rust src-tauri/src/main.rs
   ```json src-tauri/tauri.conf.json
   ```rust src-tauri/build.rs
   ```html web/index.html
   ```css web/style.css
   ```javascript web/script.js
2. src-tauri/Cargo.toml: use tauri 2.x with features ["devtools"]. Name the package after the app.
3. src-tauri/src/main.rs: use tauri::Builder, register any Tauri commands with #[tauri::command].
   Expose backend functions to the frontend via invoke(). Use serde for serialization.
4. src-tauri/tauri.conf.json (Tauri v2 format):
   - "identifier": "com.bildsyps.<appname>", "productName": "<App Name>", "version": "0.1.0"
   - "build": { "frontendDist": "../web" }  — NO devPath or distDir (those are Tauri v1).
   - Do NOT include devUrl unless you are using a live dev server.
   - Do NOT include an "allowlist" object (that is Tauri v1). Use "app": { "security": { "csp": null } } if needed.
5. src-tauri/build.rs: standard tauri_build::build() call.
6. Frontend in web/: plain HTML5, vanilla ES6+ JS, CSS. No frameworks, no bundler, no npm.
{THEME_RULE}
8. Add a branded startup splash overlay in index.html:
   - Full-screen overlay div using the app's theme background, "Built with BildsyPS" in accent color
   - Fades out after 1.5 seconds via CSS animation + JS setTimeout
   - Footer: <footer style="text-align:center;padding:8px;color:#666;font-size:11px">Built with BildsyPS</footer>
9. If the app needs data persistence, use Tauri fs API + JSON file in the app data directory.
   Access via @tauri-apps/api path and fs modules from the JS side, or Rust-side file I/O.
10. NEVER hardcode or generate placeholder API keys, tokens, passwords, or secrets in the code.
    If the app needs API credentials, create a Settings panel in the HTML UI where the user can
    enter their own key at runtime. Persist settings via a Tauri command to the app's JSON
    config file. Use <input type="password"> for key fields.
11. Use the __TAURI__ global or window.__TAURI__.invoke() for frontend-to-backend communication.
12. All Rust code must compile with stable Rust. No nightly features.

Output ONLY the code blocks. No explanations before or after.
'@

$script:BuilderPowerShellModulePrompt = @'
You are a PowerShell module code generator. Given a specification, produce an installable PowerShell module with proper structure.

RULES:
1. Output these files, each in its own fenced code block with filename:
   ```powershell {ModuleName}.psm1
   ```powershell {ModuleName}.psd1
   ```json config.json (only if the app needs persistent settings)
   ```text README.txt
2. The .psm1 file contains ALL exported functions. No dot-sourcing other scripts.
3. Every function MUST use an approved verb-noun name (Get-, Set-, New-, Remove-, Add-, Clear-,
   Close-, Copy-, Enter-, Exit-, Find-, Format-, Hide-, Join-, Lock-, Move-, Open-, Invoke-,
   Start-, Stop-, Test-, Write-, Read-, Import-, Export-, ConvertTo-, ConvertFrom-, Install-,
   Uninstall-, Register-, Unregister-, Update-, Enable-, Disable-, Publish-, Save-, Sync-,
   Compare-, Compress-, Expand-, Merge-, Split-, Search-, Select-, Show-, Wait-, Watch-,
   Backup-, Checkpoint-, Confirm-, Debug-, Grant-, Group-, Limit-, Measure-, Mount-, Protect-,
   Receive-, Send-, Repair-, Request-, Reset-, Resize-, Restore-, Revoke-, Resume-, Suspend-,
   Unblock-, Unprotect-, Use-, Trace-, Rename-, Redo-, Undo-, Optimize-, Pop-, Push-, Skip-,
   Step-, Switch-).
4. Every function includes [CmdletBinding()] and typed parameter declarations.
5. Functions that process collections MUST support pipeline input via [Parameter(ValueFromPipeline)].
6. Error handling: try/catch with Write-Error -ErrorAction Stop for critical failures.
7. All user-facing output uses Write-Output (NEVER Write-Host) to preserve pipeline compatibility.
8. Each function includes comment-based help: .SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE.
9. User config stored in: Join-Path $env:APPDATA "Bildsy\{ModuleName}\config.json"
10. The .psd1 manifest MUST include: ModuleVersion='1.0.0', FunctionsToExport (list ALL functions),
    PowerShellVersion='5.1', Description, Author='Generated by BildsyPS'.
11. Do NOT use external modules (no Import-Module for non-built-in modules).
12. .NET Framework classes are allowed for functionality not in native cmdlets.
13. NEVER hardcode API keys, tokens, or secrets. Use config.json for user-provided credentials.
14. README.txt: installation instructions for PS5.1 and PS7, list of exported functions.
15. Module header: # Generated by BildsyPS — AI-powered shell orchestrator
    # https://github.com/gsultani/bildsyps
    # Generated: {timestamp}

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Framework
    )

    # User override wins
    if ($Framework) {
        $valid = @('powershell', 'powershell-module', 'python-tk', 'python-web', 'tauri')
        if ($Framework -in $valid) { return $Framework }
        Write-Host "[AppBuilder] Unknown framework '$Framework'. Valid: $($valid -join ', ')" -ForegroundColor Yellow
    }

    $lower = $Prompt.ToLower()

    # Explicit triggers
    if ($lower -match '\b(powershell\s*module|ps\s*module|psm1|cmdlet|automation\s*module|profile\s*module)\b') {
        return 'powershell-module'
    }
    if ($lower -match '\b(tauri|rust\s*gui|rust\s*app|native\s*web|tauri\s*app)\b') {
        return 'tauri'
    }
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
    [CmdletBinding()]
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

    $limit = 8192  # Default: safe for most providers

    # Exact match
    if ($Model -and $outputLimits.ContainsKey($Model)) {
        $limit = $outputLimits[$Model]
    }
    else {
        # Fuzzy match: check if model name contains a known key (longest key first for specificity)
        if ($Model) {
            foreach ($key in ($outputLimits.Keys | Sort-Object { $_.Length } -Descending)) {
                if ($Model -like "*$key*") {
                    $limit = $outputLimits[$key]
                    break
                }
            }
        }
    }

    return $limit
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
        [string]$Model,
        [string]$Theme = 'system'
    )

    $frameworkLabel = switch ($Framework) {
        'powershell'        { 'POWERSHELL (Windows Forms GUI, single .ps1 file, ps2exe compatible)' }
        'powershell-module' { 'POWERSHELL_MODULE (installable .psm1 module with .psd1 manifest, verb-noun functions, no GUI)' }
        'python-tk'         { 'PYTHON_TKINTER (single app.py, stdlib only)' }
        'python-web'        { 'PYTHON_PYWEBVIEW (app.py + web/index.html + CSS + JS)' }
        'tauri'             { 'TAURI_V2 (Rust backend + HTML/CSS/JS frontend, native desktop app)' }
    }

    $themeStyle = $script:ThemePresets[$Theme]['refine']
    $systemPrompt = $script:BuilderRefinePrompt -replace '\{FRAMEWORK_PLACEHOLDER\}', $frameworkLabel
    $systemPrompt = $systemPrompt -replace '\{THEME_STYLE\}', $themeStyle

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

# ===== Planning Agent =====

function Invoke-BuildPlanning {
    <#
    .SYNOPSIS
    LLM call: Decompose complex specifications into structured plans.
    Triggers only when spec word count exceeds 150 words.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Spec,
        [Parameter(Mandatory)][string]$Framework,
        [string]$Provider,
        [string]$Model
    )

    $wordCount = ($Spec -split '\s+').Count
    if ($wordCount -le 150) {
        return @{ Success = $true; Plan = $null; Skipped = $true }
    }

    $planPrompt = @'
You are a software architect. Given an application specification, produce a structured implementation plan.

Output format:
COMPONENTS:
- component name: description
FUNCTIONS:
- function/method name: purpose
DATA_MODEL:
- entity: fields and relationships
FILE_STRUCTURE:
- filename: purpose
STATE_MANAGEMENT:
- what state is tracked and how
ERROR_HANDLING:
- key error scenarios and recovery

Be concise. Output ONLY the plan structure, no code.
'@

    if ($Framework -eq 'powershell-module') {
        $planPrompt += "`nThis is a PowerShell module (no UI). Focus on function decomposition, parameter design, and pipeline flow."
    }

    $messages = @(
        @{ role = 'user'; content = "Plan the implementation for this specification:`n`n$Spec" }
    )

    $params = @{
        Messages     = $messages
        SystemPrompt = $planPrompt
        MaxTokens    = 2048
        Temperature  = 0.3
    }
    if ($Provider) { $params.Provider = $Provider }
    if ($Model) { $params.Model = $Model }

    try {
        Write-Host "[AppBuilder] Planning complex app (spec: $wordCount words)..." -ForegroundColor Cyan
        $response = Invoke-ChatCompletion @params
        $plan = if ($response.Content) { $response.Content } else { "$response" }
        return @{ Success = $true; Plan = $plan; Skipped = $false }
    }
    catch {
        Write-Host "[AppBuilder] Planning failed (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
        return @{ Success = $true; Plan = $null; Skipped = $true }
    }
}

# ===== Review Agent =====

function Invoke-BuildReview {
    <#
    .SYNOPSIS
    LLM call: Check generated code against the specification for alignment.
    Returns pass/fail with specific issues.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Files,
        [Parameter(Mandatory)][string]$Spec,
        [Parameter(Mandatory)][string]$Framework,
        [string]$Provider,
        [string]$Model
    )

    $reviewPrompt = @'
You are a code reviewer. Compare the generated code against the specification and check:
1. Do all specified FEATURES exist in the code?
2. Is the DATA_MODEL implemented as specified?
3. Are EDGE_CASES from the spec addressed?
4. Is the UI_LAYOUT correct (if applicable)?

Output format:
PASSED: true/false
ISSUES:
- issue description (if any)

If all features are implemented correctly, output PASSED: true with no issues.
Be strict but fair. Minor style differences are acceptable.
'@

    $codeContext = ($Files.Keys | ForEach-Object {
        "--- $_ ---`n$($Files[$_])"
    }) -join "`n`n"

    $messages = @(
        @{ role = 'user'; content = "Specification:`n$Spec`n`nGenerated code:`n$codeContext" }
    )

    $params = @{
        Messages     = $messages
        SystemPrompt = $reviewPrompt
        MaxTokens    = 4096
        Temperature  = 0.2
    }
    if ($Provider) { $params.Provider = $Provider }
    if ($Model) { $params.Model = $Model }

    try {
        Write-Host "[AppBuilder] Reviewing code against spec..." -ForegroundColor Cyan
        $response = Invoke-ChatCompletion @params
        $content = if ($response.Content) { $response.Content } else { "$response" }

        $passed = $content -match 'PASSED:\s*true'
        $issues = [System.Collections.Generic.List[string]]::new()

        if (-not $passed -and $content -match '(?s)ISSUES:\s*\n(.+)') {
            $issueBlock = $Matches[1]
            foreach ($line in ($issueBlock -split "`n")) {
                $trimmed = $line.Trim() -replace '^-\s*', ''
                if ($trimmed -and $trimmed.Length -gt 3) {
                    $issues.Add($trimmed)
                }
            }
        }

        return @{ Passed = $passed; Issues = @($issues); Raw = $content }
    }
    catch {
        Write-Host "[AppBuilder] Review failed (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
        return @{ Passed = $true; Issues = @(); Raw = '' }
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
        [string]$Model,
        [string]$Theme = 'system'
    )

    $systemPrompt = switch ($Framework) {
        'powershell'        { $script:BuilderPowerShellPrompt }
        'powershell-module' { $script:BuilderPowerShellModulePrompt }
        'python-tk'         { $script:BuilderTkinterPrompt }
        'python-web'        { $script:BuilderPyWebViewPrompt }
        'tauri'             { $script:BuilderTauriPrompt }
    }

    $themeRule = $script:ThemePresets[$Theme][$Framework]
    $systemPrompt = $systemPrompt -replace '\{THEME_RULE\}', $themeRule

    # Inject learned constraints from build memory
    $constraints = Get-BuildConstraints -Framework $Framework
    if ($constraints.Count -gt 0) {
        $constraintBlock = ($constraints | ForEach-Object { "- $_" }) -join "`n"
        $systemPrompt += "`n`nLEARNED CONSTRAINTS (from previous build failures — follow these strictly):`n$constraintBlock"
    }

    $messages = @(
        @{ role = 'user'; content = "Generate the application from this specification:`n`n$Spec" }
    )

    # Scale timeout with token budget: 5min base + 1s per 100 tokens
    $timeoutSec = [math]::Max(300, 300 + [math]::Ceiling($MaxTokens / 100))

    $params = @{
        Messages     = $messages
        SystemPrompt = $systemPrompt
        MaxTokens    = $MaxTokens
        Temperature  = 0.3
        TimeoutSec   = $timeoutSec
    }
    if ($Provider) { $params.Provider = $Provider }
    if ($Model) { $params.Model = $Model }

    try {
        Write-Host "[AppBuilder] Generating code ($Framework, max $MaxTokens tokens, timeout ${timeoutSec}s)..." -ForegroundColor Cyan
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
            # Use filename from fence line if available (e.g., ```powershell app.ps1)
            $fileName = $block.FileName

            if (-not $fileName) {
                # Fallback: infer filename from language tag
                $fileName = switch ($block.Language) {
                    'powershell' { if ($Framework -eq 'powershell-module') { if ($files.Keys -match '\.psm1$') { 'module.psd1' } else { 'module.psm1' } } else { if ($files.ContainsKey('app.ps1')) { "source/file_$($block.Index).ps1" } else { 'app.ps1' } } }
                    'ps1'        { if ($files.ContainsKey('app.ps1')) { "source/file_$($block.Index).ps1" } else { 'app.ps1' } }
                    'psd1'       { 'module.psd1' }
                    'python'     { if ($files.ContainsKey('app.py')) { "module_$($block.Index).py" } else { 'app.py' } }
                    'py'         { if ($files.ContainsKey('app.py')) { "module_$($block.Index).py" } else { 'app.py' } }
                    'html'       { 'web/index.html' }
                    'css'        { 'web/style.css' }
                    'javascript' { 'web/script.js' }
                    'js'         { 'web/script.js' }
                    'rust'       { if (-not $files.ContainsKey('src-tauri/src/main.rs')) { 'src-tauri/src/main.rs' } elseif (-not $files.ContainsKey('src-tauri/build.rs')) { 'src-tauri/build.rs' } else { "src-tauri/src/file_$($block.Index).rs" } }
                    'rs'         { if (-not $files.ContainsKey('src-tauri/src/main.rs')) { 'src-tauri/src/main.rs' } elseif (-not $files.ContainsKey('src-tauri/build.rs')) { 'src-tauri/build.rs' } else { "src-tauri/src/file_$($block.Index).rs" } }
                    'toml'       { 'src-tauri/Cargo.toml' }
                    'json'       { if ($Framework -eq 'tauri') { 'src-tauri/tauri.conf.json' } else { "file_$($block.Index).json" } }
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
            'powershell'        { 'app.ps1' }
            'powershell-module' { $files.Keys | Where-Object { $_ -match '\.psm1$' } | Select-Object -First 1 }
            'tauri'             { 'src-tauri/src/main.rs' }
            default             { 'app.py' }
        }
        if (-not $primaryFile) { $primaryFile = 'module.psm1' }
        if (-not $files.ContainsKey($primaryFile)) {
            # Try to find the closest match
            $candidate = $files.Keys | Where-Object { $_ -match '\.(ps1|psm1|py|rs)$' } | Select-Object -First 1
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

# ===== Code Repair (pre-validation) =====

function Repair-GeneratedCode {
    <#
    .SYNOPSIS
    Auto-repair common LLM code generation mistakes before validation.
    Uses the PowerShell parser to locate exact error positions and fix them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Files,
        [Parameter(Mandatory)][string]$Framework
    )

    $totalFixes = 0
    $knownScopes = @('global','local','script','private','using','workflow','env','variable','function','alias')

    foreach ($fileName in @($Files.Keys)) {
        $ext = [System.IO.Path]::GetExtension($fileName).ToLower()
        if ($ext -ne '.ps1' -and $ext -ne '.psm1') { continue }

        $code = $Files[$fileName]
        $fileFixes = 0
        $maxPasses = 30

        for ($pass = 0; $pass -lt $maxPasses; $pass++) {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errors)

            $varErr = $errors | Where-Object { $_.Message -match 'Variable reference is not valid' } | Select-Object -First 1
            if (-not $varErr) { break }

            $startOff = $varErr.Extent.StartOffset
            $errText  = $varErr.Extent.Text

            if ($varErr.Message -match "':' was not followed") {
                # Pattern: $varName: where varName is not a valid scope
                if ($errText -match '^\$(\w+):') {
                    $varName = $Matches[1]
                    if ($knownScopes -contains $varName.ToLower()) {
                        $code = $code.Substring(0, $startOff) + '`' + $code.Substring($startOff)
                    }
                    else {
                        $endOff = $startOff + $errText.Length
                        $code = $code.Substring(0, $startOff) + "`$(`$$varName):" + $code.Substring($endOff)
                    }
                }
                else {
                    $code = $code.Substring(0, $startOff) + '`' + $code.Substring($startOff)
                }
                $fileFixes++
            }
            else {
                # Pattern: bare $ not followed by valid variable name char — escape it
                $code = $code.Substring(0, $startOff) + '`$' + $code.Substring($startOff + 1)
                $fileFixes++
            }
        }

        if ($fileFixes -gt 0) {
            $Files[$fileName] = $code
            $totalFixes += $fileFixes
        }
    }

    return $totalFixes
}

# ===== Code Validation =====

function Test-GeneratedCode {
    <#
    .SYNOPSIS
    Validate generated code: syntax check, security scan, import validation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Files,
        [Parameter(Mandatory)][string]$Framework
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($fileName in $Files.Keys) {
        $code = $Files[$fileName]
        $ext = [System.IO.Path]::GetExtension($fileName).ToLower()

        # Syntax check
        if ($ext -eq '.ps1' -or $ext -eq '.psm1') {
            $tempFile = Join-Path $env:TEMP "bildsyps_validate_$(Get-Random)$ext"
            try {
                $code | Set-Content $tempFile -Encoding UTF8
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($tempFile, [ref]$tokens, [ref]$parseErrors) | Out-Null
                if ($parseErrors.Count -gt 0) {
                    foreach ($pe in $parseErrors) {
                        $errors.Add("[$fileName] Syntax error line $($pe.Extent.StartLineNumber): $($pe.Message)")
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
                        $errors.Add("[$fileName] Python syntax error: $resultStr")
                    }
                }
                finally { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            }
        }
        elseif ($ext -eq '.rs') {
            if (-not $code -or $code.Trim().Length -lt 10) {
                $errors.Add("[$fileName] Rust file appears empty or trivially small")
            }
        }

        # PS 5.1 compatibility: reject PS7+ only operators in .ps1 files
        if ($ext -eq '.ps1') {
            foreach ($cp in $script:PS7CompatPatterns) {
                if ($code -match $cp.Pattern) {
                    $errors.Add("[$fileName] Compatibility: contains $($cp.Name)")
                }
            }
        }

        # Tauri HTML structure validation
        if ($Framework -eq 'tauri' -and $ext -eq '.html') {
            if ($code -notmatch '<!DOCTYPE') {
                $errors.Add("[$fileName] HTML: missing <!DOCTYPE html> declaration")
            }
            if ($code -notmatch '<head[\s>]') {
                $errors.Add("[$fileName] HTML: missing <head> element")
            }
            if ($code -notmatch '<body[\s>]') {
                $errors.Add("[$fileName] HTML: missing <body> element")
            }
            # Block external script/link sources (Tauri apps must be self-contained)
            if ($code -match '<script[^>]+src\s*=\s*["'']https?://') {
                $errors.Add("[$fileName] Security: external <script src> not allowed in Tauri apps")
            }
            if ($code -match '<link[^>]+href\s*=\s*["'']https?://') {
                $errors.Add("[$fileName] Security: external <link href> not allowed in Tauri apps")
            }
        }

        # Tauri JS security validation (inline scripts in HTML + .js files)
        if ($Framework -eq 'tauri' -and ($ext -eq '.js' -or $ext -eq '.html')) {
            foreach ($jp in $script:DangerousJavaScriptPatterns) {
                if ($code -match $jp.Pattern) {
                    $errors.Add("[$fileName] JS Security: contains $($jp.Name)")
                }
            }
        }

        # Security scan: language-aware dangerous patterns
        $dangerousPatterns = switch ($ext) {
            '.ps1' { $script:DangerousPowerShellPatterns }
            '.py'  { $script:DangerousPythonPatterns }
            default { $script:DangerousPowerShellPatterns + $script:DangerousPythonPatterns }
        }

        foreach ($dp in $dangerousPatterns) {
            if ($code -match $dp.Pattern) {
                $errors.Add("[$fileName] Security: contains $($dp.Name)")
            }
        }

        # Secret scan
        if (Get-Command Invoke-SecretScan -ErrorAction SilentlyContinue) {
            $tempScan = Join-Path $env:TEMP "bildsyps_secretscan_$(Get-Random)$ext"
            try {
                $code | Set-Content $tempScan -Encoding UTF8
                $findings = Invoke-SecretScan -Paths @($tempScan)
                foreach ($f in $findings) {
                    $errors.Add("[$fileName] Secret detected (line $($f.Line)): $($f.Pattern) -- $($f.Masked)")
                }
            }
            finally { Remove-Item $tempScan -Force -ErrorAction SilentlyContinue }
        }
    }

    # Tauri Rust validation: lightweight manifest + structure checks
    if ($Framework -eq 'tauri') {
        $tomlFile = $Files.Keys | Where-Object { $_ -match 'Cargo\.toml$' } | Select-Object -First 1
        $rsFiles  = @($Files.Keys | Where-Object { $_ -match '\.rs$' })

        if ($tomlFile) {
            $tomlContent = $Files[$tomlFile]
            # Check required TOML sections
            if ($tomlContent -notmatch '\[package\]') {
                $errors.Add("[Tauri] Cargo.toml missing [package] section")
            }
            if ($tomlContent -notmatch '\[dependencies\]') {
                $errors.Add("[Tauri] Cargo.toml missing [dependencies] section")
            }
            if ($tomlContent -notmatch 'tauri\s*=') {
                $errors.Add("[Tauri] Cargo.toml missing tauri dependency")
            }
            # Check that main.rs exists in generated files
            $hasMain = $rsFiles | Where-Object { $_ -match 'main\.rs$' }
            if (-not $hasMain) {
                $errors.Add("[Tauri] Missing main.rs — required for Tauri binary")
            }
            # If [lib] section declared, check lib.rs exists
            if ($tomlContent -match '\[lib\]') {
                $hasLib = $rsFiles | Where-Object { $_ -match 'lib\.rs$' }
                if (-not $hasLib) {
                    $errors.Add("[Tauri] Cargo.toml declares [lib] but no lib.rs was generated")
                }
            }
            # Validate build.rs exists if build-dependencies are declared
            if ($tomlContent -match '\[build-dependencies\]') {
                $hasBuildRs = $rsFiles | Where-Object { $_ -match 'build\.rs$' }
                if (-not $hasBuildRs) {
                    $errors.Add("[Tauri] Cargo.toml has [build-dependencies] but no build.rs was generated")
                }
            }
        }
        else {
            $errors.Add("[Tauri] Missing Cargo.toml")
        }

        # Basic Rust syntax: check balanced braces in each .rs file
        foreach ($rsFile in $rsFiles) {
            $rsCode = $Files[$rsFile]
            $openBraces  = ([regex]::Matches($rsCode, '\{')).Count
            $closeBraces = ([regex]::Matches($rsCode, '\}')).Count
            if ($openBraces -ne $closeBraces) {
                $errors.Add("[$rsFile] Rust syntax: unbalanced braces (open=$openBraces, close=$closeBraces)")
            }
        }
    }

    # PowerShell Module-specific validators
    if ($Framework -eq 'powershell-module') {
        # Naming validator: check exported functions use approved verbs
        $approvedVerbs = (Get-Verb).Verb
        foreach ($fn in $Files.Keys) {
            $fext = [System.IO.Path]::GetExtension($fn).ToLower()
            if ($fext -ne '.psm1') { continue }
            $funcNames = [regex]::Matches($Files[$fn], 'function\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
            foreach ($funcName in $funcNames) {
                if ($funcName -match '^(\w+)-') {
                    $verb = $Matches[1]
                    if ($verb -notin $approvedVerbs) {
                        $errors.Add("[$fn] Naming: function '$funcName' uses unapproved verb '$verb'. Use Get-Verb for approved verbs.")
                    }
                }
            }
        }

        # Completeness validator: at least one exported function, psm1 exists
        $hasPsm1 = $Files.Keys | Where-Object { $_ -match '\.psm1$' }
        if (-not $hasPsm1) {
            $errors.Add("[module] Completeness: no .psm1 file found")
        }
        else {
            $psm1Code = $Files[$hasPsm1]
            $funcCount = ([regex]::Matches($psm1Code, 'function\s+[\w-]+')).Count
            if ($funcCount -eq 0) {
                $errors.Add("[$hasPsm1] Completeness: module contains no exported functions")
            }
        }

        # Manifest validator: check .psd1 has required fields
        $hasPsd1 = $Files.Keys | Where-Object { $_ -match '\.psd1$' }
        if ($hasPsd1) {
            $psd1Code = $Files[$hasPsd1]
            if ($psd1Code -notmatch 'ModuleVersion') {
                $errors.Add("[$hasPsd1] Manifest: missing ModuleVersion field")
            }
            if ($psd1Code -notmatch 'FunctionsToExport') {
                $errors.Add("[$hasPsd1] Manifest: missing FunctionsToExport field")
            }
            if ($psd1Code -notmatch 'Description') {
                $errors.Add("[$hasPsd1] Manifest: missing Description field")
            }
        }

        # Module security: block COM objects, remote WMI, network listeners
        foreach ($fn in $Files.Keys) {
            $fext = [System.IO.Path]::GetExtension($fn).ToLower()
            if ($fext -ne '.psm1') { continue }
            $fcode = $Files[$fn]
            if ($fcode -match 'New-Object\s+-ComObject') {
                $errors.Add("[$fn] Security: New-Object -ComObject is not allowed in modules")
            }
            if ($fcode -match 'Get-WmiObject.*-ComputerName|Get-CimInstance.*-ComputerName') {
                $errors.Add("[$fn] Security: remote WMI/CIM queries are not allowed")
            }
            if ($fcode -match 'System\.Net\.(HttpListener|Sockets\.TcpListener)') {
                $errors.Add("[$fn] Security: network listeners are not allowed in modules")
            }
        }
    }

    if ($errors.Count -gt 0) {
        return @{ Success = $false; Errors = @($errors) }
    }
    return @{ Success = $true; Errors = @() }
}

# ===== Fix Loop (retry on validation failure) =====

function Invoke-BuildFixLoop {
    <#
    .SYNOPSIS
    Retry code generation when validation fails, feeding errors back to the LLM.
    Saves learned constraints to build memory on final failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Spec,
        [Parameter(Mandatory)][string]$Framework,
        [Parameter(Mandatory)][array]$Errors,
        [int]$MaxTokens,
        [string]$Provider,
        [string]$Model,
        [string]$Theme = 'system',
        [int]$MaxRetries = 3
    )

    for ($retry = 1; $retry -le $MaxRetries; $retry++) {
        $errorBlock = ($Errors | ForEach-Object { "- $_" }) -join "`n"
        if ($retry -le 1) {
            $fixSpec = "PREVIOUS ATTEMPT FAILED with these errors:`n$errorBlock`n`nFix ALL of the above errors. Original specification:`n$Spec"
        }
        else {
            # On later retries, use focused context to avoid prompt bloat
            $fixSpec = "ATTEMPT $retry FIX — the following errors STILL remain:`n$errorBlock`n`nFix ONLY these remaining errors. Keep all working code intact. Original app name and framework from spec:`n$($Spec -split "`n" | Select-Object -First 10 | Out-String)"
        }

        Write-Host "[AppBuilder] Fix attempt $retry/$MaxRetries..." -ForegroundColor Yellow

        $codeResult = Invoke-CodeGeneration -Spec $fixSpec -Framework $Framework `
            -MaxTokens $MaxTokens -Provider $Provider -Model $Model -Theme $Theme
        if (-not $codeResult.Success) {
            Write-Host "[AppBuilder] Fix attempt $retry generation failed: $($codeResult.Output)" -ForegroundColor Red
            continue
        }

        $null = Repair-GeneratedCode -Files $codeResult.Files -Framework $Framework
        $validation = Test-GeneratedCode -Files $codeResult.Files -Framework $Framework

        if ($validation.Success) {
            Write-Host "[AppBuilder] Fix attempt $retry succeeded." -ForegroundColor Green
            return @{ Success = $true; Files = $codeResult.Files; Raw = $codeResult.Raw }
        }

        $Errors = $validation.Errors
        Write-Host "[AppBuilder] Fix attempt $retry still has $($Errors.Count) error(s)." -ForegroundColor Yellow
    }

    # All retries exhausted — save constraints to build memory
    foreach ($err in $Errors) {
        $constraint = ConvertTo-BuildConstraint -ErrorText $err -Framework $Framework
        Save-BuildConstraint -Framework $Framework -Constraint $constraint -ErrorPattern $err
    }
    Write-Host "[AppBuilder] Saved $($Errors.Count) constraint(s) to build memory for future builds." -ForegroundColor DarkYellow

    return @{ Success = $false; Errors = $Errors }
}

# ===== Branding Injection =====

function Invoke-BildsyPSBranding {
    <#
    .SYNOPSIS
    Verify branding is present in generated code. Patch it in if LLM omitted it.
    #>
    [CmdletBinding()]
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
        'tauri' {
            $key = 'web/index.html'
            if ($Files.ContainsKey($key) -and $Files[$key] -notmatch [regex]::Escape($brandingText)) {
                $footer = '<footer style="text-align:center;padding:8px;color:#666;font-size:11px">Built with BildsyPS</footer>'
                if ($Files[$key] -match '</body>') {
                    $Files[$key] = $Files[$key] -replace '</body>', "$footer`n</body>"
                }
                else {
                    $Files[$key] += "`n$footer"
                }
            }
        }
        'powershell-module' {
            $psm1Key = $Files.Keys | Where-Object { $_ -match '\.psm1$' } | Select-Object -First 1
            if ($psm1Key -and $Files[$psm1Key] -notmatch [regex]::Escape('Generated by BildsyPS')) {
                $header = "# Generated by BildsyPS — AI-powered shell orchestrator`n# https://github.com/gsultani/bildsyps`n# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n"
                $Files[$psm1Key] = $header + $Files[$psm1Key]
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
    [CmdletBinding()]
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

function Merge-PowerShellSources {
    <#
    .SYNOPSIS
    Merge multiple .ps1 source files into a single script for ps2exe compilation.
    Strips dot-source lines and orders files so dependencies come before dependents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [string]$OutputFile
    )

    if (-not $OutputFile) {
        $OutputFile = Join-Path $SourceDir '_merged.ps1'
    }

    $appFile = Join-Path $SourceDir 'app.ps1'
    if (-not (Test-Path $appFile)) {
        return @{ Success = $false; Output = "Entry point not found: $appFile"; MergedPath = $null }
    }

    # Collect all .ps1 files
    $allFiles = Get-ChildItem $SourceDir -Filter '*.ps1' -Recurse -File | Where-Object { $_.Name -ne '_merged.ps1' }

    if ($allFiles.Count -le 1) {
        # Single file — no merge needed, just return app.ps1
        return @{ Success = $true; Output = "Single file, no merge needed"; MergedPath = $appFile }
    }

    # Separate entry point from source files
    $sourceFiles = $allFiles | Where-Object { $_.FullName -ne (Resolve-Path $appFile).Path } | Sort-Object FullName

    # Dot-source pattern: . "$PSScriptRoot\..." or . ".\..." or . .\...
    $dotSourcePattern = '^\s*\.\s+[''"]?\$?(\$PSScriptRoot\\|\.\\|\./).*[''"]?\s*$'

    $merged = [System.Text.StringBuilder]::new()
    $null = $merged.AppendLine("# Merged by BildsyPS build pipeline — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $null = $merged.AppendLine("")

    # Source files first (dependencies before dependents)
    foreach ($f in $sourceFiles) {
        $null = $merged.AppendLine("# ===== $($f.Name) =====")
        $content = Get-Content $f.FullName -Raw -Encoding UTF8
        # Strip dot-source lines from source files too (in case they cross-reference)
        $lines = $content -split "`n"
        $filtered = $lines | Where-Object { $_ -notmatch $dotSourcePattern }
        $null = $merged.AppendLine(($filtered -join "`n"))
        $null = $merged.AppendLine("")
    }

    # Entry point last, with dot-source lines stripped
    $null = $merged.AppendLine("# ===== app.ps1 (entry point) =====")
    $appContent = Get-Content $appFile -Raw -Encoding UTF8
    $appLines = $appContent -split "`n"
    $appFiltered = $appLines | Where-Object { $_ -notmatch $dotSourcePattern }
    $null = $merged.AppendLine(($appFiltered -join "`n"))

    $mergedContent = $merged.ToString()
    Set-Content -Path $OutputFile -Value $mergedContent -Encoding UTF8 -NoNewline

    $fileCount = $sourceFiles.Count + 1
    Write-Host "[AppBuilder] Merged $fileCount source files into _merged.ps1" -ForegroundColor Cyan
    return @{ Success = $true; Output = "Merged $fileCount files"; MergedPath = $OutputFile }
}

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

    # Merge multi-file sources into a single script for ps2exe
    $mergeResult = Merge-PowerShellSources -SourceDir $SourceDir
    if (-not $mergeResult.Success) {
        return @{ Success = $false; Output = "Source merge failed: $($mergeResult.Output)" }
    }
    $inputFile = $mergeResult.MergedPath
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

function Build-TauriExecutable {
    <#
    .SYNOPSIS
    Build a Tauri project to a native .exe via cargo tauri build.
    Requires Rust toolchain (cargo) and cargo-tauri CLI.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$AppName,
        [string]$OutputDir,
        [string]$IconPath
    )

    if (-not $OutputDir) { $OutputDir = Join-Path $global:AppBuilderPath $AppName }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    # Check Rust toolchain
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargo) {
        return @{ Success = $false; Output = "Rust toolchain not found. Install from https://rustup.rs/ and ensure 'cargo' is on PATH." }
    }

    $startTime = Get-Date

    try {
        # Ensure cargo-tauri CLI is installed
        $tauriCli = & cargo install --list 2>&1 | Out-String
        if ($tauriCli -notmatch 'tauri-cli') {
            Write-Host "[AppBuilder] Installing cargo-tauri CLI (first-time setup, may take a few minutes)..." -ForegroundColor Cyan
            & cargo install tauri-cli 2>&1 | Out-Null
        }

        # The tauri project root is the parent of src-tauri
        $tauriProjectRoot = $SourceDir
        $tauriDir = Join-Path $SourceDir 'src-tauri'

        if (-not (Test-Path $tauriDir)) {
            return @{ Success = $false; Output = "src-tauri directory not found in $SourceDir" }
        }

        if (-not (Test-Path (Join-Path $tauriDir 'Cargo.toml'))) {
            return @{ Success = $false; Output = "src-tauri/Cargo.toml not found" }
        }

        # Patch tauri.conf.json: fix common LLM mistakes (v1 keys, invalid devUrl)
        $confPath = Join-Path $tauriDir 'tauri.conf.json'
        if (Test-Path $confPath) {
            try {
                $conf = Get-Content $confPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $patched = $false

                # Fix v1 build keys → v2 frontendDist
                if ($conf.build) {
                    if ($conf.build.PSObject.Properties['devPath']) {
                        $distVal = $conf.build.devPath
                        $conf.build.PSObject.Properties.Remove('devPath')
                        if (-not $conf.build.PSObject.Properties['frontendDist']) {
                            $conf.build | Add-Member -NotePropertyName 'frontendDist' -NotePropertyValue $distVal
                        }
                        $patched = $true
                    }
                    if ($conf.build.PSObject.Properties['distDir']) {
                        $distVal = $conf.build.distDir
                        $conf.build.PSObject.Properties.Remove('distDir')
                        if (-not $conf.build.PSObject.Properties['frontendDist']) {
                            $conf.build | Add-Member -NotePropertyName 'frontendDist' -NotePropertyValue $distVal
                        }
                        $patched = $true
                    }
                    # Remove devUrl if it's a file path (not a URL)
                    if ($conf.build.PSObject.Properties['devUrl'] -and $conf.build.devUrl -notmatch '^https?://') {
                        $conf.build.PSObject.Properties.Remove('devUrl')
                        $patched = $true
                    }
                    # Ensure frontendDist exists
                    if (-not $conf.build.PSObject.Properties['frontendDist']) {
                        $conf.build | Add-Member -NotePropertyName 'frontendDist' -NotePropertyValue '../web'
                        $patched = $true
                    }
                }
                else {
                    $conf | Add-Member -NotePropertyName 'build' -NotePropertyValue ([PSCustomObject]@{ frontendDist = '../web' })
                    $patched = $true
                }

                # Remove v1 allowlist if present
                if ($conf.PSObject.Properties['allowlist']) {
                    $conf.PSObject.Properties.Remove('allowlist')
                    $patched = $true
                }

                if ($patched) {
                    Write-Host "[AppBuilder] Patched tauri.conf.json (fixed v1/v2 config issues)" -ForegroundColor Yellow
                    $conf | ConvertTo-Json -Depth 10 | Set-Content $confPath -Encoding UTF8
                }
            }
            catch {
                Write-Host "[AppBuilder] Warning: Could not patch tauri.conf.json: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Optionally inject icon
        if ($IconPath -and (Test-Path $IconPath)) {
            $iconDir = Join-Path $tauriDir 'icons'
            if (-not (Test-Path $iconDir)) { New-Item -ItemType Directory -Path $iconDir -Force | Out-Null }
            Copy-Item $IconPath (Join-Path $iconDir 'icon.ico') -Force
        }

        Write-Host "[AppBuilder] Building Tauri app (this may take several minutes on first build)..." -ForegroundColor Cyan
        $buildLog = Join-Path $SourceDir 'build_output.log'
        $buildErr = Join-Path $SourceDir 'build_errors.log'

        Start-Process cargo -ArgumentList @('tauri', 'build') `
            -WorkingDirectory $tauriProjectRoot -Wait -NoNewWindow `
            -RedirectStandardOutput $buildLog -RedirectStandardError $buildErr

        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

        # Tauri outputs to src-tauri/target/release/bundle/nsis/*.exe or src-tauri/target/release/<name>.exe
        $releaseExe = Get-ChildItem (Join-Path $tauriDir 'target\release') -Filter '*.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'build-script' } | Select-Object -First 1

        # Also check NSIS bundle
        if (-not $releaseExe) {
            $releaseExe = Get-ChildItem (Join-Path $tauriDir 'target\release\bundle') -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }

        if ($releaseExe) {
            $finalExe = Join-Path $OutputDir "$AppName.exe"
            Copy-Item $releaseExe.FullName $finalExe -Force
            $size = (Get-Item $finalExe).Length
            $sizeStr = if ($size -lt 1MB) { "$([math]::Round($size/1KB))KB" } else { "$([math]::Round($size/1MB, 1))MB" }
            return @{
                Success   = $true
                ExePath   = $finalExe
                Size      = $sizeStr
                BuildTime = $elapsed
                Output    = "Built $AppName.exe ($sizeStr) in ${elapsed}s via Tauri"
            }
        }

        $errContent = if (Test-Path $buildErr) { Get-Content $buildErr -Raw -ErrorAction SilentlyContinue } else { '' }
        $logContent = if (Test-Path $buildLog) { Get-Content $buildLog -Raw -ErrorAction SilentlyContinue } else { '' }
        $combinedErr = @($errContent, $logContent) -join "`n" | Select-Object -First 1
        if ($combinedErr.Length -gt 500) { $combinedErr = $combinedErr.Substring(0, 500) + '...' }
        return @{ Success = $false; Output = "Tauri build failed (${elapsed}s): $combinedErr" }
    }
    catch {
        return @{ Success = $false; Output = "Tauri build error: $($_.Exception.Message)" }
    }
}

function Build-PowerShellModule {
    <#
    .SYNOPSIS
    Package a PowerShell module (.psm1 + .psd1) as a .zip archive.
    No compilation — just validate, inject attribution, generate README if missing, and zip.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$AppName,
        [string]$OutputDir
    )

    if (-not $OutputDir) { $OutputDir = Join-Path $global:AppBuilderPath $AppName }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    $startTime = Get-Date

    try {
        # Convert app name to PascalCase module name
        $moduleName = ($AppName -replace '[^a-zA-Z0-9]', ' ').Trim() -split '\s+' | ForEach-Object {
            if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }
        }
        $moduleName = $moduleName -join ''
        if (-not $moduleName) { $moduleName = 'BildsyModule' }

        # Rename files to use proper module name
        $psm1Files = Get-ChildItem $SourceDir -Filter '*.psm1' -ErrorAction SilentlyContinue
        $psd1Files = Get-ChildItem $SourceDir -Filter '*.psd1' -ErrorAction SilentlyContinue

        if ($psm1Files.Count -eq 0) {
            return @{ Success = $false; Output = "No .psm1 file found in $SourceDir" }
        }

        $psm1Source = $psm1Files[0].FullName
        $psd1Source = if ($psd1Files.Count -gt 0) { $psd1Files[0].FullName } else { $null }

        # Inject attribution header if not present
        $psm1Content = Get-Content $psm1Source -Raw -Encoding UTF8
        $attribution = "# Generated by BildsyPS"
        if ($psm1Content -notmatch [regex]::Escape($attribution)) {
            $header = "# Generated by BildsyPS — AI-powered shell orchestrator`n# https://github.com/gsultani/bildsyps`n# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n"
            $psm1Content = $header + $psm1Content
            Set-Content $psm1Source -Value $psm1Content -Encoding UTF8
        }

        # Generate README.txt if missing
        $readmePath = Join-Path $SourceDir 'README.txt'
        if (-not (Test-Path $readmePath)) {
            # Extract function names from .psm1
            $functions = [regex]::Matches($psm1Content, 'function\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
            $funcList = if ($functions) { ($functions | ForEach-Object { "  - $_" }) -join "`n" } else { "  (none detected)" }

            $readme = @"
$moduleName PowerShell Module
==============================

Installation (PowerShell 7):
  Extract to: `$env:USERPROFILE\Documents\PowerShell\Modules\$moduleName\
  Then: Import-Module $moduleName

Installation (Windows PowerShell 5.1):
  Extract to: `$env:USERPROFILE\Documents\WindowsPowerShell\Modules\$moduleName\
  Then: Import-Module $moduleName

Auto-load: Add 'Import-Module $moduleName' to your `$PROFILE

Exported Functions:
$funcList

Generated by BildsyPS — https://github.com/gsultani/bildsyps
"@
            Set-Content $readmePath -Value $readme -Encoding UTF8
        }

        # Create zip archive
        $zipDir = Join-Path $env:TEMP "bildsyps_zip_$(Get-Random)"
        $moduleDir = Join-Path $zipDir $moduleName
        New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null

        # Copy and rename files into module directory
        Copy-Item $psm1Source (Join-Path $moduleDir "$moduleName.psm1") -Force
        if ($psd1Source) {
            Copy-Item $psd1Source (Join-Path $moduleDir "$moduleName.psd1") -Force
        }
        $configPath = Join-Path $SourceDir 'config.json'
        if (Test-Path $configPath) {
            Copy-Item $configPath (Join-Path $moduleDir 'config.json') -Force
        }
        Copy-Item $readmePath (Join-Path $moduleDir 'README.txt') -Force

        $zipFile = Join-Path $OutputDir "$moduleName.zip"
        if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
        Compress-Archive -Path $moduleDir -DestinationPath $zipFile -Force

        # Cleanup temp
        Remove-Item $zipDir -Recurse -Force -ErrorAction SilentlyContinue

        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
        $size = (Get-Item $zipFile).Length
        $sizeStr = if ($size -lt 1KB) { "${size}B" } elseif ($size -lt 1MB) { "$([math]::Round($size/1KB))KB" } else { "$([math]::Round($size/1MB, 1))MB" }

        return @{
            Success   = $true
            ExePath   = $zipFile
            Size      = $sizeStr
            BuildTime = $elapsed
            Output    = "Built $moduleName.zip ($sizeStr) in ${elapsed}s"
        }
    }
    catch {
        return @{ Success = $false; Output = "Module packaging error: $($_.Exception.Message)" }
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

# ===== Build Memory (learned constraints from failures) =====

function Initialize-BuildMemoryTable {
    if (-not $global:ChatDbReady) { return $false }
    if (-not (Get-Command Get-ChatDbConnection -ErrorAction SilentlyContinue)) { return $false }

    try {
        $conn = Get-ChatDbConnection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS build_memory (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    framework       TEXT NOT NULL,
    constraint_text TEXT NOT NULL,
    error_pattern   TEXT,
    hit_count       INTEGER DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    last_hit_at     TEXT NOT NULL DEFAULT (datetime('now'))
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

function Save-BuildConstraint {
    param(
        [Parameter(Mandatory)][string]$Framework,
        [Parameter(Mandatory)][string]$Constraint,
        [string]$ErrorPattern
    )

    if (-not (Initialize-BuildMemoryTable)) { return }

    try {
        $conn = Get-ChatDbConnection
        $cmd = $conn.CreateCommand()

        # Check for existing constraint (dedup by constraint_text + framework)
        $cmd.CommandText = "SELECT id, hit_count FROM build_memory WHERE framework = @fw AND constraint_text = @ct LIMIT 1"
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@fw", $Framework)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@ct", $Constraint)) | Out-Null
        $reader = $cmd.ExecuteReader()

        if ($reader.Read()) {
            $existingId = $reader['id']
            $newCount = [int]$reader['hit_count'] + 1
            $reader.Close()
            $cmd.Dispose()

            $updateCmd = $conn.CreateCommand()
            $updateCmd.CommandText = "UPDATE build_memory SET hit_count = @hc, last_hit_at = datetime('now') WHERE id = @id"
            $updateCmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@hc", $newCount)) | Out-Null
            $updateCmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@id", $existingId)) | Out-Null
            $updateCmd.ExecuteNonQuery() | Out-Null
            $updateCmd.Dispose()
        }
        else {
            $reader.Close()
            $cmd.Dispose()

            $insertCmd = $conn.CreateCommand()
            $insertCmd.CommandText = "INSERT INTO build_memory (framework, constraint_text, error_pattern) VALUES (@fw, @ct, @ep)"
            $insertCmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@fw", $Framework)) | Out-Null
            $insertCmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@ct", $Constraint)) | Out-Null
            $insertCmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@ep", $(if ($ErrorPattern) { $ErrorPattern } else { [DBNull]::Value }))) | Out-Null
            $insertCmd.ExecuteNonQuery() | Out-Null
            $insertCmd.Dispose()
        }

        $conn.Close()
        $conn.Dispose()
    }
    catch {
        Write-Verbose "AppBuilder: Failed to save build constraint: $($_.Exception.Message)"
    }
}

function Get-BuildConstraints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Framework,
        [int]$Limit = 20
    )

    if (-not (Initialize-BuildMemoryTable)) { return @() }

    try {
        $conn = Get-ChatDbConnection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT constraint_text FROM build_memory WHERE framework = @fw ORDER BY hit_count DESC, last_hit_at DESC LIMIT @lim"
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@fw", $Framework)) | Out-Null
        $cmd.Parameters.Add([Microsoft.Data.Sqlite.SqliteParameter]::new("@lim", $Limit)) | Out-Null
        $reader = $cmd.ExecuteReader()
        $constraints = [System.Collections.Generic.List[string]]::new()
        while ($reader.Read()) {
            $constraints.Add($reader['constraint_text'])
        }
        $reader.Close()
        $cmd.Dispose()
        $conn.Close()
        $conn.Dispose()
        return @($constraints)
    }
    catch { return @() }
}

function ConvertTo-BuildConstraint {
    <#
    .SYNOPSIS
    Categorize a build/validation error into a reusable constraint string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ErrorText,
        [Parameter(Mandatory)][string]$Framework
    )

    switch ($Framework) {
        'powershell' {
            if ($ErrorText -match 'Variable reference is not valid') {
                return "Do not use bare `$ before colons in strings. Use `$(`$var): or escape with backtick."
            }
            if ($ErrorText -match 'empty catch') {
                return "Never use empty catch blocks. Always log or display the error."
            }
            if ($ErrorText -match 'Invoke-Expression|iex ') {
                return "Do not use Invoke-Expression or iex. Use direct function calls instead."
            }
            if ($ErrorText -match 'null-coalescing|\?\?') {
                return "Do not use ?? or ?. operators. They are PS7+ only and break ps2exe."
            }
        }
        'tauri' {
            if ($ErrorText -match 'unresolved import') {
                return "Ensure all Rust use/import statements reference valid crate paths from Cargo.toml dependencies."
            }
            if ($ErrorText -match 'borrow.*moved|moved value') {
                return "Do not move ownership into closures. Use .clone() when the value is needed after the closure."
            }
            if ($ErrorText -match 'missing.*feature|feature.*not found') {
                return "Add all required features to the [dependencies] section in Cargo.toml."
            }
            if ($ErrorText -match 'allowlist|devPath|distDir') {
                return "Use Tauri v2 config format: frontendDist (not devPath/distDir), no allowlist object."
            }
            if ($ErrorText -match 'external.*script|external.*link') {
                return "Tauri apps must be self-contained. Do not load scripts or stylesheets from external URLs."
            }
        }
        'python-tk' {
            if ($ErrorText -match 'import.*error|No module named') {
                return "Use only Python standard library imports. No pip packages."
            }
            if ($ErrorText -match 'geometry manager') {
                return "Use grid() geometry manager consistently. Do not mix pack() and grid() in the same container."
            }
        }
        'python-web' {
            if ($ErrorText -match 'import.*error|No module named') {
                return "Only allowed imports: stdlib + pywebview + requests."
            }
        }
    }

    # Generic fallback: truncate and use the error directly
    $cleaned = $ErrorText -replace '\[[\w\.]+\]\s*', '' -replace 'line \d+:\s*', ''
    if ($cleaned.Length -gt 150) { $cleaned = $cleaned.Substring(0, 150) }
    return "Avoid: $cleaned"
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
    [CmdletBinding()]
    param()

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
    [CmdletBinding()]
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
    Force a specific framework: powershell (default), python-tk, python-web, tauri.

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

    .PARAMETER Theme
    UI color scheme: dark (default), light, or system (native OS colors).

    .PARAMETER IconPath
    Path to .ico file for the executable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [string]$Framework,
        [string]$Name,
        [int]$MaxTokens = 0,
        [string]$Provider,
        [string]$Model,
        [switch]$NoBranding,
        [ValidateSet('dark','light','system')][string]$Theme = 'system',
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
    $refineResult = Invoke-PromptRefinement -Prompt $Prompt -Framework $framework -Provider $Provider -Model $Model -Theme $Theme
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

    # Step 2b: Planning (for complex specs)
    $planResult = Invoke-BuildPlanning -Spec $refineResult.Spec -Framework $framework -Provider $Provider -Model $Model
    $generationSpec = $refineResult.Spec
    if ($planResult.Plan) {
        $generationSpec += "`n`nIMPLEMENTATION PLAN:`n$($planResult.Plan)"
    }

    # Step 2c: Complexity gate — estimate token need vs budget
    $codeMaxTokens = Get-BuildMaxTokens -Framework $framework -Model $resolvedModel -Override $MaxTokens
    $featureLines = @($generationSpec -split "`n" | Where-Object { $_ -match '^\s*-\s+' })
    $featureCount = $featureLines.Count
    # Heuristic: base 4000 tokens + ~1500 per feature for PowerShell, ~2000 for Tauri
    $tokensPerFeature = if ($framework -eq 'tauri') { 2000 } else { 1500 }
    $estimatedTokens = 4000 + ($featureCount * $tokensPerFeature)
    if ($estimatedTokens -gt ($codeMaxTokens * 0.8)) {
        Write-Host "[AppBuilder] WARNING: Estimated complexity (~$featureCount features, ~$estimatedTokens tokens) may exceed output budget ($codeMaxTokens tokens)." -ForegroundColor Yellow
        Write-Host "[AppBuilder] Consider simplifying the prompt or using a model with higher output limits." -ForegroundColor Yellow
    }

    # Step 3: Code generation
    $codeResult = Invoke-CodeGeneration -Spec $generationSpec -Framework $framework `
        -MaxTokens $codeMaxTokens -Provider $Provider -Model $Model -Theme $Theme
    if (-not $codeResult.Success) {
        Write-Host "[AppBuilder] FAILED: $($codeResult.Output)" -ForegroundColor Red
        Save-BuildRecord -Name $Name -Framework $framework -Prompt $Prompt -Status 'failed' `
            -Provider $Provider -Model $Model -ErrorMsg $codeResult.Output -BuildTime 0
        return $codeResult
    }

    Write-Host "[AppBuilder] Generated $($codeResult.Files.Count) file(s)" -ForegroundColor Cyan

    # Step 3b: Auto-repair common LLM syntax mistakes
    $repairCount = Repair-GeneratedCode -Files $codeResult.Files -Framework $framework
    if ($repairCount -gt 0) {
        Write-Host "[AppBuilder] Auto-repaired $repairCount syntax issue(s)" -ForegroundColor Yellow
    }

    # Step 4: Validate
    Write-Host "[AppBuilder] Validating code..." -ForegroundColor Cyan
    $validation = Test-GeneratedCode -Files $codeResult.Files -Framework $framework
    if (-not $validation.Success) {
        Write-Host "[AppBuilder] Validation found $($validation.Errors.Count) error(s). Entering fix loop..." -ForegroundColor Yellow
        foreach ($err in $validation.Errors) { Write-Host "  $err" -ForegroundColor Yellow }

        $fixResult = Invoke-BuildFixLoop -Spec $refineResult.Spec -Framework $framework `
            -Errors $validation.Errors -MaxTokens $codeMaxTokens `
            -Provider $Provider -Model $Model -Theme $Theme
        if (-not $fixResult.Success) {
            Save-BuildRecord -Name $Name -Framework $framework -Prompt $Prompt -Status 'failed' `
                -Provider $Provider -Model $Model -ErrorMsg ($fixResult.Errors -join '; ') -BuildTime 0
            return @{ Success = $false; Output = "Validation failed after fix loop"; Errors = $fixResult.Errors }
        }
        $codeResult = $fixResult
    }

    # Step 4b: Review Agent (spec alignment check)
    $reviewResult = Invoke-BuildReview -Files $codeResult.Files -Spec $refineResult.Spec -Framework $framework -Provider $Provider -Model $Model
    if (-not $reviewResult.Passed -and $reviewResult.Issues.Count -gt 0) {
        Write-Host "[AppBuilder] Review found $($reviewResult.Issues.Count) issue(s). Re-entering fix loop..." -ForegroundColor Yellow
        foreach ($issue in $reviewResult.Issues) { Write-Host "  $issue" -ForegroundColor Yellow }

        $reviewErrors = $reviewResult.Issues | ForEach-Object { "[Review] $_" }
        $fixResult = Invoke-BuildFixLoop -Spec $refineResult.Spec -Framework $framework `
            -Errors $reviewErrors -MaxTokens $codeMaxTokens `
            -Provider $Provider -Model $Model -Theme $Theme -MaxRetries 1
        if ($fixResult.Success) {
            $codeResult = $fixResult
        }
    }

    # Step 4c: Branding injection
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
    $buildResult = switch ($framework) {
        'powershell'        { Build-PowerShellExecutable -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir -IconPath $IconPath }
        'powershell-module' { Build-PowerShellModule -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir }
        'tauri'             { Build-TauriExecutable -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir -IconPath $IconPath }
        default             { Build-PythonExecutable -SourceDir $sourceDir -AppName $Name -Framework $framework -OutputDir $outputDir -IconPath $IconPath }
    }

    # Step 6b: Runtime smoke test for PowerShell builds
    if ($buildResult.Success -and $framework -eq 'powershell') {
        $smokeScript = Join-Path $sourceDir '_merged.ps1'
        if (-not (Test-Path $smokeScript)) { $smokeScript = Join-Path $sourceDir 'app.ps1' }
        if (Test-Path $smokeScript) {
            Write-Host "[AppBuilder] Running smoke test..." -ForegroundColor Cyan
            try {
                $smokeJob = Start-Job -ScriptBlock {
                    param($scriptPath)
                    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
                    try {
                        . $scriptPath
                    }
                    catch {
                        throw "SMOKE_FAIL: $($_.Exception.Message)"
                    }
                } -ArgumentList $smokeScript
                $null = $smokeJob | Wait-Job -Timeout 10
                if ($smokeJob.State -eq 'Failed') {
                    $smokeErr = $smokeJob | Receive-Job -ErrorAction SilentlyContinue 2>&1 | Out-String
                    Write-Host "[AppBuilder] Smoke test FAILED: $smokeErr" -ForegroundColor Yellow
                    # Non-fatal: report but don't block the build
                    Write-Host "[AppBuilder] Build completed but runtime errors detected. The app may crash on launch." -ForegroundColor Yellow
                }
                elseif ($smokeJob.State -eq 'Running') {
                    # Still running after 10s = likely the form loaded successfully
                    Write-Host "[AppBuilder] Smoke test passed (form loaded)" -ForegroundColor Green
                }
                else {
                    # Completed quickly — check for errors in output
                    $smokeOutput = $smokeJob | Receive-Job -ErrorAction SilentlyContinue 2>&1 | Out-String
                    if ($smokeOutput -match 'SMOKE_FAIL') {
                        Write-Host "[AppBuilder] Smoke test detected runtime error: $smokeOutput" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "[AppBuilder] Smoke test passed" -ForegroundColor Green
                    }
                }
                $smokeJob | Stop-Job -ErrorAction SilentlyContinue
                $smokeJob | Remove-Job -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Host "[AppBuilder] Smoke test skipped (non-fatal): $($_.Exception.Message)" -ForegroundColor DarkGray
            }
        }
    }

    $totalElapsed = [math]::Round(((Get-Date) - $totalStart).TotalSeconds, 1)

    if ($buildResult.Success) {
        Write-Host "`n[AppBuilder] SUCCESS: $($buildResult.Output)" -ForegroundColor Green
        $outputLabel = if ($framework -eq 'powershell-module') { 'Module:' } else { 'Executable:' }
        Write-Host "  $($outputLabel) $($buildResult.ExePath)" -ForegroundColor White
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Changes,
        [string]$Provider,
        [string]$Model,
        [ValidateSet('dark','light','system')][string]$Theme = 'system'
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
    $framework = if ($files.Keys | Where-Object { $_ -match '\.psm1$' }) { 'powershell-module' }
                 elseif ($files.ContainsKey('app.ps1')) { 'powershell' }
                 elseif ($files.ContainsKey('src-tauri/src/main.rs') -or $files.ContainsKey('src-tauri/Cargo.toml')) { 'tauri' }
                 elseif ($files.ContainsKey('web/index.html')) { 'python-web' }
                 else { 'python-tk' }

    # Check if user wants full regeneration
    $fullRegenTriggers = @('rewrite', 'redesign', 'from scratch', 'start over', 'completely new')
    $needsFullRegen = $fullRegenTriggers | Where-Object { $Changes -match $_ }

    # Tauri capability changes require full regen (capabilities affect Cargo.toml, permissions, Rust code)
    if ($framework -eq 'tauri' -and -not $needsFullRegen) {
        $capabilityTriggers = @('clipboard', 'notification', 'http\s*(client|request|api)', 'file\s*system', 'fs\s*access', 'dialog', 'shell', 'global\s*shortcut', 'system\s*tray', 'updater')
        $needsFullRegen = $capabilityTriggers | Where-Object { $Changes -match $_ }
        if ($needsFullRegen) {
            Write-Host "[AppBuilder] Tauri capability change detected — full regeneration required." -ForegroundColor Yellow
        }
    }

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
        return New-AppBuild -Prompt $originalPrompt -Framework $framework -Name $Name -Provider $Provider -Model $Model -Theme $Theme
    }

    # Diff-based modification
    Write-Host "[AppBuilder] Applying modifications to '$Name'..." -ForegroundColor Cyan

    $sourceContext = ($files.Keys | ForEach-Object {
        "--- $_ ---`n$($files[$_])`n"
    }) -join "`n"

    $messages = @(
        @{ role = 'user'; content = "Here is the current source code:`n`n$sourceContext`n`nUser's change request: $Changes" }
    )

    # Framework-aware system prompt for modifications
    $modifyPrompt = $script:BuilderModifyPrompt
    if ($framework -eq 'tauri') {
        $modifyPrompt += "`n`nTAURI CONTEXT: This is a Tauri v2 app with Rust backend (src-tauri/src/main.rs) and HTML/CSS/JS frontend (web/). Rust changes go in .rs files, UI changes in .html/.css/.js files. Tauri commands use #[tauri::command] in Rust and window.__TAURI__.invoke() in JS. If the change requires new Tauri capabilities or permissions, respond with FULL_REGENERATION_NEEDED."
    }

    $params = @{
        Messages     = $messages
        SystemPrompt = $modifyPrompt
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
            return Update-AppBuild -Name $Name -Changes "rewrite: $Changes" -Provider $Provider -Model $Model -Theme $Theme
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

        # Auto-repair
        $repairCount = Repair-GeneratedCode -Files $files -Framework $framework
        if ($repairCount -gt 0) {
            Write-Host "[AppBuilder] Auto-repaired $repairCount syntax issue(s)" -ForegroundColor Yellow
            foreach ($fn in $files.Keys) {
                $filePath = Join-Path $sourceDir $fn
                $files[$fn] | Set-Content $filePath -Encoding UTF8
            }
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
        $buildResult = switch ($framework) {
            'powershell'        { Build-PowerShellExecutable -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir }
            'powershell-module' { Build-PowerShellModule -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir }
            'tauri'             { Build-TauriExecutable -SourceDir $sourceDir -AppName $Name -OutputDir $outputDir }
            default             { Build-PythonExecutable -SourceDir $sourceDir -AppName $Name -Framework $framework -OutputDir $outputDir }
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
    @('powershell', 'powershell-module', 'python-tk', 'python-web', 'tauri') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Framework: $_")
    }
}

$_themeCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    @('dark', 'light', 'system') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Theme: $_")
    }
}
Register-ArgumentCompleter -CommandName New-AppBuild   -ParameterName Theme -ScriptBlock $_themeCompleter
Register-ArgumentCompleter -CommandName Update-AppBuild -ParameterName Theme -ScriptBlock $_themeCompleter

# ===== Aliases =====
Set-Alias builds Get-AppBuilds -Force
Set-Alias rebuild Update-AppBuild -Force

Write-Verbose "AppBuilder loaded: New-AppBuild, Update-AppBuild, Get-AppBuilds, Remove-AppBuild"
