# ===== DocumentTools.ps1 =====
# OpenXML document creation without COM dependencies (cross-platform)

function New-MinimalDocx {
    <#
    .SYNOPSIS
    Creates a valid Word document (.docx) using OpenXML format
    
    .PARAMETER Path
    Full path for the new document
    
    .PARAMETER Content
    Optional initial text content
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Content = ""
    )
    
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    if (Test-Path $Path) { Remove-Item $Path -Force }
    
    $zip = [System.IO.Compression.ZipFile]::Open($Path, 'Create')
    
    try {
        # [Content_Types].xml
        $contentTypesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
'@
        $entry = $zip.CreateEntry('[Content_Types].xml')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($contentTypesXml)
        $writer.Dispose()
        
        # _rels/.rels
        $relsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
'@
        $entry = $zip.CreateEntry('_rels/.rels')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($relsXml)
        $writer.Dispose()
        
        # word/document.xml
        $escapedContent = [System.Security.SecurityElement]::Escape($Content)
        $documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:t>$escapedContent</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>
"@
        $entry = $zip.CreateEntry('word/document.xml')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($documentXml)
        $writer.Dispose()
    }
    finally {
        $zip.Dispose()
    }
    
    return $Path
}

function New-MinimalXlsx {
    <#
    .SYNOPSIS
    Creates a valid Excel spreadsheet (.xlsx) using OpenXML format
    
    .PARAMETER Path
    Full path for the new spreadsheet
    
    .PARAMETER SheetName
    Name for the first sheet (default: Sheet1)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$SheetName = "Sheet1"
    )
    
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    if (Test-Path $Path) { Remove-Item $Path -Force }
    
    $zip = [System.IO.Compression.ZipFile]::Open($Path, 'Create')
    
    try {
        # [Content_Types].xml
        $contentTypesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
'@
        $entry = $zip.CreateEntry('[Content_Types].xml')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($contentTypesXml)
        $writer.Dispose()
        
        # _rels/.rels
        $relsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'@
        $entry = $zip.CreateEntry('_rels/.rels')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($relsXml)
        $writer.Dispose()
        
        # xl/workbook.xml
        $workbookXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="$SheetName" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
"@
        $entry = $zip.CreateEntry('xl/workbook.xml')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($workbookXml)
        $writer.Dispose()
        
        # xl/_rels/workbook.xml.rels
        $wbRelsXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
'@
        $entry = $zip.CreateEntry('xl/_rels/workbook.xml.rels')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($wbRelsXml)
        $writer.Dispose()
        
        # xl/worksheets/sheet1.xml
        $sheetXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData/>
</worksheet>
'@
        $entry = $zip.CreateEntry('xl/worksheets/sheet1.xml')
        $writer = [System.IO.StreamWriter]::new($entry.Open())
        $writer.Write($sheetXml)
        $writer.Dispose()
    }
    finally {
        $zip.Dispose()
    }
    
    return $Path
}

Write-Verbose "DocumentTools loaded: New-MinimalDocx, New-MinimalXlsx"
