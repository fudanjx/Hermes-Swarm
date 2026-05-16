# 6-restart-containers.ps1
# Safely restarts containers and optionally updates API keys from .env

param(
    [Parameter(ParameterSetName='ById', Mandatory=$true)]
    [int[]]$ContainerId,
    
    [Parameter(ParameterSetName='ByRange', Mandatory=$true)]
    [string]$Range,
    
    [Parameter(ParameterSetName='All', Mandatory=$true)]
    [switch]$All,
    
    [switch]$UpdateKeys
)

$ErrorActionPreference = "Stop"

# Import utility modules
. "$PSScriptRoot\utils\state-manager.ps1"
. "$PSScriptRoot\utils\port-manager.ps1"
. "$PSScriptRoot\utils\docker-helpers.ps1"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Hermes Agent - Restart Containers" -ForegroundColor Cyan
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
$idsToRestart = @()

if ($All) {
    $idsToRestart = $state.containers | ForEach-Object { $_.id }
}
elseif ($Range) {
    if ($Range -match '^(\d+)-(\d+)$') {
        $start = [int]$Matches[1]
        $end = [int]$Matches[2]

        for ($i = $start; $i -le $end; $i++) {
            $idsToRestart += $i
        }
    }
    else {
        Write-Host "ERROR: Invalid range format. Use format: 1-5" -ForegroundColor Red
        exit 1
    }
}
elseif ($ContainerId) {
    $idsToRestart = $ContainerId
}
else {
    Write-Host "ERROR: No containers specified." -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\6-restart-containers.ps1 -ContainerId 1" -ForegroundColor Gray
    Write-Host "  .\6-restart-containers.ps1 -ContainerId 1,3,5" -ForegroundColor Gray
    Write-Host "  .\6-restart-containers.ps1 -Range 1-5" -ForegroundColor Gray
    Write-Host "  .\6-restart-containers.ps1 -All" -ForegroundColor Gray
    Write-Host "  .\6-restart-containers.ps1 -ContainerId 1 -UpdateKeys" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Validate containers exist
$containersToRestart = @()

foreach ($id in $idsToRestart) {
    $container = Get-ContainerById -ContainerId $id

    if ($null -eq $container) {
        Write-Host "WARNING: Container C$id not found in state, skipping..." -ForegroundColor Yellow
    }
    else {
        $containersToRestart += $container
    }
}

if ($containersToRestart.Count -eq 0) {
    Write-Host "No valid containers to restart." -ForegroundColor Yellow
    exit 0
}

# Show what will be restarted
Write-Host "Will restart $($containersToRestart.Count) container(s):" -ForegroundColor White
Write-Host ""

if ($UpdateKeys) {
    Write-Host "MODE: Recreate with updated API keys from .env" -ForegroundColor Yellow
    Write-Host ""
}
else {
    Write-Host "MODE: Simple restart (docker restart)" -ForegroundColor Cyan
    Write-Host ""
}

foreach ($container in $containersToRestart | Sort-Object -Property id) {
    $status = Get-ContainerStatus -ContainerName $container.name
    
    if ($UpdateKeys) {
        $newKey = Get-ContainerApiKey -ContainerId $container.id
        Write-Host "  - C$($container.id) - $($container.name) [New API Key: $newKey]" -ForegroundColor White
    }
    else {
        Write-Host "  - C$($container.id) - $($container.name) [$status]" -ForegroundColor White
    }
}

Write-Host ""
$confirm = Read-Host "Continue? (y/N)"

if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host ""
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# Restart containers
$successCount = 0
$failCount = 0

foreach ($container in $containersToRestart | Sort-Object -Property id) {
    Write-Host "Restarting $($container.name)..." -ForegroundColor Cyan

    try {
        if ($UpdateKeys) {
            # Get new API key from .env
            $newKey = Get-ContainerApiKey -ContainerId $container.id

            Write-Host "  Stopping and removing old container..." -ForegroundColor Gray
            docker stop $container.name 2>&1 | Out-Null
            docker rm $container.name 2>&1 | Out-Null

            Write-Host "  Creating new container with updated API key..." -ForegroundColor Gray
            
            # Recreate with new API key
            $dockerId = Create-HermesContainer -Id $container.id -VolumeName $container.volume `
                -ApiPort $container.ports.api -DashboardPort $container.ports.dashboard -ApiKey $newKey

            # Verify container started
            Start-Sleep -Seconds 2
            $running = Test-ContainerRunning -ContainerName $container.name

            if (-not $running) {
                throw "Container failed to start after recreation"
            }

            # Update API key in state
            $container.api_key = $newKey
            $container.status = "running"
            
            # Update state file
            $stateUpdate = Get-HermesState
            $stateContainer = $stateUpdate.containers | Where-Object { $_.id -eq $container.id }
            if ($stateContainer) {
                $stateContainer.api_key = $newKey
                $stateContainer.status = "running"
                Update-HermesState -State $stateUpdate
            }

            Write-Host "SUCCESS: Recreated $($container.name) with new API key" -ForegroundColor Green
        }
        else {
            # Simple restart
            docker restart $container.name 2>&1 | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "SUCCESS: Restarted $($container.name)" -ForegroundColor Green
                Update-ContainerStatus -ContainerId $container.id -Status "running"
            }
            else {
                throw "Docker restart failed with exit code $LASTEXITCODE"
            }
        }

        $successCount++
    }
    catch {
        Write-Host "ERROR: Failed to restart $($container.name): $_" -ForegroundColor Red
        $failCount++
    }

    Write-Host ""
}

# Summary
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Restart Complete" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Successfully restarted: $successCount" -ForegroundColor Green

if ($failCount -gt 0) {
    Write-Host "Failed: $failCount" -ForegroundColor Red
}

Write-Host ""

if ($UpdateKeys) {
    Write-Host "API keys have been updated from .env file" -ForegroundColor Cyan
    Write-Host "Updated containers are now running with new keys" -ForegroundColor White
    Write-Host ""
}

