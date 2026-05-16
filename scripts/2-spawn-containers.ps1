# 2-spawn-containers.ps1
# Spawns N Hermes containers with isolated data volumes

param(
    [int]$Count = 1,
    [int]$StartId = 0,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Import utility modules
. "$PSScriptRoot\utils\state-manager.ps1"
. "$PSScriptRoot\utils\port-manager.ps1"
. "$PSScriptRoot\utils\docker-helpers.ps1"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Hermes Agent - Container Spawning" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

if ($Count -lt 1) {
    Write-Host "ERROR: Count must be at least 1" -ForegroundColor Red
    exit 1
}

if ($Count -gt 100) {
    Write-Host "ERROR: Cannot spawn more than 100 containers at once" -ForegroundColor Red
    exit 1
}

Write-Host "Checking Docker..." -ForegroundColor Yellow
if (-not (Test-DockerRunning)) {
    Write-Host "ERROR: Docker is not running. Please start Docker Desktop and try again." -ForegroundColor Red
    exit 1
}
Write-Host "SUCCESS: Docker is running" -ForegroundColor Green
Write-Host ""

Write-Host "Loading state..." -ForegroundColor Yellow
$state = Get-HermesState

if ($null -eq $state) {
    Write-Host "ERROR: State file not found." -ForegroundColor Red
    Write-Host "  Please run 1-seed-setup.ps1 first to configure the seed." -ForegroundColor Yellow
    exit 1
}

$seedVolume = $state.seed_volume
Write-Host "SUCCESS: State loaded" -ForegroundColor Green
Write-Host ""

Write-Host "Checking seed volume..." -ForegroundColor Yellow
$volumeInfo = Get-VolumeInfo -VolumeName $seedVolume

if (-not $volumeInfo.exists) {
    Write-Host "ERROR: Seed volume not found: $seedVolume" -ForegroundColor Red
    Write-Host "  Please run 1-seed-setup.ps1 first." -ForegroundColor Yellow
    exit 1
}
Write-Host "SUCCESS: Seed volume found: $seedVolume" -ForegroundColor Green
Write-Host ""

if ($StartId -gt 0) {
    $firstId = $StartId
    Write-Host "Using custom start ID: $firstId" -ForegroundColor Yellow
} else {
    $firstId = $state.next_container_id
}

$lastId = $firstId + $Count - 1

Write-Host "Planning to spawn $Count container(s): C$firstId to C$lastId" -ForegroundColor White
Write-Host ""

Show-PortAllocationTable -StartId $firstId -Count $Count
Write-Host ""

if (-not $Force) {
    Write-Host "Checking port availability..." -ForegroundColor Yellow
    $portCheck = Find-AvailablePortRange -StartId $firstId -Count $Count

    if (-not $portCheck.available) {
        Write-Host "ERROR: Port conflicts detected:" -ForegroundColor Red
        foreach ($conflict in $portCheck.unavailable_ports) {
            Write-Host "  - $conflict" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Please free up these ports or use -Force to skip this check." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "SUCCESS: All ports available" -ForegroundColor Green
    Write-Host ""
}

if (-not $Force) {
    Write-Host "Ready to spawn $Count container(s)." -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (y/N)"

    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host ""
        Write-Host "Spawn cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Spawning Containers" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failCount = 0
$spawnedContainers = @()

for ($i = 0; $i -lt $Count; $i++) {
    $containerId = $firstId + $i
    $containerName = "hermes-c$containerId"
    $volumeName = "hermes_c${containerId}_data"
    $ports = Get-ContainerPorts -ContainerId $containerId

    Write-Host "[$($i+1)/$Count] Creating $containerName..." -ForegroundColor Cyan

    try {
        # Check if container already exists (stopped or running)
        $existingContainer = docker ps -aq --filter "name=${containerName}" 2>&1 | Out-String
        $existingContainer = $existingContainer.Trim()

        if ($existingContainer) {
            Write-Host "  Container $containerName already exists, removing it first..." -ForegroundColor Yellow
            docker rm -f $existingContainer 2>&1 | Out-Null
        }

        # Check if volume already exists (from previous container with -KeepVolumes)
        $existingVolume = docker volume ls --filter "name=${volumeName}" --format "{{.Name}}" 2>&1 | Out-String
        $existingVolume = $existingVolume.Trim()

        if ($existingVolume -and $existingVolume -eq $volumeName) {
            Write-Host "  Volume $volumeName already exists, reusing it..." -ForegroundColor Yellow
            Write-Host "  Skipping seed copy (preserving existing data)" -ForegroundColor Gray
        }
        else {
            Write-Host "  Creating new volume $volumeName..." -ForegroundColor Gray
            docker volume create $volumeName 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create volume"
            }

            Copy-DockerVolume -Source $seedVolume -Destination $volumeName
            Set-VolumePermissions -VolumeName $volumeName
        }

        # Get API key for this container
        $apiKey = Get-ContainerApiKey -ContainerId $containerId

        $dockerId = Create-HermesContainer -Id $containerId -VolumeName $volumeName `
            -ApiPort $ports.api -DashboardPort $ports.dashboard -ApiKey $apiKey

        $running = Test-ContainerRunning -ContainerName $containerName

        if (-not $running) {
            throw "Container failed to start"
        }

        $containerInfo = @{
            id = $containerId
            name = $containerName
            volume = $volumeName
            ports = @{
                api = $ports.api
                dashboard = $ports.dashboard
            }
            api_key = $apiKey
            status = "running"
            created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        }

        Add-Container -ContainerInfo $containerInfo

        Write-Host "SUCCESS: Created $containerName (API: $($ports.api), Dashboard: $($ports.dashboard))" -ForegroundColor Green
        $successCount++
        $spawnedContainers += $containerInfo
        Write-Host ""
    }
    catch {
        Write-Host "ERROR: Failed to create $containerName : $_" -ForegroundColor Red
        $failCount++

        try {
            docker rm -f $containerName 2>&1 | Out-Null
            docker volume rm $volumeName 2>&1 | Out-Null
        }
        catch {
        }

        Write-Host ""
    }
}

Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Spawn Complete" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""

if ($successCount -gt 0) {
    Write-Host "Successfully spawned $successCount container(s):" -ForegroundColor Green
    Write-Host ""

    Write-Host "+----+--------------+----------+----------------+"
    Write-Host "| ID | Name         | API Port | Dashboard Port |"
    Write-Host "+----+--------------+----------+----------------+"

    foreach ($container in $spawnedContainers) {
        $idStr = "C$($container.id)".PadRight(3)
        $nameStr = $container.name.PadRight(13)
        $apiStr = $container.ports.api.ToString().PadRight(9)
        $dashStr = $container.ports.dashboard.ToString().PadRight(15)

        Write-Host "| $idStr| $nameStr| $apiStr| $dashStr|"
    }

    Write-Host "+----+--------------+----------+----------------+"
    Write-Host ""

    Write-Host "API Keys (saved to state file):" -ForegroundColor Cyan
    foreach ($container in $spawnedContainers) {
        Write-Host "  - $($container.name): $($container.api_key)" -ForegroundColor White
    }
    Write-Host ""

    Write-Host "Access dashboards:" -ForegroundColor Cyan
    foreach ($container in $spawnedContainers) {
        Write-Host "  - http://localhost:$($container.ports.api) ($($container.name))" -ForegroundColor White
    }
    Write-Host ""

    Write-Host "API Access Example:" -ForegroundColor Cyan
    if ($spawnedContainers.Count -gt 0) {
        $first = $spawnedContainers[0]
        Write-Host "  curl -H 'Authorization: Bearer $($first.api_key)' http://localhost:$($first.ports.api)/api/endpoint" -ForegroundColor Gray
    }
    Write-Host ""
}

if ($failCount -gt 0) {
    Write-Host "Failed to spawn $failCount container(s). See errors above." -ForegroundColor Red
    Write-Host ""
}

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  - List containers: .\scripts\3-list-containers.ps1" -ForegroundColor White
Write-Host "  - Spawn more: .\scripts\2-spawn-containers.ps1 -Count N" -ForegroundColor White
Write-Host ""
