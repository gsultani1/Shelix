# ===== NavigationUtils.ps1 =====
# Navigation shortcuts, directory utilities, and git shortcuts

# ===== Directory Navigation =====
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }
function ~ { Set-Location $env:USERPROFILE }
function docs { Set-Location "$env:USERPROFILE\Documents" }
function desktop { Set-Location "$env:USERPROFILE\Desktop" }
function downloads { Set-Location "$env:USERPROFILE\Downloads" }
function projects { 
    $projectsPath = "$env:USERPROFILE\Projects"
    if (-not (Test-Path $projectsPath)) {
        $projectsPath = "$env:USERPROFILE\Documents\Projects"
    }
    if (Test-Path $projectsPath) {
        Set-Location $projectsPath
    } else {
        Write-Host "Projects folder not found" -ForegroundColor Yellow
    }
}

# ===== Directory Listing =====
function ll { Get-ChildItem -Force @args | Format-Table -AutoSize }
function la { Get-ChildItem -Force -Hidden @args }
function lsd { Get-ChildItem -Directory @args }
function lsf { Get-ChildItem -File @args }

function tree {
    param(
        [string]$Path = ".",
        [int]$Depth = 2
    )
    
    function Show-Tree {
        param($Dir, $Prefix = "", $CurrentDepth = 0, $MaxDepth)
        
        if ($CurrentDepth -ge $MaxDepth) { return }
        
        $items = Get-ChildItem $Dir -ErrorAction SilentlyContinue
        $count = $items.Count
        $i = 0
        
        foreach ($item in $items) {
            $i++
            $isLast = ($i -eq $count)
            $connector = if ($isLast) { "+-- " } else { "|-- " }
            $newPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix|   " }
            
            $color = if ($item.PSIsContainer) { "Cyan" } else { "White" }
            Write-Host "$Prefix$connector" -NoNewline -ForegroundColor DarkGray
            Write-Host $item.Name -ForegroundColor $color
            
            if ($item.PSIsContainer) {
                Show-Tree -Dir $item.FullName -Prefix $newPrefix -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
            }
        }
    }
    
    Write-Host $Path -ForegroundColor Yellow
    Show-Tree -Dir $Path -MaxDepth $Depth
}

# ===== File Operations =====
function touch {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Path $Path | Out-Null
    }
}

