# ===== VisionTools.ps1 =====
# Vision model support: screenshot capture, image loading, base64 encoding,
# and multimodal message construction for Claude, GPT-4o, and Ollama vision models.
# Uses System.Drawing + System.Windows.Forms for screen capture (Windows).

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# ===== Vision-Capable Models =====
$global:VisionModels = @(
    # Anthropic
    'claude-sonnet-4-5-20250929'
    'claude-3-5-sonnet-20241022'
    'claude-3-5-haiku-20241022'
    'claude-3-opus-20240229'
    # OpenAI
    'gpt-4o'
    'gpt-4o-mini'
    'gpt-4-turbo'
    'o1'
    # Ollama vision models
    'llava'
    'llava:13b'
    'llava:34b'
    'llama3.2-vision'
    'llama3.2-vision:11b'
    'llama3.2-vision:90b'
    'moondream'
    'bakllava'
)

# Default resize threshold (longest edge in pixels). Use --full to skip.
$global:VisionMaxEdge = 2048

# ===== Core Functions =====

function Test-VisionSupport {
    <#
    .SYNOPSIS
    Check if the current or specified provider/model supports vision input.
    #>
    param(
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model
    )

    if (-not $Model) {
        $config = $global:ChatProviders[$Provider]
        if ($config) { $Model = $config.DefaultModel }
    }
    if (-not $Model) { return $false }

    # Exact match
    if ($Model -in $global:VisionModels) { return $true }

    # Partial match (model tags like llava:7b-v1.6)
    foreach ($vm in $global:VisionModels) {
        if ($Model -like "$vm*" -or $Model -like "*$vm*") { return $true }
    }

    return $false
}

function Capture-Screenshot {
    <#
    .SYNOPSIS
    Capture the primary screen to a temporary PNG file.

    .PARAMETER Region
    Optional hashtable @{ X; Y; Width; Height } for partial capture.

    .PARAMETER FullResolution
    Skip auto-resize. Use when detail matters (dense text, spreadsheets).
    #>
    param(
        [hashtable]$Region,
        [switch]$FullResolution
    )

    try {
        if ($Region) {
            $bounds = New-Object System.Drawing.Rectangle($Region.X, $Region.Y, $Region.Width, $Region.Height)
        }
        else {
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen
            $bounds = $screen.Bounds
        }

        $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $graphics.Dispose()

        # Auto-resize unless full resolution requested
        if (-not $FullResolution) {
            $bitmap = Resize-ImageBitmap -Bitmap $bitmap -MaxEdge $global:VisionMaxEdge
        }

        $tempPath = Join-Path $env:TEMP "bildsyps_screenshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
        $bitmap.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()

        return @{
            Success = $true
            Path    = $tempPath
            Width   = $bounds.Width
            Height  = $bounds.Height
        }
    }
    catch {
        if ($bitmap) { $bitmap.Dispose() }
        return @{
            Success = $false
            Output  = "Screenshot failed: $($_.Exception.Message)"
        }
    }
}

function Get-ClipboardImage {
    <#
    .SYNOPSIS
    Get an image from the clipboard if one exists. Saves to temp PNG.
    #>
    param([switch]$FullResolution)

    try {
        if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
            return @{ Success = $false; Output = 'No image on clipboard' }
        }

        $image = [System.Windows.Forms.Clipboard]::GetImage()
        if (-not $image) {
            return @{ Success = $false; Output = 'Failed to read clipboard image' }
        }

        $bitmap = New-Object System.Drawing.Bitmap($image)
        $image.Dispose()

        if (-not $FullResolution) {
            $bitmap = Resize-ImageBitmap -Bitmap $bitmap -MaxEdge $global:VisionMaxEdge
        }

        $tempPath = Join-Path $env:TEMP "bildsyps_clipboard_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
        $bitmap.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()

        return @{
            Success = $true
            Path    = $tempPath
        }
    }
    catch {
        return @{
            Success = $false
            Output  = "Clipboard image error: $($_.Exception.Message)"
        }
    }
}

function Resize-ImageBitmap {
    <#
    .SYNOPSIS
    Resize a System.Drawing.Bitmap so its longest edge is at most MaxEdge pixels.
    Returns the original bitmap if already within bounds.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap,
        [int]$MaxEdge = 2048
    )

    $longest = [math]::Max($Bitmap.Width, $Bitmap.Height)
    if ($longest -le $MaxEdge) { return $Bitmap }

    $scale = $MaxEdge / $longest
    $newW = [int]([math]::Round($Bitmap.Width * $scale))
    $newH = [int]([math]::Round($Bitmap.Height * $scale))

    $resized = New-Object System.Drawing.Bitmap($newW, $newH)
    $g = [System.Drawing.Graphics]::FromImage($resized)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($Bitmap, 0, 0, $newW, $newH)
    $g.Dispose()
    $Bitmap.Dispose()

    return $resized
}

