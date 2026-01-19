# Complete Guide - Offline Workloads for OpenShift

**A comprehensive guide covering everything you need to know about deploying, running, and monitoring offline workloads on OpenShift.**

> **Important**: This is the workloads repository. All commands in this guide should be run from the root of this repository (the workloads directory). The repository is self-contained and does not require navigating to any parent directories.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Available Workloads](#available-workloads)
5. [Deployment](#deployment)
6. [Running Workloads](#running-workloads)
7. [Monitoring Workloads](#monitoring-workloads)
8. [Thanos Metrics](#thanos-metrics)
9. [Customization](#customization)
10. [Troubleshooting](#troubleshooting)
11. [Complete CLI Reference](#complete-cli-reference)
12. [File Structure](#file-structure)

---

## Overview

These workloads run entirely within your OpenShift cluster with **no external dependencies**. They use only the `busybox` image which is typically cached in most clusters.

### Features

- ✅ **100% Offline** - No internet access required
- ✅ **Lightweight** - Uses only `busybox:latest` image
- ✅ **Simple** - Easy to deploy and manage
- ✅ **Resource Efficient** - Configurable CPU and memory limits
- ✅ **Self-Contained** - All files and documentation in this directory

### What These Workloads Do

These workloads generate CPU, memory, I/O, and network activity to test and validate your OpenShift cluster's resource management, monitoring, and observability capabilities.

---

## Prerequisites

Before you begin, ensure you have:

1. **Access to an OpenShift cluster**
2. **OpenShift CLI (`oc`) installed**
   ```bash
   oc version
   ```
3. **Cluster admin or namespace admin permissions**
4. **Logged in to OpenShift**
   ```bash
   oc whoami
   ```
   If not logged in, see [Login Instructions](#login-to-openshift) below.

5. **Optional but recommended: `jq` installed** (for better JSON parsing)
   ```bash
   # On macOS
   brew install jq
   
   # On Linux (RHEL/CentOS)
   sudo yum install jq
   
   # On Linux (Ubuntu/Debian)
   sudo apt-get install jq
   ```

---

## Quick Start

### Complete Setup from Login

```bash
# Step 1: Login to OpenShift
oc login <your-openshift-api-url> -u <username> -p <password>

# Step 2: Run complete setup (from workloads directory)
chmod +x complete-setup.sh
./complete-setup.sh

# Step 3: Run workloads
./run-workload.sh all

# Step 4: Monitor
./status.sh
```

### Quick Workflow

```bash
# Complete workflow in one go (run from workloads directory)
oc login <api-url> -u <user> -p <pass>
./complete-setup.sh
./run-workload.sh all
./status.sh
```

---

## Available Workloads

This directory contains 5 offline workloads:

### 1. Simple CPU Workload (`workloads/simple-cpu-workload.yaml`)
- **Purpose**: CPU-intensive stress test
- **Resources**: CPU 100m-500m, Memory 64Mi-128Mi
- **Duration**: 15 minutes
- **Schedule**: Every 2 hours

### 2. Simple Memory Workload (`workloads/simple-memory-workload.yaml`)
- **Purpose**: Memory-intensive stress test
- **Resources**: CPU 50m-200m, Memory 128Mi-512Mi
- **Duration**: 15 minutes
- **Schedule**: Every 2 hours

### 3. File I/O Workload (`workloads/file-io-workload.yaml`)
- **Purpose**: File I/O operations
- **Resources**: CPU 50m-200m, Memory 64Mi-128Mi
- **Duration**: 15 minutes
- **Schedule**: Every 2 hours

### 4. Network Workload (`workloads/network-workload.yaml`)
- **Purpose**: Network traffic generation
- **Resources**: CPU 50m-200m, Memory 64Mi-128Mi
- **Duration**: 15 minutes
- **Schedule**: Every 2 hours

### 5. Combined Workload (`workloads/combined-workload.yaml`)
- **Purpose**: Combined CPU, memory, and I/O
- **Resources**: CPU 100m-500m, Memory 128Mi-512Mi
- **Duration**: 15 minutes
- **Schedule**: Every 2 hours

---

## Deployment

### Option 1: Complete Setup Script (Recommended)

```bash
chmod +x complete-setup.sh
./complete-setup.sh
```

This script will:
- ✅ Check if you're logged in to OpenShift
- ✅ Create the namespace (`offline-workload`)
- ✅ Deploy all CronJobs
- ✅ Verify deployment

### Option 2: Deploy All Workloads

```bash
./deploy-offline-workloads.sh
```

### Option 3: Manual Deployment

```bash
# Create namespace
oc create namespace offline-workload

# Deploy all CronJobs
oc apply -f workloads/simple-cpu-workload.yaml
oc apply -f workloads/simple-memory-workload.yaml
oc apply -f workloads/file-io-workload.yaml
oc apply -f workloads/network-workload.yaml
oc apply -f workloads/combined-workload.yaml

# Verify deployment
oc get cronjobs -n offline-workload
```

---

## Running Workloads

### Using Scripts

```bash
# Run all workloads
./run-workload.sh all

# Run specific workload
./run-workload.sh cpu
./run-workload.sh memory
./run-workload.sh io
./run-workload.sh network
./run-workload.sh combined
```

### Manual CLI Commands

```bash
# CPU workload
oc create job --from=cronjob/simple-cpu-workload cpu-test-$(date +%s) -n offline-workload

# Memory workload
oc create job --from=cronjob/simple-memory-workload memory-test-$(date +%s) -n offline-workload

# File I/O workload
oc create job --from=cronjob/file-io-workload io-test-$(date +%s) -n offline-workload

# Network workload
oc create job --from=cronjob/network-workload network-test-$(date +%s) -n offline-workload

# Combined workload
oc create job --from=cronjob/combined-workload combined-test-$(date +%s) -n offline-workload

# Run all at once
oc create job --from=cronjob/simple-cpu-workload cpu-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/simple-memory-workload memory-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/file-io-workload io-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/network-workload network-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/combined-workload combined-test-$(date +%s) -n offline-workload
```

---

## Monitoring Workloads

### Using Scripts

```bash
./status.sh
```

### Manual CLI Commands

```bash
# View CronJobs
oc get cronjobs -n offline-workload

# View Jobs
oc get jobs -n offline-workload

# View Pods
oc get pods -n offline-workload

# View resource usage
oc top pods -n offline-workload

# Watch pods in real-time
oc get pods -n offline-workload -w

# Get all resources
oc get all -n offline-workload
```

### View Logs

```bash
# View logs for a specific pod
oc logs <pod-name> -n offline-workload

# View logs for a specific job
oc logs -l job-name=<job-name> -n offline-workload

# View logs for CPU workloads
oc logs -f -n offline-workload -l app=simple-cpu

# View logs for Memory workloads
oc logs -f -n offline-workload -l app=simple-memory

# View logs for all running pods
oc get pods -n offline-workload -o name | xargs -I {} oc logs {} -n offline-workload
```

### Monitor in Real-Time

```bash
# Watch pods
oc get pods -n offline-workload -w

# Watch jobs
oc get jobs -n offline-workload -w

# Watch resource usage
watch -n 2 'oc top pods -n offline-workload'
```

---

## Thanos Metrics

### Check Thanos Metrics (Existing Workloads)

The `check-thanos-metrics.sh` script verifies workloads and queries Thanos for metrics.

#### Overview

The script:
- Verifies that workloads are deployed and running
- Checks if namespace, CronJobs, Jobs, and Pods exist
- Queries Thanos for CPU and memory utilization metrics
- Displays current values and time series data for the last 4 hours

#### Usage

```bash
./check-thanos-metrics.sh
```

#### What It Queries

**6 metrics** for the namespace:

**CPU Metrics (3 metrics):**
- `acm_rs:namespace:cpu_request` - Sum of all CPU requests
- `acm_rs:namespace:cpu_usage` - Actual CPU usage
- `acm_rs:namespace:cpu_recommendation` - Recommended CPU allocation

**Memory Metrics (3 metrics):**
- `acm_rs:namespace:memory_request` - Sum of all memory requests
- `acm_rs:namespace:memory_usage` - Actual memory usage
- `acm_rs:namespace:memory_recommendation` - Recommended memory allocation

#### Output

The script displays:
- Current values for all 6 metrics (formatted and raw)
- Time series data for all 6 metrics (last 4 hours, 5-minute intervals)
- Comprehensive summary table with status indicators
- Detailed values table showing both formatted and raw values

### Test Thanos Metrics (Deploy, Wait, Query)

The `test-thanos-metrics.sh` script deploys workloads, waits 20 minutes, and then queries Thanos.

#### Overview

The script:
1. Deploys all offline workloads
2. Triggers workloads immediately
3. Waits 20 minutes for metrics to accumulate
4. Queries Thanos for 8 metrics:
   - `acm_rs:namespace:cpu_request_hard`
   - `acm_rs:namespace:cpu_request`
   - `acm_rs:namespace:cpu_usage`
   - `acm_rs:namespace:cpu_recommendation`
   - `acm_rs:namespace:memory_request_hard`
   - `acm_rs:namespace:memory_request`
   - `acm_rs:namespace:memory_usage`
   - `acm_rs:namespace:memory_recommendation`
5. Displays current values and time series data

#### Usage

```bash
./test-thanos-metrics.sh
```

#### What It Does

1. **Deployment Phase**: Creates namespace, deploys all 5 CronJobs, triggers jobs immediately
2. **Waiting Phase**: Waits exactly 20 minutes with progress bar
3. **Query Phase**: Automatically detects Thanos endpoint, queries all 8 metrics
4. **Output Phase**: Displays current values, time series data, and summary table

### Manual Thanos Queries

#### Setup Port-Forward

```bash
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
```

#### Query Current Value

```bash
TOKEN=$(oc whoami -t)

curl -k -G \
  --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:9091/api/v1/query"
```

#### Query Time Series (Last 4 Hours)

```bash
TOKEN=$(oc whoami -t)
END_TIME=$(date +%s)
START_TIME=$((END_TIME - 14400))  # 4 hours ago

curl -k -G \
  --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "step=300" \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:9091/api/v1/query_range"
```

---

## Customization

### Modify CPU and Memory Values

#### Method 1: Edit YAML Files (Recommended)

1. Open the workload YAML file (e.g., `workloads/simple-cpu-workload.yaml`)
2. Locate the `resources` section:

```yaml
resources:
  requests:
    cpu: "100m"      # Change this value
    memory: "64Mi"  # Change this value
  limits:
    cpu: "500m"      # Change this value
    memory: "128Mi"  # Change this value
```

3. Modify the values as needed:
   - CPU values: Use `m` for millicores (e.g., `"100m"` = 0.1 cores, `"500m"` = 0.5 cores)
   - Memory values: Use `Mi` for megabytes or `Gi` for gigabytes (e.g., `"64Mi"`, `"128Mi"`, `"1Gi"`)

4. Apply the changes:

```bash
oc apply -f workloads/simple-cpu-workload.yaml
```

#### Method 2: Use `oc patch` Command

```bash
# Update CPU request
oc patch cronjob simple-cpu-workload -n offline-workload --type='json' -p='[
  {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"}
]'

# Update CPU limit
oc patch cronjob simple-cpu-workload -n offline-workload --type='json' -p='[
  {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/limits/cpu", "value": "1000m"}
]'

# Update memory request
oc patch cronjob simple-cpu-workload -n offline-workload --type='json' -p='[
  {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/requests/memory", "value": "128Mi"}
]'

# Update memory limit
oc patch cronjob simple-cpu-workload -n offline-workload --type='json' -p='[
  {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/limits/memory", "value": "256Mi"}
]'
```

#### Method 3: Use `oc edit` Command

```bash
oc edit cronjob simple-cpu-workload -n offline-workload
```

This opens the CronJob in your default editor. Find the `resources` section and modify the values, then save and exit.

### Resource Value Examples

**Low Resource Configuration:**
```yaml
resources:
  requests:
    cpu: "50m"
    memory: "32Mi"
  limits:
    cpu: "200m"
    memory: "64Mi"
```

**Medium Resource Configuration (Default):**
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "128Mi"
```

**High Resource Configuration:**
```yaml
resources:
  requests:
    cpu: "200m"
    memory: "128Mi"
  limits:
    cpu: "1000m"
    memory: "256Mi"
```

### Change Schedule

All workloads are scheduled to run **every 2 hours** by default. To change the schedule, edit the `schedule` field in the YAML files:

- `"0 */2 * * *"` - Every 2 hours (current)
- `"0 * * * *"` - Every hour
- `"*/30 * * * *"` - Every 30 minutes
- `"0 9 * * 1-5"` - Every weekday at 9 AM

### Change Duration

Edit the `timeout` value in the command section:

```yaml
timeout 900  # 900 seconds = 15 minutes
timeout 600  # 600 seconds = 10 minutes
```

### Change CPU Intensity

For CPU workloads, edit the loop count in the command section:

```yaml
while [ $i -lt 100000 ]; do  # Increase 100000 for more CPU stress
```

### Change Memory Allocation Size

For memory workloads, edit the `MEM_SIZE` variable:

```yaml
MEM_SIZE=256  # Change this value (in MB)
```

---

## Troubleshooting

### Login to OpenShift

If you're not logged in:

```bash
# Method 1: Interactive login (recommended)
oc login <your-openshift-api-url>

# Method 2: With username and password
oc login <your-openshift-api-url> -u <username> -p <password>

# Method 3: With token
oc login <your-openshift-api-url> --token=<your-token>
```

**Verify login:**
```bash
oc whoami
oc config current-context
```

### Jobs Not Starting

```bash
# Check CronJob status
oc describe cronjob <cronjob-name> -n offline-workload

# Check for resource quotas
oc describe quota -n offline-workload

# Check if CronJob is suspended
oc get cronjob <cronjob-name> -n offline-workload -o jsonpath='{.spec.suspend}'
```

### Pods Failing

```bash
# Check pod events
oc describe pod <pod-name> -n offline-workload

# Check pod logs
oc logs <pod-name> -n offline-workload

# Check pod status
oc get pods -n offline-workload
```

### Image Pull Errors

The workloads use `busybox:latest` which should be available in most clusters. If you get image pull errors:

```bash
# Check if image is available
oc run test-pod --image=busybox:latest --rm -it --restart=Never -n offline-workload -- /bin/sh
```

### Insufficient Resources

```bash
# Check available resources
oc describe nodes
oc top nodes

# Reduce resource requests/limits in the YAML files
```

### Cannot Connect to Thanos

If you see connection errors:

1. **Check Thanos Query Service:**
   ```bash
   oc get svc -n openshift-monitoring thanos-querier
   ```

2. **Check Route:**
   ```bash
   oc get route -n openshift-monitoring thanos-querier
   ```

3. **Manual Port-Forward:**
   ```bash
   oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
   ```

4. **Check Permissions:**
   ```bash
   oc auth can-i get pods -n openshift-monitoring
   oc auth can-i get routes -n openshift-monitoring
   ```

### No Metrics Found

If metrics show "N/A":

1. **Verify Namespace:**
   ```bash
   oc get namespace offline-workload
   ```

2. **Check if Workloads are Running:**
   ```bash
   oc get pods -n offline-workload
   oc get jobs -n offline-workload
   ```

3. **Wait for Metrics**: Metrics may take time to propagate to Thanos

4. **Verify Metric Names**: The metric names must match exactly

### Permission Denied (Scripts)

```bash
chmod +x check-thanos-metrics.sh
chmod +x test-thanos-metrics.sh
chmod +x complete-setup.sh
chmod +x deploy-offline-workloads.sh
chmod +x run-workload.sh
chmod +x status.sh
chmod +x cleanup.sh
```

---

## Complete CLI Reference

### Login to OpenShift Cluster

```bash
# Method 1: Interactive login (recommended)
oc login <your-openshift-api-url>

# Method 2: With username and password
oc login <your-openshift-api-url> -u <username> -p <password>

# Method 3: With token
oc login <your-openshift-api-url> --token=<your-token>

# Verify login
oc whoami
oc config current-context
```

### Deploy Workloads

```bash
# Create namespace
oc create namespace offline-workload

# Deploy all CronJobs
oc apply -f workloads/simple-cpu-workload.yaml
oc apply -f workloads/simple-memory-workload.yaml
oc apply -f workloads/file-io-workload.yaml
oc apply -f workloads/network-workload.yaml
oc apply -f workloads/combined-workload.yaml

# Verify deployment
oc get cronjobs -n offline-workload
```

### Run Workloads

```bash
# Run CPU workload
oc create job --from=cronjob/simple-cpu-workload cpu-test-$(date +%s) -n offline-workload

# Run Memory workload
oc create job --from=cronjob/simple-memory-workload memory-test-$(date +%s) -n offline-workload

# Run File I/O workload
oc create job --from=cronjob/file-io-workload io-test-$(date +%s) -n offline-workload

# Run Network workload
oc create job --from=cronjob/network-workload network-test-$(date +%s) -n offline-workload

# Run Combined workload
oc create job --from=cronjob/combined-workload combined-test-$(date +%s) -n offline-workload
```

### Monitor Workloads

```bash
# Check CronJobs
oc get cronjobs -n offline-workload

# Check Jobs
oc get jobs -n offline-workload

# Check Pods
oc get pods -n offline-workload

# Watch pods in real-time
oc get pods -n offline-workload -w

# Check resource usage
oc top pods -n offline-workload

# Get all resources
oc get all -n offline-workload
```

### View Logs

```bash
# View logs for a specific pod
oc logs <pod-name> -n offline-workload

# View logs for a specific job
oc logs -l job-name=<job-name> -n offline-workload

# View logs for CPU workloads
oc logs -f -n offline-workload -l app=simple-cpu

# View logs for Memory workloads
oc logs -f -n offline-workload -l app=simple-memory

# View logs for all running pods
oc get pods -n offline-workload -o name | xargs -I {} oc logs {} -n offline-workload
```

### Stop Workloads

```bash
# Suspend CronJob (stop scheduling)
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":true}}'

# Resume CronJob
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":false}}'

# Delete running jobs
oc delete jobs --all -n offline-workload

# Delete specific job
oc delete job <job-name> -n offline-workload
```

### Clean Up

```bash
# Delete all jobs
oc delete jobs --all -n offline-workload

# Delete all CronJobs
oc delete cronjobs --all -n offline-workload

# Delete all pods
oc delete pods --all -n offline-workload

# Delete namespace (removes everything)
oc delete namespace offline-workload
```

### Useful One-Liners

```bash
# Get all workloads status
oc get cronjobs,jobs,pods -n offline-workload

# Get running workloads
oc get pods -n offline-workload | grep Running

# Get completed workloads
oc get jobs -n offline-workload | grep Complete

# Get logs from all running pods
oc get pods -n offline-workload -o name | xargs -I {} oc logs {} -n offline-workload

# Describe a specific workload
oc describe cronjob simple-cpu-workload -n offline-workload

# Get events for troubleshooting
oc get events -n offline-workload --sort-by='.lastTimestamp' | tail -20

# Count running pods
oc get pods -n offline-workload --field-selector=status.phase=Running --no-headers | wc -l

# List all job names
oc get jobs -n offline-workload -o jsonpath='{.items[*].metadata.name}'

# Get last schedule time
oc get cronjob simple-cpu-workload -n offline-workload -o jsonpath='{.status.lastScheduleTime}'

# Get resource requests
oc get cronjob simple-cpu-workload -n offline-workload -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].resources}'
```

### Troubleshooting Commands

```bash
# Check if logged in
oc whoami

# Check current context
oc config current-context

# List all contexts
oc config get-contexts

# Switch context
oc config use-context <context-name>

# Check namespace exists
oc get namespace offline-workload

# Check CronJob details
oc describe cronjob simple-cpu-workload -n offline-workload

# Check pod events
oc get events -n offline-workload --sort-by='.lastTimestamp' | tail -20

# Check pod status
oc describe pod <pod-name> -n offline-workload
```

---

## File Structure

This repository is self-contained. All files are in the workloads directory:

```
.
├── docs/
│   ├── COMPLETE-GUIDE.md          # This comprehensive guide
│   ├── README.md                   # Overview and quick start
│   ├── START-HERE.md               # Quick start guide from login
│   ├── CLI-COMMANDS.md             # Complete CLI commands reference
│   ├── QUICK-REFERENCE.md          # Quick command reference
│   ├── CHECK-THANOS-METRICS.md    # Check Thanos metrics guide
│   └── TEST-THANOS-METRICS.md    # Test Thanos metrics guide
├── workloads/
│   ├── simple-cpu-workload.yaml    # CPU workload CronJob
│   ├── simple-memory-workload.yaml # Memory workload CronJob
│   ├── file-io-workload.yaml      # File I/O workload CronJob
│   ├── network-workload.yaml      # Network workload CronJob
│   └── combined-workload.yaml     # Combined workload CronJob
├── check-thanos-metrics.sh         # Check existing Thanos metrics
├── test-thanos-metrics.sh         # Deploy, wait, query Thanos metrics
├── complete-setup.sh              # Complete setup script
├── deploy-offline-workloads.sh    # Deploy workloads script
├── run-workload.sh                # Run workloads script
├── status.sh                      # Check status script
└── cleanup.sh                     # Clean up script
```

**Note**: All commands should be run from this directory (the workloads repository root).

---

## Summary

This guide covers everything you need to:

1. ✅ **Deploy** offline workloads to OpenShift
2. ✅ **Run** workloads manually or on schedule
3. ✅ **Monitor** workloads and view logs
4. ✅ **Query** Thanos for metrics
5. ✅ **Customize** resource limits and schedules
6. ✅ **Troubleshoot** common issues
7. ✅ **Use** all available CLI commands

### Quick Reference

- **Deploy**: `./complete-setup.sh`
- **Run**: `./run-workload.sh all`
- **Monitor**: `./status.sh`
- **Check Metrics**: `./check-thanos-metrics.sh`
- **Test Metrics**: `./test-thanos-metrics.sh`
- **Clean Up**: `./cleanup.sh`

### Notes

- All workloads use the `busybox:latest` image
- Workloads run entirely within the cluster
- No external network access required
- Suitable for air-gapped environments
- Minimal resource footprint
- All files and documentation are self-contained

---

**For more specific information, refer to the individual documentation files in the `docs/` directory.**
