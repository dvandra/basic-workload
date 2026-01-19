# 🚀 Quick Start Guide - Offline Workloads

Welcome! This guide will help you get started with offline workloads in just a few minutes.

## Prerequisites

- Access to an OpenShift cluster
- `oc` CLI tool installed
- Cluster admin or namespace admin permissions

## Complete Setup from Login

### Step 1: Login to OpenShift

```bash
oc login <your-openshift-api-url> -u <username> -p <password>
```

**Verify login:**
```bash
oc whoami
```

### Step 2: Navigate to Workloads Directory

```bash
cd workloads
```

### Step 3: Run Complete Setup

```bash
chmod +x complete-setup.sh
./complete-setup.sh
```

This script will:
- ✅ Check if you're logged in
- ✅ Create the namespace (`offline-workload`)
- ✅ Deploy all CronJobs
- ✅ Verify deployment

### Step 4: Run Workloads

```bash
# Run all workloads
./run-workload.sh all

# Or run specific workload
./run-workload.sh cpu
./run-workload.sh memory
./run-workload.sh io
./run-workload.sh network
./run-workload.sh combined
```

### Step 5: Monitor

```bash
# Check status
./status.sh

# Or manually
oc get pods -n offline-workload
oc top pods -n offline-workload

# View logs
oc logs -f -n offline-workload -l app=simple-cpu
```

## Available Workloads

This directory contains 5 offline workloads:

1. **Simple CPU Workload** (`simple-cpu-workload.yaml`)
   - CPU-intensive stress test
   - Resources: CPU 100m-500m, Memory 64Mi-128Mi

2. **Simple Memory Workload** (`simple-memory-workload.yaml`)
   - Memory-intensive stress test
   - Resources: CPU 50m-200m, Memory 128Mi-512Mi

3. **File I/O Workload** (`file-io-workload.yaml`)
   - File I/O operations
   - Resources: CPU 50m-200m, Memory 64Mi-128Mi

4. **Network Workload** (`network-workload.yaml`)
   - Network traffic generation
   - Resources: CPU 50m-200m, Memory 64Mi-128Mi

5. **Combined Workload** (`combined-workload.yaml`)
   - Combined CPU, memory, and I/O
   - Resources: CPU 100m-500m, Memory 128Mi-512Mi

## Quick Reference

### Deploy Individual Workload

```bash
# Example: Deploy CPU workload
oc create namespace offline-workload
oc apply -f simple-cpu-workload.yaml
```

### Modify CPU and Memory

1. Edit the YAML file (e.g., `simple-cpu-workload.yaml`)
2. Find the `resources` section
3. Modify CPU/memory values
4. Apply: `oc apply -f simple-cpu-workload.yaml`

For detailed instructions, see **README.md** section "Modify CPU and Memory Values".

### Stop Workloads

```bash
# Suspend CronJob (stop scheduling)
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":true}}'

# Delete running jobs
oc delete jobs --all -n offline-workload

# Clean up everything
./cleanup.sh
```

## 📋 All CLI Commands (Manual Method)

If you prefer to run commands manually, see:
- **CLI-COMMANDS.md** - Complete CLI commands reference
- **QUICK-REFERENCE.md** - Quick command reference

## 📁 Files in This Directory

- `complete-setup.sh` - Complete setup script (login check + deployment)
- `deploy-offline-workloads.sh` - Deploy workloads only
- `run-workload.sh` - Run workloads manually
- `status.sh` - Check status
- `cleanup.sh` - Clean up resources
- `CLI-COMMANDS.md` - Complete CLI commands reference
- `README.md` - Full documentation
- `QUICK-REFERENCE.md` - Quick command reference
- `START-HERE.md` (this file) - Quick start guide
- `*.yaml` - Workload CronJob definitions

## 🎯 Quick Workflow

```bash
# Complete workflow
oc login <api-url> -u <user> -p <pass>
cd workloads
./complete-setup.sh
./run-workload.sh all
./status.sh
```

## 📖 Documentation Files

This directory contains all the documentation you need:

- **START-HERE.md** (this file) - Quick start guide
- **README.md** - Full documentation and overview
- **CLI-COMMANDS.md** - Complete CLI commands from login
- **QUICK-REFERENCE.md** - Quick command reference

All documentation is self-contained in this directory.

## 🆘 Need Help?

1. **Quick Start**: Follow this guide (START-HERE.md)
2. **Full Documentation**: See README.md
3. **CLI Commands**: See CLI-COMMANDS.md
4. **Quick Reference**: See QUICK-REFERENCE.md
5. **Troubleshooting**: See README.md troubleshooting section

## Next Steps

1. ✅ Complete setup using `./complete-setup.sh`
2. ✅ Run workloads using `./run-workload.sh all`
3. ✅ Monitor using `./status.sh`
4. 📖 Read README.md for detailed customization options
5. 🔧 Modify CPU/memory values as needed (see README.md)
