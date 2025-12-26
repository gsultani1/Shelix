# ===== DockerTools.ps1 =====
# Docker shortcuts and utilities

function dps { 
    <#
    .SYNOPSIS
    List running Docker containers
    #>
    docker ps 
}

function dpsa { 
    <#
    .SYNOPSIS
    List all Docker containers (including stopped)
    #>
    docker ps -a 
}

function dlog { 
    <#
    .SYNOPSIS
    Follow Docker container logs
    #>
    param([Parameter(Mandatory=$true)][string]$container)
    docker logs -f $container 
}

function dexec { 
    <#
    .SYNOPSIS
    Execute bash in a Docker container
    #>
    param([Parameter(Mandatory=$true)][string]$container)
    docker exec -it $container /bin/bash 
}

function dstop { 
    <#
    .SYNOPSIS
    Stop all running Docker containers
    #>
    docker stop $(docker ps -q) 
}

function drm {
    <#
    .SYNOPSIS
    Remove stopped Docker containers
    #>
    docker container prune -f
}

function drmi {
    <#
    .SYNOPSIS
    Remove dangling Docker images
    #>
    docker image prune -f
}

function dclean {
    <#
    .SYNOPSIS
    Clean up Docker system (containers, images, networks, volumes)
    #>
    Write-Host "Cleaning Docker system..." -ForegroundColor Cyan
    docker system prune -f
    Write-Host "Docker cleanup complete." -ForegroundColor Green
}

function dstats {
    <#
    .SYNOPSIS
    Show Docker container resource usage
    #>
    docker stats --no-stream
}

function dimages {
    <#
    .SYNOPSIS
    List Docker images
    #>
    docker images
}

function dvolumes {
    <#
    .SYNOPSIS
    List Docker volumes
    #>
    docker volume ls
}

function dnetworks {
    <#
    .SYNOPSIS
    List Docker networks
    #>
    docker network ls
}

function dbuild {
    <#
    .SYNOPSIS
    Build Docker image from current directory
    #>
    param(
        [Parameter(Mandatory=$true)][string]$tag,
        [string]$dockerfile = "Dockerfile"
    )
    docker build -t $tag -f $dockerfile .
}

function drun {
    <#
    .SYNOPSIS
    Run a Docker container interactively
    #>
    param(
        [Parameter(Mandatory=$true)][string]$image,
        [string]$name,
        [string[]]$ports,
        [switch]$detach
    )
    
    $dockerArgs = @()
    if ($detach) { $dockerArgs += "-d" } else { $dockerArgs += "-it" }
    if ($name) { $dockerArgs += "--name"; $dockerArgs += $name }
    foreach ($p in $ports) { $dockerArgs += "-p"; $dockerArgs += $p }
    $dockerArgs += $image
    
    docker run @dockerArgs
}

function Get-DockerInfo {
    <#
    .SYNOPSIS
    Display Docker system information
    #>
    Write-Host "`n===== Docker Info =====" -ForegroundColor Cyan
    
    $dockerAvailable = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerAvailable) {
        Write-Host "Docker not found in PATH" -ForegroundColor Red
        return
    }
    
    try {
        $version = docker version --format '{{.Server.Version}}' 2>$null
        Write-Host "Docker Version: $version" -ForegroundColor White
        
        $containers = (docker ps -q 2>$null | Measure-Object).Count
        $allContainers = (docker ps -aq 2>$null | Measure-Object).Count
        Write-Host "Containers: $containers running / $allContainers total" -ForegroundColor White
        
        $images = (docker images -q 2>$null | Measure-Object).Count
        Write-Host "Images: $images" -ForegroundColor White
        
    } catch {
        Write-Host "Docker daemon not running or not accessible" -ForegroundColor Yellow
    }
    
    Write-Host "========================`n" -ForegroundColor Cyan
}

Set-Alias dinfo Get-DockerInfo -Force

Write-Verbose "DockerTools loaded: dps, dpsa, dlog, dexec, dstop, drm, drmi, dclean, dstats"
