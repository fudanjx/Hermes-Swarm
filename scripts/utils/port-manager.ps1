# port-manager.ps1
# Handles port allocation and availability checking

$ErrorActionPreference = "Stop"

function Test-PortAvailable {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Port
    )

    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        $listener.Stop()
        return $true
    }
    catch {
        return $false
    }
}

function Get-ContainerPorts {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ContainerId,

        [int]$BaseApiPort = 8642,

        [int]$BaseDashboardPort = 9119
    )

    return @{
        api = $BaseApiPort + ($ContainerId - 1)
        dashboard = $BaseDashboardPort + ($ContainerId - 1)
    }
}

function Find-AvailablePortRange {
    param(
        [Parameter(Mandatory=$true)]
        [int]$StartId,

        [Parameter(Mandatory=$true)]
        [int]$Count,

        [int]$BaseApiPort = 8642,

        [int]$BaseDashboardPort = 9119
    )

    $unavailablePorts = @()

    for ($i = 0; $i -lt $Count; $i++) {
        $containerId = $StartId + $i
        $ports = Get-ContainerPorts -ContainerId $containerId -BaseApiPort $BaseApiPort -BaseDashboardPort $BaseDashboardPort

        if (-not (Test-PortAvailable -Port $ports.api)) {
            $unavailablePorts += "Container C$containerId API port $($ports.api) is already in use"
        }

        if (-not (Test-PortAvailable -Port $ports.dashboard)) {
            $unavailablePorts += "Container C$containerId Dashboard port $($ports.dashboard) is already in use"
        }
    }

    return @{
        available = ($unavailablePorts.Count -eq 0)
        unavailable_ports = $unavailablePorts
    }
}

function Show-PortAllocationTable {
    param(
        [Parameter(Mandatory=$true)]
        [int]$StartId,

        [Parameter(Mandatory=$true)]
        [int]$Count
    )

    Write-Host ""
    Write-Host "Port Allocation Plan:" -ForegroundColor Cyan
    Write-Host "+----+--------------+----------+----------------+"
    Write-Host "| ID | Name         | API Port | Dashboard Port |"
    Write-Host "+----+--------------+----------+----------------+"

    for ($i = 0; $i -lt $Count; $i++) {
        $containerId = $StartId + $i
        $ports = Get-ContainerPorts -ContainerId $containerId
        $name = "hermes-c$containerId"

        $idStr = "C$containerId".PadRight(3)
        $nameStr = $name.PadRight(13)
        $apiStr = $ports.api.ToString().PadRight(9)
        $dashStr = $ports.dashboard.ToString().PadRight(15)

        Write-Host "| $idStr| $nameStr| $apiStr| $dashStr|"
    }

    Write-Host "+----+--------------+----------+----------------+"
}

