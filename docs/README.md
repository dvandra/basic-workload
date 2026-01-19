# Offline Workloads for OpenShift

These workloads run entirely within your OpenShift cluster with **no external dependencies**. They use only the `busybox` image which is typically cached in most clusters.

## Features

- ✅ **100% Offline** - No internet access required
- ✅ **Lightweight** - Uses only `busybox:latest` image
- ✅ **Simple** - Easy to deploy and manage
- ✅ **Resource Efficient** - Configurable CPU and memory limits
- ✅ **Self-Contained** - All files and documentation in this directory

## Available Workloads

1. **Simple CPU Workload** (`workloads/simple-cpu-workload.yaml`)
   - CPU-intensive loops
   - Resources: CPU 100m-500m, Memory 64Mi-128Mi
   - Duration: 15 minutes

2. **Simple Memory Workload** (`workloads/simple-memory-workload.yaml`)
   - Memory allocation and usage
   - Resources: CPU 50m-200m, Memory 128Mi-512Mi
   - Duration: 15 minutes

3. **File I/O Workload** (`workloads/file-io-workload.yaml`)
   - File read/write operations
   - Resources: CPU 50m-200m, Memory 64Mi-128Mi
   - Duration: 15 minutes

4. **Network Workload** (`workloads/network-workload.yaml`)
   - Local network connections
   - Resources: CPU 50m-200m, Memory 64Mi-128Mi
   - Duration: 15 minutes

5. **Combined Workload** (`workloads/combined-workload.yaml`)
   - CPU, memory, and I/O simultaneously
   - Resources: CPU 100m-500m, Memory 128Mi-512Mi
   - Duration: 15 minutes

## Quick Start

### Option 1: Complete Setup Script (Recommended)

```bash
chmod +x complete-setup.sh
./complete-setup.sh
```

**Note**: Run all commands from the workloads repository directory.

This script will:
- ✅ Check if you're logged in to OpenShift
- ✅ Create the namespace (`offline-workload`)
- ✅ Deploy all CronJobs
- ✅ Verify deployment

### Option 2: Deploy All Workloads

```bash
./deploy-offline-workloads.sh
```

### Option 3: Deploy Individual Workloads

```bash
# Create namespace
oc create namespace offline-workload

# Deploy CPU workload
oc apply -f workloads/simple-cpu-workload.yaml

# Deploy Memory workload
oc apply -f workloads/simple-memory-workload.yaml

# Deploy File I/O workload
oc apply -f workloads/file-io-workload.yaml

# Deploy Network workload
oc apply -f workloads/network-workload.yaml

# Deploy Combined workload
oc apply -f workloads/combined-workload.yaml
```

## Run Workloads

### Using Scripts

```bash
# Run all workloads
./run-workload.sh all
```

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
```

## Monitor Workloads

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

# View logs
oc logs -f -n offline-workload -l app=simple-cpu
```

## Modify CPU and Memory Values

### Method 1: Edit YAML Files (Recommended)

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

### Method 2: Use `oc patch` Command

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

### Method 3: Use `oc edit` Command

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

## Stop Workloads

### Suspend CronJobs (Stop Scheduling New Jobs)

```bash
# Suspend all CronJobs
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":true}}'
oc patch cronjob simple-memory-workload -n offline-workload -p '{"spec":{"suspend":true}}'
oc patch cronjob file-io-workload -n offline-workload -p '{"spec":{"suspend":true}}'
oc patch cronjob network-workload -n offline-workload -p '{"spec":{"suspend":true}}'
oc patch cronjob combined-workload -n offline-workload -p '{"spec":{"suspend":true}}'

# Resume CronJobs
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":false}}'
oc patch cronjob simple-memory-workload -n offline-workload -p '{"spec":{"suspend":false}}'
oc patch cronjob file-io-workload -n offline-workload -p '{"spec":{"suspend":false}}'
oc patch cronjob network-workload -n offline-workload -p '{"spec":{"suspend":false}}'
oc patch cronjob combined-workload -n offline-workload -p '{"spec":{"suspend":false}}'
```

### Delete Running Jobs

```bash
# Delete all jobs
oc delete jobs --all -n offline-workload

# Or delete specific job
oc delete job <job-name> -n offline-workload
```

### Clean Up Everything

```bash
./cleanup.sh

# Or manually
oc delete cronjobs --all -n offline-workload
oc delete jobs --all -n offline-workload
oc delete pods --all -n offline-workload
oc delete namespace offline-workload
```

## Schedule

All workloads are scheduled to run **every 2 hours** and each job runs for **15 minutes**.

To change the schedule, edit the `schedule` field in the YAML files:
- `"0 */2 * * *"` - Every 2 hours (current)
- `"0 * * * *"` - Every hour
- `"*/30 * * * *"` - Every 30 minutes
- `"0 9 * * 1-5"` - Every weekday at 9 AM

## Customization

### Change Resource Limits

Edit the `resources` section in any YAML file:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "128Mi"
```

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

## Monitoring

These workloads generate metrics that can be observed in your observability stack:

- **CPU Metrics**: CPU usage, throttling
- **Memory Metrics**: Memory usage, RSS, working set
- **I/O Metrics**: Read/write operations, disk usage
- **Network Metrics**: Connection counts, bandwidth

## Documentation Files

This directory contains:

- **README.md** (this file) - Overview and quick start
- **START-HERE.md** - Quick start guide from login
- **CLI-COMMANDS.md** - Complete CLI commands reference
- **QUICK-REFERENCE.md** - Quick command reference
- **complete-setup.sh** - Complete setup script
- **deploy-offline-workloads.sh** - Deploy workloads script
- **run-workload.sh** - Run workloads script
- **status.sh** - Check status script
- **cleanup.sh** - Clean up script
- **workloads/\*.yaml** - Workload CronJob definitions

## Troubleshooting

### Jobs not starting

```bash
# Check CronJob status
oc describe cronjob <cronjob-name> -n offline-workload

# Check for resource quotas
oc describe quota -n offline-workload

# Check if CronJob is suspended
oc get cronjob <cronjob-name> -n offline-workload -o jsonpath='{.spec.suspend}'
```

### Pods failing

```bash
# Check pod events
oc describe pod <pod-name> -n offline-workload

# Check pod logs
oc logs <pod-name> -n offline-workload
```

### Image pull errors

The workloads use `busybox:latest` which should be available in most clusters. If you get image pull errors:

```bash
# Check if image is available
oc run test-pod --image=busybox:latest --rm -it --restart=Never -n offline-workload -- /bin/sh
```

### Insufficient resources

```bash
# Check available resources
oc describe nodes
oc top nodes

# Reduce resource requests/limits in the YAML files
```

## Notes

- All workloads use the `busybox:latest` image
- Workloads run entirely within the cluster
- No external network access required
- Suitable for air-gapped environments
- Minimal resource footprint
- All files and documentation are self-contained in this directory
