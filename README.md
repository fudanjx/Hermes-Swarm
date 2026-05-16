# Hermes Agent Container Scaling System

Complete Docker-based solution for running multiple Hermes Agent containers with preserved Onboarding configuration.

## Quick Start

```powershell
cd C:\Users\eee_j\Documents\Personal_Agents\hermes

# 1. Initial setup (run once)
.\scripts\1-seed-setup.ps1

# 2. Spawn containers
.\scripts\2-spawn-containers.ps1 -Count 5

# 3. List containers
.\scripts\3-list-containers.ps1
```

Access dashboards at: http://localhost:8642, http://localhost:8643, etc.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Scripts Reference](#scripts-reference)
- [API Key Management](#api-key-management)
- [Common Workflows](#common-workflows)
- [Troubleshooting](#troubleshooting)

---

## Overview

### What It Does

- **One-time OAuth setup** - Configure Codex OAuth once, clone to all containers
- **Scalable** - Spawn containers incrementally (C1-C5, then C6-C10, etc.)
- **Isolated data** - Each container has independent working data
- **Auto port assignment** - API and Dashboard ports assigned automatically
- **Easy management** - Simple CLI scripts for all operations

### Architecture

```
hermes_seed_data (Golden Template)
    └─ Contains: OAuth tokens, config, API keys
    
    ↓ Cloned at spawn time
    
hermes_c1_data → Container C1 (ports 8642, 9119)
hermes_c2_data → Container C2 (ports 8643, 9120)
hermes_c3_data → Container C3 (ports 8644, 9121)
    └─ Each evolves independently
```

### Port Assignment

| Container | API Port | Dashboard Port |
|-----------|----------|----------------|
| C1        | 8642     | 9119           |
| C2        | 8643     | 9120           |
| C3        | 8644     | 9121           |
| CN        | 8642+(N-1) | 9119+(N-1) |

---

## Prerequisites

- **Docker Desktop** (Windows/Mac) or Docker Engine (Linux)
- **PowerShell** 5.1+ or PowerShell Core 7+
- **Internet connection** for Hermes Agent image

---

## Scripts Reference

All scripts are in `.\scripts\` directory.

### 1. Seed Setup (Run Once)

**`1-seed-setup.ps1`** - Creates seed volume with OAuth configuration

```powershell
.\scripts\1-seed-setup.ps1

# Force recreate (overwrites existing seed)
.\scripts\1-seed-setup.ps1 -Force
```

**What it does:**
- Creates `hermes_seed_data` volume
- Runs interactive Hermes setup (OAuth, API keys, MCP servers)
- Initializes `hermes-state.json` tracking file

**When to use:**
- First time setup
- Updating OAuth credentials/API credential injection path
- Changing base configuration

---

### 2. Spawn Containers

**`2-spawn-containers.ps1`** - Creates new containers

**Parameters:**
- `-Count <number>` - Number of containers to spawn (default: 1)
- `-StartId <number>` - Override starting container ID (optional)
- `-Force` - Skip port availability check

**Volume Reuse (Automatic):**
- If a volume already exists (from `-KeepVolumes`), it will be automatically reused
- Preserves all data: configs, memories, skills, work history
- Only copies from seed if volume doesn't exist

**Examples:**

```powershell
# Spawn 5 containers
.\scripts\2-spawn-containers.ps1 -Count 5

# Spawn 10 containers
.\scripts\2-spawn-containers.ps1 -Count 10

# Skip confirmation
.\scripts\2-spawn-containers.ps1 -Count 3 -Force

# Respawn with preserved data (reuses existing volume)
.\scripts\2-spawn-containers.ps1 -Count 1 -StartId 3

# Custom starting ID (advanced)
.\scripts\2-spawn-containers.ps1 -Count 2 -StartId 10
```

**Output:**
```
Successfully spawned 3 container(s):

+----+--------------+----------+----------------+
| ID | Name         | API Port | Dashboard Port |
+----+--------------+----------+----------------+
| C1 | hermes-c1    | 8642     | 9119           |
| C2 | hermes-c2    | 8643     | 9120           |
| C3 | hermes-c3    | 8644     | 9121           |
+----+--------------+----------+----------------+

API Keys:
  - hermes-c1: hermes123456
  - hermes-c2: hermes123456
  - hermes-c3: hermes123456

Access dashboards:
  - http://localhost:8642 (hermes-c1)
  - http://localhost:8643 (hermes-c2)
  - http://localhost:8644 (hermes-c3)
```

---

### 3. List Containers

**`3-list-containers.ps1`** - Shows all containers with status

```powershell
.\scripts\3-list-containers.ps1
```

**Output:**
```
Seed Volume: hermes_seed_data [OK]
Next Container ID: 6

Active Containers:
+----+--------------+----------+----------+----------------+------------+
| ID | Name         | Status   | API Port | Dashboard Port | Created    |
+----+--------------+----------+----------+----------------+------------+
| C1 | hermes-c1    | running  | 8642     | 9119           | 2d ago     |
| C2 | hermes-c2    | running  | 8643     | 9120           | 2d ago     |
| C3 | hermes-c3    | stopped  | 8644     | 9121           | 1d ago     |
+----+--------------+----------+----------+----------------+------------+

Total: 3 containers (2 running, 1 stopped)
```

---

### 4. Stop Containers

**`4-stop-containers.ps1`** - Stops containers (preserves data)

**Parameters:**
- `-ContainerId <ids>` - Specific container(s)
- `-Range <start-end>` - Range of containers
- `-All` - All containers

**Examples:**

```powershell
# Stop single container
.\scripts\4-stop-containers.ps1 -ContainerId 1

# Stop multiple containers
.\scripts\4-stop-containers.ps1 -ContainerId 1,2,3

# Stop range
.\scripts\4-stop-containers.ps1 -Range 1-5

# Stop all
.\scripts\4-stop-containers.ps1 -All
```

**Note:** Data is preserved. Restart with `docker start hermes-cN` or use script 6.

---

### 5. Remove Containers

**`5-remove-containers.ps1`** - Permanently removes containers

**Parameters:**
- `-ContainerId <ids>` - Specific container(s)
- `-Range <start-end>` - Range of containers
- `-All` - All containers
- `-KeepVolumes` - Preserve data volumes

**Examples:**

```powershell
# Remove container and data (requires typing 'DELETE')
.\scripts\5-remove-containers.ps1 -ContainerId 3

# Remove but keep data volume
.\scripts\5-remove-containers.ps1 -ContainerId 3 -KeepVolumes

# Remove multiple
.\scripts\5-remove-containers.ps1 -ContainerId 2,4,6

# Remove range
.\scripts\5-remove-containers.ps1 -Range 1-5

# Remove all (requires extra confirmation)
.\scripts\5-remove-containers.ps1 -All
```

**⚠️ WARNING:** Without `-KeepVolumes`, all data is permanently deleted!

---

### 6. Restart Containers

**`6-restart-containers.ps1`** - Restarts containers (with optional API key update)

**Parameters:**
- `-ContainerId <ids>` - Specific container(s)
- `-Range <start-end>` - Range of containers
- `-All` - All containers
- `-UpdateKeys` - Update API keys from .env (recreates container, preserves data)

**Examples:**

```powershell
# Simple restart
.\scripts\6-restart-containers.ps1 -ContainerId 1

# Restart multiple
.\scripts\6-restart-containers.ps1 -ContainerId 1,2,3

# Restart range
.\scripts\6-restart-containers.ps1 -Range 1-5

# Restart all
.\scripts\6-restart-containers.ps1 -All

# Update API key from .env and restart
.\scripts\6-restart-containers.ps1 -ContainerId 3 -UpdateKeys

# Update all containers with new keys
.\scripts\6-restart-containers.ps1 -All -UpdateKeys
```

**What `-UpdateKeys` does:**
1. Reads API key from `.env` file
2. Stops and removes old container
3. Creates new container with updated key
4. **Preserves data volume** (no data loss!)
5. Updates state file

---

## API Key Management

API keys control access to each container's API server.

### Configuration File

Edit `C:\Users\eee_j\Documents\Personal_Agents\hermes\.env`:

```env
# Default key for all containers
DEFAULT_API_KEY=hermes123456

# Per-container keys (optional, overrides default)
CONTAINER_C1_API_KEY=prod_key_001
CONTAINER_C2_API_KEY=prod_key_002
CONTAINER_C3_API_KEY=prod_key_003
```

### Priority

```
CONTAINER_C{N}_API_KEY  →  DEFAULT_API_KEY  →  hermes123456
   (per-container)           (fallback)         (hardcoded)
```

### Updating API Keys

**Method 1: Update and restart (recommended)**

```powershell
# 1. Edit .env
notepad .env

# 2. Update key
CONTAINER_C3_API_KEY=new_secure_key_here

# 3. Restart with update (preserves data!)
.\scripts\6-restart-containers.ps1 -ContainerId 3 -UpdateKeys
```

**Method 2: Recreate container**

```powershell
# 1. Edit .env
notepad .env

# 2. Remove container (keep volume)
.\scripts\5-remove-containers.ps1 -ContainerId 3 -KeepVolumes

# 3. Respawn (reuses existing volume)
.\scripts\2-spawn-containers.ps1 -Count 1 -StartId 3
```

### Using API Keys

```bash
# Example API call
curl -H "Authorization: Bearer hermes123456" \
  http://localhost:8642/api/chat \
  -d '{"message":"Hello"}'
```

---

## Common Workflows

### Workflow 1: Initial Deployment

```powershell
# Step 1: Create seed with OAuth
.\scripts\1-seed-setup.ps1

# Step 2: Spawn 5 containers
.\scripts\2-spawn-containers.ps1 -Count 5

# Step 3: Verify running
.\scripts\3-list-containers.ps1

# Step 4: Access dashboards
# http://localhost:8642, 8643, 8644, 8645, 8646
```

### Workflow 2: Scale Up

```powershell
# Check current containers
.\scripts\3-list-containers.ps1

# Spawn 5 more (will be C6-C10 if C1-C5 exist)
.\scripts\2-spawn-containers.ps1 -Count 5

# Verify
.\scripts\3-list-containers.ps1
```

### Workflow 3: API Key Rotation

```powershell
# Edit .env file
notepad .env

# Change: CONTAINER_C1_API_KEY=new_secure_key

# Restart with updated key (no data loss)
.\scripts\6-restart-containers.ps1 -ContainerId 1 -UpdateKeys

# Verify
.\scripts\3-list-containers.ps1
```

### Workflow 4: Maintenance Window

```powershell
# Stop containers for maintenance
.\scripts\4-stop-containers.ps1 -Range 1-5

# Perform maintenance...

# Restart containers
.\scripts\6-restart-containers.ps1 -Range 1-5
```

### Workflow 5: Clean Rebuild

```powershell
# Remove container but keep data
.\scripts\5-remove-containers.ps1 -ContainerId 3 -KeepVolumes

# Edit .env if needed
notepad .env

# Respawn with same ID (reuses existing volume)
.\scripts\2-spawn-containers.ps1 -Count 1 -StartId 3
```

---

## Troubleshooting

### "State file not found"

**Cause:** No seed setup completed  
**Fix:** Run `.\scripts\1-seed-setup.ps1`

### "Seed volume not found"

**Cause:** Seed was deleted or never created  
**Fix:** Run `.\scripts\1-seed-setup.ps1`

### "Port already in use"

**Cause:** Another process is using the port  
**Fix:**
```powershell
# Find process using port 8642
netstat -ano | findstr "8642"

# Kill process or use different port
# Or skip check: -Force flag
```

### Container Won't Start

**Check logs:**
```powershell
docker logs hermes-c1
docker logs -f hermes-c1  # Follow logs
```

**Common fixes:**
```powershell
# Restart
.\scripts\6-restart-containers.ps1 -ContainerId 1

# Or recreate
.\scripts\5-remove-containers.ps1 -ContainerId 1 -KeepVolumes
.\scripts\2-spawn-containers.ps1 -Count 1 -StartId 1
```

### API Key Not Updating

**Cause:** .env file not found or wrong path  
**Verify:**
```powershell
Test-Path C:\Users\eee_j\Documents\Personal_Agents\hermes\.env
Get-Content .env
```

**Fix:** Ensure .env file exists in project root, then:
```powershell
.\scripts\6-restart-containers.ps1 -ContainerId 3 -UpdateKeys
```

### Permission Errors During Spawn

**Cause:** Volume permission issues  
**Fix:** Already handled by scripts (uses alpine container as root)

---

## Advanced Usage

### View Container Logs

```powershell
# View logs
docker logs hermes-c1

# Follow logs (live)
docker logs -f hermes-c1

# Last 100 lines
docker logs --tail 100 hermes-c1
```

### Execute Commands Inside Container

```powershell
# Interactive shell
docker exec -it hermes-c1 bash

# Single command
docker exec hermes-c1 hermes config edit

# Check Hermes version
docker exec hermes-c1 hermes --version
```

### Backup Container Data

```powershell
# Backup volume to tar file
docker run --rm -v hermes_c1_data:/data -v ${PWD}:/backup alpine tar czf /backup/hermes-c1-backup.tar.gz -C /data .

# Restore from backup
docker run --rm -v hermes_c1_data:/data -v ${PWD}:/backup alpine tar xzf /backup/hermes-c1-backup.tar.gz -C /data
```

### Inspect Volume Contents

```powershell
# List files in volume
docker run --rm -v hermes_c1_data:/data alpine ls -la /data

# View config file
docker run --rm -v hermes_c1_data:/data alpine cat /data/config.yaml

# View OAuth tokens (be careful!)
docker run --rm -v hermes_c1_data:/data alpine cat /data/auth.json
```

### Manual Docker Operations

```powershell
# List all Hermes containers
docker ps -a --filter "name=hermes-c"

# List all Hermes volumes
docker volume ls --filter "name=hermes_"

# Stop all Hermes containers
docker stop $(docker ps -q --filter "name=hermes-c")

# Remove all stopped Hermes containers
docker rm $(docker ps -aq --filter "name=hermes-c" --filter "status=exited")
```

---

## Files & Structure

```
hermes/
├── .env                       # API key configuration
├── hermes-state.json          # Container tracking (auto-created)
├── README.md                  # This file
├── scripts/
│   ├── 1-seed-setup.ps1      # Initial OAuth setup
│   ├── 2-spawn-containers.ps1 # Create containers
│   ├── 3-list-containers.ps1  # List status
│   ├── 4-stop-containers.ps1  # Stop containers
│   ├── 5-remove-containers.ps1 # Remove containers
│   ├── 6-restart-containers.ps1 # Restart containers
│   └── utils/
│       ├── state-manager.ps1  # State file operations
│       ├── port-manager.ps1   # Port allocation
│       └── docker-helpers.ps1 # Docker wrappers
```

---

## Quick Reference Card

```powershell
# SETUP
.\scripts\1-seed-setup.ps1

# SPAWN
.\scripts\2-spawn-containers.ps1 -Count 5

# LIST
.\scripts\3-list-containers.ps1

# STOP
.\scripts\4-stop-containers.ps1 -ContainerId 1,2,3
.\scripts\4-stop-containers.ps1 -Range 1-5
.\scripts\4-stop-containers.ps1 -All

# RESTART
.\scripts\6-restart-containers.ps1 -ContainerId 1
.\scripts\6-restart-containers.ps1 -ContainerId 3 -UpdateKeys

# REMOVE
.\scripts\5-remove-containers.ps1 -ContainerId 1
.\scripts\5-remove-containers.ps1 -ContainerId 1 -KeepVolumes
```

---

## Tips & Best Practices

✅ **Always check status first** - Run `3-list-containers.ps1` before operations  
✅ **Use -KeepVolumes** when removing - Preserve data for recovery  
✅ **Backup important containers** - Use volume backup commands  
✅ **Use -UpdateKeys for API rotation** - Safe way to update keys  
✅ **Monitor container logs** - `docker logs hermes-cN`  
✅ **Test with small batches** - Spawn 2-3 containers first  
✅ **Don't mix parameters** - Use ONE of: -ContainerId, -Range, or -All  

❌ **Don't delete seed volume** - It's your golden template  
❌ **Don't manually edit state.json** - Use scripts instead  
❌ **Don't remove without -KeepVolumes** unless sure - Data loss is permanent  

---

## Support

For issues:
1. Check [Troubleshooting](#troubleshooting) section
2. View container logs: `docker logs hermes-cN`
3. Check Docker status: `docker ps -a`
4. Verify .env file: `Get-Content .env`

---

**Version:** 1.0  
**Last Updated:** 2026-05-16  
**Docker Image:** nousresearch/hermes-agent
