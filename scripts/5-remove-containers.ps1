# 5-remove-containers.ps1
# Removes Hermes containers and optionally their volumes

param(
    [Parameter(ParameterSetName='ById', Mandatory=$true)]
    [int[]]$ContainerId,
    
    [Parameter(ParameterSetName='ByRange', Mandatory=$true)]
    [string]$Range,
    
    [Parameter(ParameterSetName='All', Mandatory=$true)]
    [switch]$All,
    
    [switch]$KeepVolumes
)

$ErrorActionPreference = "Stop"

# Import utility modules
. "$PSScriptRoot\utils\state-manager.ps1"
. "$PSScriptRoot\utils\docker-helpers.ps1"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Hermes Agent - Remove Containers" -ForegroundColor Cyan
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
$idsToRemove = @()

if ($All) {
    $idsToRemove = $state.containers | ForEach-Object { $_.id }
}
elseif ($Range) {
    if ($Range -match '^(\d+)-(\d+)$') {
        $start = [int]$Matches[1]
        $end = [int]$Matches[2]

        for ($i = $start; $i -le $end; $i++) {
            $idsToRemove += $i
        }
    }
    else {
        Write-Host "ERROR: Invalid range format. Use format: 1-5" -ForegroundColor Red
        exit 1
    }
}
elseif ($ContainerId) {
    $idsToRemove = $ContainerId
}
else {
    Write-Host "ERROR: No containers specified." -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\5-remove-containers.ps1 -ContainerId 1" -ForegroundColor Gray
    Write-Host "  .\5-remove-containers.ps1 -ContainerId 1,3,5" -ForegroundColor Gray
    Write-Host "  .\5-remove-containers.ps1 -Range 1-5" -ForegroundColor Gray
    Write-Host "  .\5-remove-containers.ps1 -All" -ForegroundColor Gray
    Write-Host "  .\5-remove-containers.ps1 -ContainerId 1 -KeepVolumes" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Validate containers exist
$containersToRemove = @()

foreach ($id in $idsToRemove) {
    $container = Get-ContainerById -ContainerId $id

    if ($null -eq $container) {
        Write-Host "WARNING: Container C$id not found in state, skipping..." -ForegroundColor Yellow
    }
    else {
        $containersToRemove += $container
    }
}

if ($containersToRemove.Count -eq 0) {
    Write-Host "No valid containers to remove." -ForegroundColor Yellow
    exit 0
}

# Show what will be removed
Write-Host "WARNING: This will PERMANENTLY REMOVE:" -ForegroundColor Red
Write-Host ""

foreach ($container in $containersToRemove | Sort-Object -Property id) {
    Write-Host "  - Container: $($container.name)" -ForegroundColor White

    if (-not $KeepVolumes) {
        Write-Host "    Volume: $($container.volume) (ALL DATA WILL BE LOST)" -ForegroundColor Red
    }
}

Write-Host ""

if ($KeepVolumes) {
    Write-Host "Volumes will be preserved (data kept)" -ForegroundColor Yellow
}
else {
    Write-Host "This will DELETE all container data permanently!" -ForegroundColor Red
}

Write-Host ""

# Extra confirmation for destructive operation
if (-not $KeepVolumes) {
    Write-Host "Type 'DELETE' to confirm permanent removal: " -NoNewline -ForegroundColor Red
    $confirm1 = Read-Host

    if ($confirm1 -ne "DELETE") {
        Write-Host ""
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}
else {
    $confirm1 = Read-Host "Type 'REMOVE' to confirm"

    if ($confirm1 -ne "REMOVE") {
        Write-Host ""
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""

# Remove containers
$successCount = 0
$failCount = 0

foreach ($container in $containersToRemove | Sort-Object -Property id) {
    Write-Host "Removing $($container.name)..." -ForegroundColor Cyan

    try {
        Remove-HermesContainer -ContainerName $container.name -RemoveVolume (-not $KeepVolumes) -VolumeName $container.volume

        # Remove from state
        Remove-Container -ContainerId $container.id

        Write-Host "SUCCESS: Removed $($container.name)" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "ERROR: Failed to remove $($container.name): $_" -ForegroundColor Red
        $failCount++
    }

    Write-Host ""
}

# Summary
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Removal Complete" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Successfully removed: $successCount" -ForegroundColor Green

if ($failCount -gt 0) {
    Write-Host "Failed: $failCount" -ForegroundColor Red
}

Write-Host ""

if ($KeepVolumes) {
    Write-Host "Volumes were preserved. You can:" -ForegroundColor Cyan
    Write-Host "  - Manually remove them: docker volume rm <volume-name>" -ForegroundColor White
    Write-Host "  - Reuse them in new containers" -ForegroundColor White
}

Write-Host ""


