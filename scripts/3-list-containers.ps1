# 3-list-containers.ps1
# Lists all managed Hermes containers with their status

$ErrorActionPreference = "Stop"

# Import utility modules
. "$PSScriptRoot\utils\state-manager.ps1"
. "$PSScriptRoot\utils\docker-helpers.ps1"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Hermes Container Status" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# Load state
$state = Get-HermesState

if ($null -eq $state) {
    Write-Host ""
    Write-Host "No state file found." -ForegroundColor Yellow
    Write-Host "Run 1-seed-setup.ps1 to initialize." -ForegroundColor White
    Write-Host ""
    exit 0
}

# Display seed info
Write-Host ""
$seedExists = (Get-VolumeInfo -VolumeName $state.seed_volume).exists
$seedStatus = if ($seedExists) { "OK" } else { "MISSING" }

Write-Host "Seed Volume: $($state.seed_volume) [$seedStatus]" -ForegroundColor $(if ($seedExists) { "Green" } else { "Red" })
Write-Host "Next Container ID: $($state.next_container_id)" -ForegroundColor White
Write-Host ""

# Check if we have any containers
if ($state.containers.Count -eq 0) {
    Write-Host "No containers spawned yet." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To spawn containers, run:" -ForegroundColor Cyan
    Write-Host "  .\scripts\2-spawn-containers.ps1 -Count 5" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Query actual Docker status for each container
Write-Host "Active Containers:" -ForegroundColor White
Write-Host "+----+--------------+----------+----------+----------------+------------+"
Write-Host "| ID | Name         | Status   | API Port | Dashboard Port | Created    |"
Write-Host "+----+--------------+----------+----------+----------------+------------+"

$runningCount = 0
$stoppedCount = 0
$errorCount = 0

foreach ($container in $state.containers | Sort-Object -Property id) {
    $actualStatus = Get-ContainerStatus -ContainerName $container.name

    # Map status to display
    $statusDisplay = switch ($actualStatus) {
        "running" { "running"; $runningCount++; "running" }
        "exited" { "stopped"; $stoppedCount++; "stopped" }
        "not_found" { "missing"; $errorCount++; "missing" }
        default { $actualStatus; $errorCount++; $actualStatus }
    }

    # Color code status
    $statusColor = switch ($actualStatus) {
        "running" { "Green" }
        "exited" { "Yellow" }
        default { "Red" }
    }

    # Format created date
    $createdDate = try {
        $date = [DateTime]::Parse($container.created_at)
        $timeSpan = (Get-Date) - $date

        if ($timeSpan.TotalDays -gt 1) {
            "$([Math]::Floor($timeSpan.TotalDays))d ago"
        } elseif ($timeSpan.TotalHours -gt 1) {
            "$([Math]::Floor($timeSpan.TotalHours))h ago"
        } else {
            "$([Math]::Floor($timeSpan.TotalMinutes))m ago"
        }
    } catch {
        "unknown"
    }

    $idStr = "C$($container.id)".PadRight(3)
    $nameStr = $container.name.PadRight(13)
    $statusStr = $statusDisplay.PadRight(9)
    $apiStr = $container.ports.api.ToString().PadRight(9)
    $dashStr = $container.ports.dashboard.ToString().PadRight(15)
    $createdStr = $createdDate.PadRight(11)

    # Write with color-coded status
    $linePrefix = "| $idStr| $nameStr| "
    $lineSuffix = " | $apiStr| $dashStr| $createdStr|"

    Write-Host $linePrefix -NoNewline
    Write-Host $statusStr -NoNewline -ForegroundColor $statusColor
    Write-Host $lineSuffix
}

Write-Host "+----+--------------+----------+----------+----------------+------------+"
Write-Host ""

# Summary
$total = $state.containers.Count
Write-Host "Total: $total container(s) " -NoNewline -ForegroundColor White

$statusParts = @()
if ($runningCount -gt 0) { $statusParts += "$runningCount running" }
if ($stoppedCount -gt 0) { $statusParts += "$stoppedCount stopped" }
if ($errorCount -gt 0) { $statusParts += "$errorCount error" }

Write-Host "($($statusParts -join ', '))" -ForegroundColor Gray
Write-Host ""

# Show dashboard URLs and API keys for running containers
$runningContainers = @()
foreach ($container in $state.containers | Sort-Object -Property id) {
    $actualStatus = Get-ContainerStatus -ContainerName $container.name
    if ($actualStatus -eq "running") {
        $runningContainers += $container
    }
}

if ($runningContainers.Count -gt 0) {
    Write-Host "Access running dashboards:" -ForegroundColor Cyan
    foreach ($container in $runningContainers) {
        Write-Host "  - http://localhost:$($container.ports.api) ($($container.name))" -ForegroundColor White
    }
    Write-Host ""

    Write-Host "API Keys:" -ForegroundColor Cyan
    foreach ($container in $runningContainers) {
        $apiKey = if ($container.PSObject.Properties['api_key']) { $container.api_key } else { "not stored" }
        Write-Host "  - $($container.name): $apiKey" -ForegroundColor White
    }
    Write-Host ""
}

# Actions
Write-Host "Available actions:" -ForegroundColor Cyan
Write-Host "  - Spawn more: .\scripts\2-spawn-containers.ps1 -Count N" -ForegroundColor White
Write-Host "  - Restart: .\scripts\6-restart-containers.ps1 -ContainerId X" -ForegroundColor White
Write-Host "  - Stop: .\scripts\4-stop-containers.ps1 -ContainerId X" -ForegroundColor White
Write-Host "  - Remove: .\scripts\5-remove-containers.ps1 -ContainerId X" -ForegroundColor White
Write-Host ""
