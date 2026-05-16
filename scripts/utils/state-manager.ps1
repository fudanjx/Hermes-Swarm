# state-manager.ps1
# Manages the hermes-state.json file for tracking spawned containers

$ErrorActionPreference = "Stop"

$StateFilePath = Join-Path $PSScriptRoot "..\..\hermes-state.json"

function Initialize-HermesState {
    $initialState = @{
        seed_volume = "hermes_seed_data"
        next_container_id = 1
        base_ports = @{
            api = 8642
            dashboard = 9119
        }
        containers = @()
    }

    $json = $initialState | ConvertTo-Json -Depth 10
    Set-Content -Path $StateFilePath -Value $json -Encoding UTF8

    Write-Host "SUCCESS: State file initialized at: $StateFilePath" -ForegroundColor Green
    return $initialState
}

function Get-HermesState {
    if (-not (Test-Path $StateFilePath)) {
        return $null
    }

    try {
        $json = Get-Content -Path $StateFilePath -Raw -Encoding UTF8
        $state = $json | ConvertFrom-Json

        if (-not $state.PSObject.Properties['seed_volume']) {
            throw "State file missing seed_volume field"
        }
        if (-not $state.PSObject.Properties['next_container_id']) {
            throw "State file missing next_container_id field"
        }

        return $state
    }
    catch {
        Write-Error "Failed to read state file: $_"
        return $null
    }
}

function Update-HermesState {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$State
    )

    $tempFile = "$StateFilePath.tmp"

    try {
        $json = $State | ConvertTo-Json -Depth 10
        Set-Content -Path $tempFile -Value $json -Encoding UTF8
        Move-Item -Path $tempFile -Destination $StateFilePath -Force
    }
    catch {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
        throw "Failed to update state file: $_"
    }
}

function Add-Container {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$ContainerInfo
    )

    $state = Get-HermesState
    if ($null -eq $state) {
        throw "State file not found. Run 1-seed-setup.ps1 first."
    }

    if ($null -eq $state.containers) {
        $state.containers = @()
    }

    $existing = $state.containers | Where-Object { $_.id -eq $ContainerInfo.id }
    if ($existing) {
        Write-Warning "Container with ID $($ContainerInfo.id) already exists in state. Updating..."
        $state.containers = @($state.containers | Where-Object { $_.id -ne $ContainerInfo.id })
    }

    $state.containers = @($state.containers) + @([PSCustomObject]$ContainerInfo)

    if ($ContainerInfo.id -ge $state.next_container_id) {
        $state.next_container_id = $ContainerInfo.id + 1
    }

    Update-HermesState -State $state
}

function Remove-Container {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ContainerId
    )

    $state = Get-HermesState
    if ($null -eq $state) {
        throw "State file not found."
    }

    $state.containers = @($state.containers | Where-Object { $_.id -ne $ContainerId })
    Update-HermesState -State $state
}

function Get-NextContainerId {
    $state = Get-HermesState
    if ($null -eq $state) {
        throw "State file not found. Run 1-seed-setup.ps1 first."
    }

    return $state.next_container_id
}

function Get-ContainerById {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ContainerId
    )

    $state = Get-HermesState
    if ($null -eq $state) {
        return $null
    }

    return $state.containers | Where-Object { $_.id -eq $ContainerId }
}

function Update-ContainerStatus {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ContainerId,

        [Parameter(Mandatory=$true)]
        [string]$Status
    )

    $state = Get-HermesState
    if ($null -eq $state) {
        throw "State file not found."
    }

    $container = $state.containers | Where-Object { $_.id -eq $ContainerId }
    if ($container) {
        $container.status = $Status
        Update-HermesState -State $state
    }
}

