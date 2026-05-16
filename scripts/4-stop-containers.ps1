# 4-stop-containers.ps1
# Stops one or more Hermes containers

param(
    [Parameter(ParameterSetName='ById', Mandatory=$true)]
    [int[]]$ContainerId,
    
    [Parameter(ParameterSetName='ByRange', Mandatory=$true)]
    [string]$Range,
    
    [Parameter(ParameterSetName='All', Mandatory=$true)]
    [switch]$All
)

$ErrorActionPreference = "Stop"

# Import utility modules
. "$PSScriptRoot\utils\state-manager.ps1"
. "$PSScriptRoot\utils\docker-helpers.ps1"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Hermes Agent - Stop Containers" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# Load state
$state = Get-HermesState

if ($null -eq $state) {
    Write-Host "ERROR: No state file found." -ForegroundColor Red
    exit 1
}

if ($state.containers.Count -eq 0) {
    Write-Host "No containers found." -ForegroundColor Yellow
    exit 0
}

# Parse input to get container IDs
$idsToStop = @()

if ($All) {
    $idsToStop = $state.containers | ForEach-Object { $_.id }
}
elseif ($Range) {
    # Parse range like "1-5"
    if ($Range -match '^(\d+)-(\d+)$') {
        $start = [int]$Matches[1]
        $end = [int]$Matches[2]

        for ($i = $start; $i -le $end; $i++) {
            $idsToStop += $i
        }
    }
    else {
        Write-Host "ERROR: Invalid range format. Use format: 1-5" -ForegroundColor Red
        exit 1
    }
}
elseif ($ContainerId) {
    # Parse comma-separated list like "1,3,5"
    $idsToStop = $ContainerId
}
else {
    Write-Host "ERROR: No containers specified." -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\4-stop-containers.ps1 -ContainerId 1" -ForegroundColor Gray
    Write-Host "  .\4-stop-containers.ps1 -ContainerId 1,3,5" -ForegroundColor Gray
    Write-Host "  .\4-stop-containers.ps1 -Range 1-5" -ForegroundColor Gray
    Write-Host "  .\4-stop-containers.ps1 -All" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Validate containers exist
$containersToStop = @()

foreach ($id in $idsToStop) {
    $container = Get-ContainerById -ContainerId $id

    if ($null -eq $container) {
        Write-Host "WARNING: Container C$id not found in state, skipping..." -ForegroundColor Yellow
    }
    else {
        $containersToStop += $container
    }
}

if ($containersToStop.Count -eq 0) {
    Write-Host "No valid containers to stop." -ForegroundColor Yellow
    exit 0
}

# Show what will be stopped
Write-Host "Will stop $($containersToStop.Count) container(s):" -ForegroundColor White
Write-Host ""

foreach ($container in $containersToStop | Sort-Object -Property id) {
    $status = Get-ContainerStatus -ContainerName $container.name
    $statusDisplay = if ($status -eq "running") {
        "[RUNNING]"
    } else {
        "[ALREADY STOPPED]"
    }

    Write-Host "  - C$($container.id) - $($container.name) $statusDisplay" -ForegroundColor White
}

Write-Host ""
$confirm = Read-Host "Continue? (y/N)"

if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host ""
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# Stop containers
$successCount = 0
$failCount = 0

foreach ($container in $containersToStop | Sort-Object -Property id) {
    Write-Host "Stopping $($container.name)..." -ForegroundColor Cyan

    $status = Get-ContainerStatus -ContainerName $container.name

    if ($status -ne "running") {
        Write-Host "  Container is not running, skipping" -ForegroundColor Yellow
        $successCount++
    }
    else {
        try {
            docker stop $container.name 2>&1 | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "SUCCESS: Stopped $($container.name)" -ForegroundColor Green
                Update-ContainerStatus -ContainerId $container.id -Status "stopped"
                $successCount++
            }
            else {
                throw "Docker stop failed with exit code $LASTEXITCODE"
            }
        }
        catch {
            Write-Host "ERROR: Failed to stop $($container.name): $_" -ForegroundColor Red
            $failCount++
        }
    }

    Write-Host ""
}

# Summary
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Stop Complete" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Successfully stopped: $successCount" -ForegroundColor Green

if ($failCount -gt 0) {
    Write-Host "Failed: $failCount" -ForegroundColor Red
}

Write-Host ""
Write-Host "To restart containers: docker start <container-name>" -ForegroundColor White
Write-Host "Or use: .\scripts\6-restart-containers.ps1 -ContainerId X" -ForegroundColor White
Write-Host ""


