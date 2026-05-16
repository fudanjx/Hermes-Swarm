# docker-helpers.ps1
# Docker operation wrappers for Hermes container management

$ErrorActionPreference = "Stop"

$EnvFilePath = Join-Path $PSScriptRoot "..\..\.env"

function Get-ContainerApiKey {
    param(
        [Parameter(Mandatory=$true)]
        [int]$ContainerId
    )

    $defaultKey = "hermes123456"

    # Check if .env file exists
    if (-not (Test-Path $EnvFilePath)) {
        Write-Host "  Warning: .env file not found, using default API key" -ForegroundColor Yellow
        return $defaultKey
    }

    # Read .env file
    $envContent = Get-Content $EnvFilePath -ErrorAction SilentlyContinue

    # Look for container-specific key first
    $containerKeyPattern = "^CONTAINER_C${ContainerId}_API_KEY=(.+)$"
    $containerKey = $envContent | Where-Object { $_ -match $containerKeyPattern }

    if ($containerKey) {
        $key = $containerKey -replace $containerKeyPattern, '$1'
        return $key.Trim()
    }

    # Fall back to default key
    $defaultKeyPattern = "^DEFAULT_API_KEY=(.+)$"
    $defaultKeyLine = $envContent | Where-Object { $_ -match $defaultKeyPattern }

    if ($defaultKeyLine) {
        $key = $defaultKeyLine -replace $defaultKeyPattern, '$1'
        return $key.Trim()
    }

    # If nothing found, return hardcoded default
    return $defaultKey
}

function Copy-DockerVolume {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Source,

        [Parameter(Mandatory=$true)]
        [string]$Destination
    )

    Write-Host "  Copying volume $Source to $Destination..." -ForegroundColor Gray

    # Use alpine as root to copy, then fix permissions
    $cmd = "docker run --rm -v ${Source}:/from:ro -v ${Destination}:/to alpine sh -c `"cp -a /from/. /to/`""

    try {
        Invoke-Expression $cmd | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker copy command failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        throw "Failed to copy volume: $_"
    }
}

function Set-VolumePermissions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VolumeName
    )

    Write-Host "  Setting permissions on $VolumeName..." -ForegroundColor Gray

    # Use alpine as root to set ownership to user ID 10000 (hermes user in the image)
    $cmd = "docker run --rm -v ${VolumeName}:/to alpine sh -c `"chown -R 10000:10000 /to && chmod -R u+rwX /to`""

    try {
        Invoke-Expression $cmd | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker chmod command failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        throw "Failed to set permissions: $_"
    }
}

function Set-ContainerApiKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VolumeName,

        [Parameter(Mandatory=$true)]
        [string]$ApiKey
    )

    Write-Host "  Setting API key in volume .env file..." -ForegroundColor Gray

    # Escape special characters for sed
    $escapedKey = $ApiKey -replace '[&/\]', '\$&'

    # Update or add API_SERVER_KEY in the container's .env file
    $cmd = @"
docker run --rm -v ${VolumeName}:/data nousresearch/hermes-agent sh -c "
if grep -q '^API_SERVER_KEY=' /data/.env 2>/dev/null; then
    sed -i 's/^API_SERVER_KEY=.*/API_SERVER_KEY=$escapedKey/' /data/.env
else
    echo 'API_SERVER_KEY=$escapedKey' >> /data/.env
fi
"
"@

    try {
        Invoke-Expression $cmd | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set API key with exit code $LASTEXITCODE"
        }
    }
    catch {
        throw "Failed to set API key in volume: $_"
    }
}

function Create-HermesContainer {
    param(
        [Parameter(Mandatory=$true)]
        [int]$Id,

        [Parameter(Mandatory=$true)]
        [string]$VolumeName,

        [Parameter(Mandatory=$true)]
        [int]$ApiPort,

        [Parameter(Mandatory=$true)]
        [int]$DashboardPort,

        [string]$ApiKey = $null
    )

    $containerName = "hermes-c$Id"

    # Get API key from .env file
    if ([string]::IsNullOrEmpty($ApiKey)) {
        $ApiKey = Get-ContainerApiKey -ContainerId $Id
    }

    Write-Host "  Starting container $containerName..." -ForegroundColor Gray
    Write-Host "  API Key: $ApiKey" -ForegroundColor Gray

    $cmd = @"
docker run -d ``
  --name $containerName ``
  --restart unless-stopped ``
  -e HERMES_DASHBOARD=1 ``
  -e API_SERVER_ENABLED=true ``
  -e API_SERVER_HOST=0.0.0.0 ``
  -e API_SERVER_KEY=$ApiKey ``
  -e API_SERVER_CORS_ORIGINS=* ``
  -v ${VolumeName}:/opt/data ``
  -p ${ApiPort}:8642 ``
  -p ${DashboardPort}:9119 ``
  nousresearch/hermes-agent gateway run
"@

    try {
        $containerId = Invoke-Expression $cmd
        if ($LASTEXITCODE -ne 0) {
            throw "Docker run command failed with exit code $LASTEXITCODE"
        }

        Start-Sleep -Seconds 2
        return $containerId.Trim()
    }
    catch {
        throw "Failed to create container: $_"
    }
}

function Test-ContainerRunning {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName
    )

    try {
        $status = docker inspect --format='{{.State.Running}}' $ContainerName 2>$null
        return $status -eq "true"
    }
    catch {
        return $false
    }
}

function Get-ContainerStatus {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName
    )

    try {
        $exists = docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $ContainerName }
        if (-not $exists) {
            return "not_found"
        }

        $running = docker inspect --format='{{.State.Running}}' $ContainerName 2>$null
        if ($running -eq "true") {
            return "running"
        }

        $status = docker inspect --format='{{.State.Status}}' $ContainerName 2>$null
        return $status
    }
    catch {
        return "error"
    }
}

function Get-VolumeInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VolumeName
    )

    try {
        $exists = docker volume ls --format '{{.Name}}' | Where-Object { $_ -eq $VolumeName }
        return [PSCustomObject]@{
            exists = ($null -ne $exists)
            name = $VolumeName
        }
    }
    catch {
        return [PSCustomObject]@{
            exists = $false
            name = $VolumeName
        }
    }
}

function Test-DockerRunning {
    try {
        docker ps > $null 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Remove-HermesContainer {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,

        [bool]$RemoveVolume = $false,

        [string]$VolumeName
    )

    $running = Test-ContainerRunning -ContainerName $ContainerName
    if ($running) {
        Write-Host "  Stopping $ContainerName..." -ForegroundColor Gray
        docker stop $ContainerName > $null 2>&1
    }

    Write-Host "  Removing $ContainerName..." -ForegroundColor Gray
    docker rm $ContainerName > $null 2>&1

    if ($RemoveVolume -and $VolumeName) {
        Write-Host "  Removing volume $VolumeName..." -ForegroundColor Gray
        docker volume rm $VolumeName > $null 2>&1
    }
}

