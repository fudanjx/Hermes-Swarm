# Getting Started - 5 Minutes

## Step 1: Initial Setup (One Time)

```powershell
cd C:\Users\eee_j\Documents\Personal_Agents\hermes
.\scripts\1-seed-setup.ps1
```

Follow the interactive setup to configure Codex OAuth.

## Step 2: Spawn Containers

```powershell
# Spawn 5 containers
.\scripts\2-spawn-containers.ps1 -Count 5
```

Output shows container names, ports, and API keys.

## Step 3: Verify

```powershell
.\scripts\3-list-containers.ps1
```

## Step 4: Access

Open browser: http://localhost:8642 (C1), http://localhost:8643 (C2), etc.

---

## Common Commands

```powershell
# List containers
.\scripts\3-list-containers.ps1

# Stop containers
.\scripts\4-stop-containers.ps1 -ContainerId 1,2,3

# Restart containers
.\scripts\6-restart-containers.ps1 -All

# Update API key and restart
.\scripts\6-restart-containers.ps1 -ContainerId 3 -UpdateKeys

# Remove container (keep data)
.\scripts\5-remove-containers.ps1 -ContainerId 3 -KeepVolumes

# Respawn container (reuses preserved data)
.\scripts\2-spawn-containers.ps1 -Count 1 -StartId 3
```

---

## API Key Configuration

Edit `.env` file:

```env
# Default for all containers
DEFAULT_API_KEY=hermes123456

# Per-container (optional)
CONTAINER_C3_API_KEY=custom_key_here
```

Then restart with `-UpdateKeys` to apply.

---

See [README.md](README.md) for complete documentation.
