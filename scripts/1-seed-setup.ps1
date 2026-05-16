# 1-seed-setup.ps1
# Initial setup script to create the golden template configuration with OAuth

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Import utility modules
. "$PSScriptRoot\utils\state-manager.ps1"
. "$PSScriptRoot\utils\docker-helpers.ps1"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Hermes Agent - Seed Configuration Setup" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker is running
Write-Host "Checking Docker..." -ForegroundColor Yellow
if (-not (Test-DockerRunning)) {
    Write-Host "ERROR: Docker is not running. Please start Docker Desktop and try again." -ForegroundColor Red
    exit 1
}
Write-Host "SUCCESS: Docker is running" -ForegroundColor Green
Write-Host ""

# Check if state file and seed already exist
$state = Get-HermesState
$seedVolume = "hermes_seed_data"

if ($null -ne $state) {
    $volumeInfo = Get-VolumeInfo -VolumeName $seedVolume

    if ($volumeInfo.exists) {
        Write-Host "WARNING: Seed volume already exists: $seedVolume" -ForegroundColor Yellow
        Write-Host ""

        if (-not $Force) {
            Write-Host "This will DELETE the existing seed configuration and OAuth setup!" -ForegroundColor Red
            Write-Host "All existing containers will lose their configuration source." -ForegroundColor Red
            Write-Host ""
            $confirm = Read-Host "Type RECREATE to continue, or anything else to cancel"

            if ($confirm -ne "RECREATE") {
                Write-Host ""
                Write-Host "Setup cancelled." -ForegroundColor Yellow
                exit 0
            }
        }

        Write-Host ""
        Write-Host "Removing existing seed volume..." -ForegroundColor Yellow
        docker volume rm $seedVolume 2>&1 | Out-Null
        Write-Host "SUCCESS: Old seed removed" -ForegroundColor Green
        Write-Host ""
    }
}

# Create seed volume
Write-Host "Creating seed volume: $seedVolume" -ForegroundColor Yellow
docker volume create $seedVolume | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create seed volume" -ForegroundColor Red
    exit 1
}
Write-Host "SUCCESS: Seed volume created" -ForegroundColor Green
Write-Host ""

# Run interactive setup
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Starting Interactive Hermes Setup" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "You will now configure Hermes, including:" -ForegroundColor White
Write-Host "  - Codex OAuth authentication" -ForegroundColor White
Write-Host "  - API keys and providers" -ForegroundColor White
Write-Host "  - MCP servers" -ForegroundColor White
Write-Host "  - Agent personality and skills" -ForegroundColor White
Write-Host ""
Write-Host "This configuration will be saved to the seed volume" -ForegroundColor White
Write-Host "and cloned to all future containers." -ForegroundColor White
Write-Host ""
Write-Host "Press any key to start setup..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Host ""

# Run interactive setup with volume mounted
$setupCmd = "docker run -it --rm -v ${seedVolume}:/opt/data nousresearch/hermes-agent setup"

try {
    Invoke-Expression $setupCmd

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Setup command failed" -ForegroundColor Red
        Write-Host "Cleaning up seed volume..." -ForegroundColor Yellow
        docker volume rm $seedVolume | Out-Null
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: Setup failed: $_" -ForegroundColor Red
    Write-Host "Cleaning up seed volume..." -ForegroundColor Yellow
    docker volume rm $seedVolume | Out-Null
    exit 1
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Verifying Configuration" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# Verify seed volume has content
Write-Host "Checking seed volume contents..." -ForegroundColor Yellow
$volumeContents = docker run --rm -v ${seedVolume}:/opt/data:ro alpine ls -la /opt/data 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to read seed volume" -ForegroundColor Red
    exit 1
}

# Check for critical files
$hasConfigYaml = docker run --rm -v ${seedVolume}:/opt/data:ro alpine test -f /opt/data/config.yaml 2>&1; $LASTEXITCODE -eq 0
$hasEnv = docker run --rm -v ${seedVolume}:/opt/data:ro alpine test -f /opt/data/.env 2>&1; $LASTEXITCODE -eq 0

Write-Host "SUCCESS: Seed volume accessible" -ForegroundColor Green

if ($hasConfigYaml) {
    Write-Host "SUCCESS: config.yaml found" -ForegroundColor Green
} else {
    Write-Host "WARNING: config.yaml not found (may not have completed setup)" -ForegroundColor Yellow
}

if ($hasEnv) {
    Write-Host "SUCCESS: .env found" -ForegroundColor Green
} else {
    Write-Host "WARNING: .env not found (optional)" -ForegroundColor Yellow
}

Write-Host ""

# Initialize or update state file
Write-Host "Updating state file..." -ForegroundColor Yellow

if ($null -eq $state) {
    $state = Initialize-HermesState
} else {
    $state.next_container_id = 1
    $state.containers = @()
    Update-HermesState -State $state
    Write-Host "SUCCESS: State file reset" -ForegroundColor Green
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Seed Setup Complete!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Seed volume: $seedVolume" -ForegroundColor White
Write-Host "This configuration will be cloned to all spawned containers." -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Spawn containers:" -ForegroundColor White
Write-Host "     .\scripts\2-spawn-containers.ps1 -Count 5" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. List containers:" -ForegroundColor White
Write-Host "     .\scripts\3-list-containers.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Access dashboards:" -ForegroundColor White
Write-Host "     http://localhost:8642 (first container)" -ForegroundColor Gray
Write-Host ""
