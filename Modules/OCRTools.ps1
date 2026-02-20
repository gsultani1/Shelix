# ===== OCRTools.ps1 =====
# OCR integration using Tesseract OCR and pdftotext (Poppler).
# Provides local text extraction from images and PDFs as a fallback
# when vision-capable LLM APIs are unavailable.

# ===== Dependency Checks =====

function Test-OCRAvailable {
    <#
    .SYNOPSIS
    Check if Tesseract OCR is installed and on PATH. Returns status hashtable.
    #>
    $tesseract = Get-Command tesseract -ErrorAction SilentlyContinue
    if ($tesseract) {
        try {
            $ver = & tesseract --version 2>&1 | Select-Object -First 1
            return @{ Available = $true; Version = "$ver"; Path = $tesseract.Source }
        }
        catch {
            return @{ Available = $true; Version = 'unknown'; Path = $tesseract.Source }
        }
    }
    return @{
        Available = $false
        Version   = $null
        Path      = $null
        Install   = 'Install Tesseract: winget install UB-Mannheim.TesseractOCR  or  choco install tesseract'
    }
}

function Test-PdftotextAvailable {
    <#
    .SYNOPSIS
    Check if pdftotext (Poppler) is installed and on PATH.
    #>
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($pdftotext) {
        return @{ Available = $true; Path = $pdftotext.Source }
    }
    return @{
        Available = $false
        Path      = $null
        Install   = 'Install Poppler: winget install poppler  or  choco install poppler'
    }
}

# ===== OCR Functions =====

function Invoke-OCR {
    <#
    .SYNOPSIS
    Run Tesseract OCR on an image file and return extracted text.

    .PARAMETER ImagePath
    Path to the image file (png, jpg, tiff, bmp, gif, webp).

    .PARAMETER Language
    Tesseract language code (default: eng). Use 'tesseract --list-langs' to see available.

    .PARAMETER PSM
    Page segmentation mode (default: 3 = fully automatic).
    Common values: 1=auto+OSD, 3=fully auto, 6=single block, 7=single line, 8=single word.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        [string]$Language = 'eng',
        [int]$PSM = 3
    )

    # Validate Tesseract
    $check = Test-OCRAvailable
    if (-not $check.Available) {
        return @{ Success = $false; Output = "Tesseract not found. $($check.Install)" }
    }

    # Validate file
    if (-not (Test-Path $ImagePath)) {
        return @{ Success = $false; Output = "File not found: $ImagePath" }
    }

    $resolvedPath = (Resolve-Path $ImagePath).Path
    $outputBase = Join-Path $env:TEMP "bildsyps_ocr_$(Get-Random)"

    try {
        $tessArgs = @($resolvedPath, $outputBase, '-l', $Language, '--psm', $PSM)
        Start-Process tesseract -ArgumentList $tessArgs -Wait -NoNewWindow -RedirectStandardError "$outputBase.err" 2>$null
        
        $outputFile = "$outputBase.txt"
        if (Test-Path $outputFile) {
            $text = Get-Content $outputFile -Raw -Encoding UTF8
            $text = $text.Trim()
            
            # Cleanup
            Remove-Item "$outputBase*" -Force -ErrorAction SilentlyContinue
            
            if ($text.Length -eq 0) {
                return @{ Success = $true; Output = '(no text detected in image)'; CharCount = 0 }
            }
            return @{ Success = $true; Output = $text; CharCount = $text.Length }
        }
        else {
            $errMsg = if (Test-Path "$outputBase.err") { Get-Content "$outputBase.err" -Raw } else { 'Unknown error' }
            Remove-Item "$outputBase*" -Force -ErrorAction SilentlyContinue
            return @{ Success = $false; Output = "Tesseract failed: $errMsg" }
        }
    }
    catch {
        Remove-Item "$outputBase*" -Force -ErrorAction SilentlyContinue
        return @{ Success = $false; Output = "OCR error: $($_.Exception.Message)" }
    }
}

function ConvertFrom-PDF {
    <#
    .SYNOPSIS
    Extract text from a PDF. Tries pdftotext first (fast, for text-based PDFs).
    If output is empty or mostly garbage, falls back to Tesseract page-by-page OCR.

    .PARAMETER PdfPath
    Path to the PDF file.

    .PARAMETER Language
    Tesseract language code for OCR fallback (default: eng).

    .PARAMETER Pages
    Page range for pdftotext (e.g. '1-5'). Default: all pages.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PdfPath,
        [string]$Language = 'eng',
        [string]$Pages
    )

    if (-not (Test-Path $PdfPath)) {
        return @{ Success = $false; Output = "File not found: $PdfPath" }
    }

    $resolvedPath = (Resolve-Path $PdfPath).Path

    # Strategy 1: pdftotext (fast, works for text-based PDFs)
    $pdftotextCheck = Test-PdftotextAvailable
    if ($pdftotextCheck.Available) {
        try {
            $outputFile = Join-Path $env:TEMP "bildsyps_pdf_$(Get-Random).txt"
            $pdfArgs = @('-layout')
            if ($Pages) {
                $parts = $Pages -split '-'
                if ($parts.Count -eq 2) {
                    $pdfArgs += @('-f', $parts[0], '-l', $parts[1])
                }
            }
            $pdfArgs += @($resolvedPath, $outputFile)
            
            Start-Process pdftotext -ArgumentList $pdfArgs -Wait -NoNewWindow 2>$null
            
            if (Test-Path $outputFile) {
                $text = Get-Content $outputFile -Raw -Encoding UTF8
                Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
                
                # Check if we got meaningful text (not just whitespace/garbage)
                $alphaCount = ($text -replace '[^a-zA-Z]', '').Length
                if ($text.Trim().Length -gt 10 -and $alphaCount -gt ($text.Length * 0.3)) {
                    return @{ Success = $true; Output = $text.Trim(); Method = 'pdftotext'; CharCount = $text.Trim().Length }
                }
                # Fall through to OCR if text looks like garbage
            }
        }
        catch {
            # Fall through to OCR
        }
    }

    # Strategy 2: Tesseract OCR (for scanned PDFs)
    $ocrCheck = Test-OCRAvailable
    if (-not $ocrCheck.Available) {
        $msg = "PDF appears to be scanned/image-based. "
        if (-not $pdftotextCheck.Available) { $msg += "$($pdftotextCheck.Install) " }
        $msg += "$($ocrCheck.Install)"
        return @{ Success = $false; Output = $msg }
    }

    # Convert PDF pages to images using Tesseract's built-in PDF support
    # Tesseract 4+ can read PDFs directly if built with pdf support
    try {
        $result = Invoke-OCR -ImagePath $resolvedPath -Language $Language
        if ($result.Success -and $result.CharCount -gt 0) {
            $result.Method = 'tesseract-ocr'
            return $result
        }
    }
    catch {
        # Tesseract may not support PDF directly on all builds
    }

    return @{ Success = $false; Output = "Could not extract text from PDF. The file may be encrypted or in an unsupported format." }
}