function ConvertTo-ImageBase64 {
    <#
    .SYNOPSIS
    Read an image file and return its base64 encoding and media type.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$FullResolution
    )

    if (-not (Test-Path $Path)) {
        return @{ Success = $false; Output = "File not found: $Path" }
    }

    # Validate extension
    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    $mediaTypes = @{
        '.png'  = 'image/png'
        '.jpg'  = 'image/jpeg'
        '.jpeg' = 'image/jpeg'
        '.gif'  = 'image/gif'
        '.webp' = 'image/webp'
        '.bmp'  = 'image/bmp'
    }

    if (-not $mediaTypes.ContainsKey($ext)) {
        return @{ Success = $false; Output = "Unsupported image format: $ext. Use png, jpg, gif, webp, or bmp." }
    }

    # Size check (20MB limit for API calls)
    $fileSize = (Get-Item $Path).Length
    if ($fileSize -gt 20MB) {
        return @{ Success = $false; Output = "Image too large ($([math]::Round($fileSize / 1MB, 1))MB). Max 20MB." }
    }

    try {
        # Resize if needed
        if (-not $FullResolution) {
            $bitmap = New-Object System.Drawing.Bitmap($Path)
            $longest = [math]::Max($bitmap.Width, $bitmap.Height)
            if ($longest -gt $global:VisionMaxEdge) {
                $bitmap = Resize-ImageBitmap -Bitmap $bitmap -MaxEdge $global:VisionMaxEdge
                $resizedPath = Join-Path $env:TEMP "bildsyps_resized_$(Get-Date -Format 'yyyyMMdd_HHmmss')$ext"
                $bitmap.Save($resizedPath)
                $bitmap.Dispose()
                $bytes = [System.IO.File]::ReadAllBytes($resizedPath)
                Remove-Item $resizedPath -Force -ErrorAction SilentlyContinue
            }
            else {
                $bitmap.Dispose()
                $bytes = [System.IO.File]::ReadAllBytes($Path)
            }
        }
        else {
            $bytes = [System.IO.File]::ReadAllBytes($Path)
        }

        $base64 = [Convert]::ToBase64String($bytes)

        return @{
            Success   = $true
            Base64    = $base64
            MediaType = $mediaTypes[$ext]
            SizeKB    = [math]::Round($bytes.Length / 1KB, 1)
        }
    }
    catch {
        return @{ Success = $false; Output = "Failed to encode image: $($_.Exception.Message)" }
    }
}

function New-VisionMessage {
    <#
    .SYNOPSIS
    Build a multimodal message content array suitable for the target provider.
    Returns a content array to use as the 'content' field of a user message.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base64,
        [Parameter(Mandatory = $true)]
        [string]$MediaType,
        [string]$Prompt = 'Describe what you see in this image.',
        [string]$Format = 'openai'  # 'openai' or 'anthropic'
    )

    if ($Format -eq 'anthropic') {
        return @(
            @{
                type   = 'image'
                source = @{
                    type       = 'base64'
                    media_type = $MediaType
                    data       = $Base64
                }
            }
            @{
                type = 'text'
                text = $Prompt
            }
        )
    }
    else {
        # OpenAI / OpenAI-compatible (Ollama)
        $dataUri = "data:${MediaType};base64,${Base64}"
        return @(
            @{
                type      = 'image_url'
                image_url = @{
                    url = $dataUri
                }
            }
            @{
                type = 'text'
                text = $Prompt
            }
        )
    }
}