function mkcd {
    param([Parameter(Mandatory=$true)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

function which {
    param([Parameter(Mandatory=$true)][string]$Command)
    Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

function size {
    param([string]$Path = ".")
    $items = Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue
    $fileCount = @($items | Where-Object { -not $_.PSIsContainer }).Count
    $dirCount = @($items | Where-Object { $_.PSIsContainer }).Count
    $size = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    
    if ($null -eq $size) { $size = 0 }
    
    $units = @("B", "KB", "MB", "GB", "TB")
    $unitIndex = 0
    while ($size -ge 1024 -and $unitIndex -lt $units.Count - 1) {
        $size /= 1024
        $unitIndex++
    }
    
    $sizeStr = "$([math]::Round($size, 2)) $($units[$unitIndex])"
    Write-Host "$sizeStr ($fileCount files, $dirCount folders)" -ForegroundColor Cyan
}

# ===== Git Shortcuts =====
function gs { git status @args }
function ga { git add @args }
function gaa { git add -A }
function gc { 
    param([Parameter(Mandatory=$true)][string]$Message)
    git commit -m $Message 
}
function gca { git commit --amend @args }
function gp { git push @args }
function gpl { git pull @args }
function gl { git log --oneline -n 15 @args }
function glg { git log --graph --oneline --all -n 20 }
function gb { git branch @args }
function gba { git branch -a }
function gco { 
    param([Parameter(Mandatory=$true)][string]$Branch)
    git checkout $Branch 
}
function gcob { 
    param([Parameter(Mandatory=$true)][string]$Branch)
    git checkout -b $Branch 
}
function gd { git diff @args }
function gds { git diff --staged @args }
function gst { git stash @args }
function gstp { git stash pop }
function gf { git fetch @args }
function gm { 
    param([Parameter(Mandatory=$true)][string]$Branch)
    git merge $Branch 
}
function grb { 
    param([string]$Branch = "main")
    git rebase $Branch 
}
function grs { git reset @args }
function grsh { git reset --hard @args }
function gcp { git cherry-pick @args }

function gclone {
    param([Parameter(Mandatory=$true)][string]$Url)
    git clone $Url
    $repoName = [System.IO.Path]::GetFileNameWithoutExtension($Url)
    if (Test-Path $repoName) {
        Set-Location $repoName
    }
}

function ginit {
    git init
    git add -A
    git commit -m "Initial commit"
}

# Show git branch in prompt helper
function Get-GitBranch {
    $branch = git branch --show-current 2>$null
    if ($branch) {
        return " ($branch)"
    }
    return ""
}

# ===== Archive Operations =====
function zip {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [string]$Destination = ""
    )
    if (-not $Destination) {
        $Destination = "$Source.zip"
    }
    Compress-Archive -Path $Source -DestinationPath $Destination -Force
    Write-Host "Created: $Destination" -ForegroundColor Green
}

function unzip {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [string]$Destination = ""
    )
    if (-not $Destination) {
        $Destination = [System.IO.Path]::GetFileNameWithoutExtension($Source)
    }
    Expand-Archive -Path $Source -DestinationPath $Destination -Force
    Write-Host "Extracted to: $Destination" -ForegroundColor Green
}

# ===== Quick Edit =====
function edit {
    param([string]$Path = ".")
    $editor = if (Get-Command code -ErrorAction SilentlyContinue) { "code" }
              elseif (Get-Command notepad++ -ErrorAction SilentlyContinue) { "notepad++" }
              else { "notepad" }
    & $editor $Path
}

function profile-edit {
    edit $PROFILE
}

# ===== Path Display =====
function pwd-full { (Get-Location).Path }
function pwd-short { (Get-Location).Path.Replace($env:USERPROFILE, '~') }

# ===== Recent Directories =====
$global:DirectoryHistory = @()
$global:MaxDirectoryHistory = 20

function Push-DirectoryHistory {
    param([string]$Path)
    $global:DirectoryHistory = @($Path) + ($global:DirectoryHistory | Where-Object { $_ -ne $Path }) | Select-Object -First $global:MaxDirectoryHistory
}

function Get-DirectoryHistory {
    param([int]$Last = 10)
    $global:DirectoryHistory | Select-Object -First $Last | ForEach-Object {
        $i = [array]::IndexOf($global:DirectoryHistory, $_)
        Write-Host "[$i] $_" -ForegroundColor $(if ($i -eq 0) { "Green" } else { "Gray" })
    }
}

function Set-LocationWithHistory {
    param([string]$Path)
    Push-DirectoryHistory (Get-Location).Path
    Set-Location $Path
}

function Pop-DirectoryHistory {
    param([int]$Index = 0)
    if ($global:DirectoryHistory.Count -gt $Index) {
        $target = $global:DirectoryHistory[$Index]
        # Splice target out of history and push current location
        $global:DirectoryHistory = $global:DirectoryHistory | Where-Object { $_ -ne $target }
        Push-DirectoryHistory (Get-Location).Path
        Set-Location $target
    }
}

# Override cd to track history
function cd {
    param([string]$Path = $env:USERPROFILE)
    if ($Path -eq '-') {
        if ($global:DirectoryHistory.Count -gt 0) {
            $target = $global:DirectoryHistory[0]
            Push-DirectoryHistory (Get-Location).Path
            Set-Location $target
        }
    } else {
        Push-DirectoryHistory (Get-Location).Path
        Set-Location $Path
    }
}

# ===== Aliases =====
Set-Alias dirs Get-DirectoryHistory -Force
Set-Alias back Pop-DirectoryHistory -Force
Set-Alias e edit -Force