function Send-ImageToAIWithFallback {
    <#
    .SYNOPSIS
    Try vision API first. If the current model doesn't support vision, fall back to
    Tesseract OCR + send extracted text as a regular prompt.

    .PARAMETER ImagePath
    Path to the image file.

    .PARAMETER Prompt
    What to ask about the image.

    .PARAMETER Provider
    Chat provider override.

    .PARAMETER Model
    Model override.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,
        [string]$Prompt = 'Describe what you see in this image in detail.',
        [string]$Provider,
        [string]$Model,
        [switch]$FullResolution
    )

    # Try vision API first
    if (Get-Command Send-ImageToAI -ErrorAction SilentlyContinue) {
        $visionSupported = $true
        if (Get-Command Test-VisionSupport -ErrorAction SilentlyContinue) {
            $testModel = if ($Model) { $Model } else { $null }
            $visionSupported = Test-VisionSupport -Model $testModel
        }
        if ($visionSupported) {
            $params = @{ ImagePath = $ImagePath; Prompt = $Prompt }
            if ($Provider) { $params.Provider = $Provider }
            if ($Model) { $params.Model = $Model }
            if ($FullResolution) { $params.FullResolution = $true }
            $result = Send-ImageToAI @params
            if ($result.Success) {
                $result.Method = 'vision-api'
                return $result
            }
        }
    }

    # Fallback to OCR
    $ocrCheck = Test-OCRAvailable
    if (-not $ocrCheck.Available) {
        return @{
            Success = $false
            Output  = "Vision model not available for current provider/model, and Tesseract OCR is not installed. $($ocrCheck.Install)"
        }
    }

    Write-Host '[OCR] Vision not available for this model. Using Tesseract OCR fallback...' -ForegroundColor DarkYellow
    $ocrResult = Invoke-OCR -ImagePath $ImagePath
    if (-not $ocrResult.Success) {
        return $ocrResult
    }

    # Send extracted text to the LLM as a regular prompt
    $contextPrompt = "The following text was extracted from an image using OCR. The user asks: $Prompt`n`n--- OCR Text ---`n$($ocrResult.Output)`n--- End OCR ---"
    
    if (Get-Command Invoke-ChatCompletion -ErrorAction SilentlyContinue) {
        $messages = @(
            @{ role = 'user'; content = $contextPrompt }
        )
        $chatParams = @{ Messages = $messages }
        if ($Provider) { $chatParams.Provider = $Provider }
        if ($Model) { $chatParams.Model = $Model }
        
        try {
            $response = Invoke-ChatCompletion @chatParams
            return @{ Success = $true; Output = $response; Method = 'ocr-fallback'; OCRChars = $ocrResult.CharCount }
        }
        catch {
            return @{ Success = $false; Output = "OCR succeeded but LLM call failed: $($_.Exception.Message)" }
        }
    }

    # No LLM available -- just return the OCR text
    return @{ Success = $true; Output = $ocrResult.Output; Method = 'ocr-only'; OCRChars = $ocrResult.CharCount }
}

# ===== Convenience Wrapper =====

function Invoke-OCRFile {
    <#
    .SYNOPSIS
    OCR a file (image or PDF) and display the extracted text.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Language = 'eng'
    )

    if (-not (Test-Path $Path)) {
        Write-Host "File not found: $Path" -ForegroundColor Red
        return
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    
    if ($ext -eq '.pdf') {
        Write-Host "[OCR] Processing PDF: $Path" -ForegroundColor Cyan
        $result = ConvertFrom-PDF -PdfPath $Path -Language $Language
    }
    else {
        Write-Host "[OCR] Processing image: $Path" -ForegroundColor Cyan
        $result = Invoke-OCR -ImagePath $Path -Language $Language
    }

    if ($result.Success) {
        $method = if ($result.Method) { " ($($result.Method))" } else { '' }
        Write-Host "[OCR] Extracted $($result.CharCount) characters$method" -ForegroundColor Green
        Write-Host ""
        Write-Host $result.Output
        Write-Host ""
    }
    else {
        Write-Host "[OCR] $($result.Output)" -ForegroundColor Red
    }

    return $result
}

# ===== Aliases =====
Set-Alias ocr Invoke-OCRFile -Force

Write-Verbose "OCRTools loaded: Invoke-OCR, ConvertFrom-PDF, Send-ImageToAIWithFallback, Invoke-OCRFile (ocr)"