function Send-ImageToAI {
    <#
    .SYNOPSIS
    Send an image to a vision-capable LLM and return the description.

    .PARAMETER ImagePath
    Path to image file (png, jpg, gif, webp, bmp).

    .PARAMETER Prompt
    What to ask about the image.

    .PARAMETER Provider
    LLM provider. Must support vision.

    .PARAMETER Model
    Model override. Must support vision.

    .PARAMETER FullResolution
    Skip auto-resize (for dense text, spreadsheets, terminal screenshots).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,
        [string]$Prompt = 'Describe what you see in this image in detail.',
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model,
        [switch]$FullResolution
    )

    # Resolve model
    $config = $global:ChatProviders[$Provider]
    if (-not $config) {
        return @{ Success = $false; Output = "Unknown provider: $Provider" }
    }
    if (-not $Model) { $Model = $config.DefaultModel }

    # Check vision support
    if (-not (Test-VisionSupport -Provider $Provider -Model $Model)) {
        $suggestedModels = switch ($Provider) {
            'anthropic' { 'claude-sonnet-4-5-20250929, claude-3-5-sonnet-20241022' }
            'openai'    { 'gpt-4o, gpt-4o-mini' }
            'ollama'    { 'llava, llama3.2-vision' }
            default     { 'gpt-4o (openai), claude-sonnet-4-5-20250929 (anthropic), llava (ollama)' }
        }
        return @{
            Success = $false
            Output  = "Model '$Model' does not support vision. Try: $suggestedModels"
        }
    }

    # Encode image
    $encoded = ConvertTo-ImageBase64 -Path $ImagePath -FullResolution:$FullResolution
    if (-not $encoded.Success) {
        return $encoded
    }

    Write-Host "  [Vision] Sending image (${($encoded.SizeKB)}KB base64) to $Model..." -ForegroundColor DarkCyan

    # Build multimodal message
    $providerFormat = $config.Format
    if ($providerFormat -eq 'llm-cli') {
        return @{ Success = $false; Output = 'Vision is not supported via the llm CLI wrapper. Use a direct API provider.' }
    }

    $contentArray = New-VisionMessage -Base64 $encoded.Base64 -MediaType $encoded.MediaType -Prompt $Prompt -Format $providerFormat

    $messages = @(
        @{ role = 'user'; content = $contentArray }
    )

    try {
        $response = Invoke-ChatCompletion -Messages $messages -Provider $Provider -Model $Model -MaxTokens 4096 -SystemPrompt 'You are a helpful assistant with vision capabilities. Describe images accurately and in detail.'
        return @{
            Success     = $true
            Output      = $response.Content
            Model       = $Model
            Provider    = $Provider
            ImageSizeKB = $encoded.SizeKB
        }
    }
    catch {
        return @{ Success = $false; Output = "Vision API error: $($_.Exception.Message)" }
    }
}

# ===== Convenience Wrappers =====

function Invoke-Vision {
    <#
    .SYNOPSIS
    Quick vision command: capture screenshot or analyze an image file.

    .EXAMPLE
    vision                          # Screenshot + describe
    vision C:\photo.jpg             # Analyze specific file
    vision --full                   # Screenshot at full resolution
    vision C:\photo.jpg "what breed is this dog?"  # Custom prompt
    #>
    param(
        [string]$PathOrFlag,
        [string]$Prompt,
        [switch]$Full,
        [string]$Provider = $global:DefaultChatProvider,
        [string]$Model
    )

    # Handle --full flag passed as positional arg
    if ($PathOrFlag -eq '--full') {
        $Full = $true
        $PathOrFlag = $null
    }

    if ($PathOrFlag -and (Test-Path $PathOrFlag)) {
        # Analyze an image file
        if (-not $Prompt) { $Prompt = 'Describe what you see in this image in detail.' }

        # Security: validate path
        if (Get-Command Test-PathAllowed -ErrorAction SilentlyContinue) {
            $validation = Test-PathAllowed -Path $PathOrFlag
            if (-not $validation.Success) {
                Write-Host "Security: $($validation.Message)" -ForegroundColor Red
                return
            }
            $PathOrFlag = $validation.Path
        }

        Write-Host "[Vision] Analyzing: $PathOrFlag" -ForegroundColor Cyan
        $result = Send-ImageToAI -ImagePath $PathOrFlag -Prompt $Prompt -Provider $Provider -Model $Model -FullResolution:$Full
    }
    else {
        # Capture screenshot
        if ($PathOrFlag -and -not (Test-Path $PathOrFlag)) {
            # Treat as prompt if it's not a valid path
            $Prompt = $PathOrFlag
        }
        if (-not $Prompt) { $Prompt = 'Describe what you see on this screen. Note any open applications, windows, and content visible.' }

        Write-Host '[Vision] Capturing screenshot...' -ForegroundColor Cyan
        $capture = Capture-Screenshot -FullResolution:$Full
        if (-not $capture.Success) {
            Write-Host "  $($capture.Output)" -ForegroundColor Red
            return
        }

        Write-Host "  Captured $($capture.Width)x$($capture.Height)" -ForegroundColor DarkGray
        $result = Send-ImageToAI -ImagePath $capture.Path -Prompt $Prompt -Provider $Provider -Model $Model -FullResolution:$Full

        # Clean up temp file
        Remove-Item $capture.Path -Force -ErrorAction SilentlyContinue
    }

    if ($result.Success) {
        Write-Host "`nAI>" -ForegroundColor Cyan
        if (Get-Command Format-Markdown -ErrorAction SilentlyContinue) {
            Format-Markdown $result.Output
        }
        else {
            Write-Host $result.Output -ForegroundColor White
        }
    }
    else {
        Write-Host "  $($result.Output)" -ForegroundColor Red
    }

    return $result
}

# ===== Aliases =====
Set-Alias vision Invoke-Vision -Force

Write-Verbose 'VisionTools loaded: Capture-Screenshot, Send-ImageToAI, Invoke-Vision, Test-VisionSupport'
