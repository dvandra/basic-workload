# Quick Reference - Offline Workloads CLI Commands

## 📋 All Commands at a Glance

### 1. Deploy Workloads

```bash
# Using script (recommended)
./deploy-offline-workloads.sh

# Or complete setup
./complete-setup.sh
```

# Or manually
oc create namespace offline-workload
oc apply -f workloads/simple-cpu-workload.yaml
oc apply -f workloads/simple-memory-workload.yaml
oc apply -f workloads/file-io-workload.yaml
oc apply -f workloads/network-workload.yaml
oc apply -f workloads/combined-workload.yaml
```

### 2. Run Workloads

```bash
# Using script
./run-workload.sh cpu
./run-workload.sh memory
./run-workload.sh io
./run-workload.sh network
./run-workload.sh combined
./run-workload.sh all

# Using CLI directly
oc create job --from=cronjob/simple-cpu-workload cpu-test-$(date +%s) -n offline-workload
oc create job --from=cronjob/simple-memory-workload memory-test-$(date +%s) -n offline-workload
oc create job --from=cronjob/file-io-workload io-test-$(date +%s) -n offline-workload
oc create job --from=cronjob/network-workload network-test-$(date +%s) -n offline-workload
oc create job --from=cronjob/combined-workload combined-test-$(date +%s) -n offline-workload
```

### 3. Check Status

```bash
# Using script
./status.sh

# Using CLI
oc get cronjobs -n offline-workload
oc get jobs -n offline-workload
oc get pods -n offline-workload
oc top pods -n offline-workload
```

### 4. View Logs

```bash
# View logs for a specific job
oc logs -f -n offline-workload -l job-name=cpu-test-<timestamp>

# View logs for all CPU workloads
oc logs -f -n offline-workload -l app=simple-cpu

# View logs for all memory workloads
oc logs -f -n offline-workload -l app=simple-memory

# View logs for all running pods
oc logs -f -n offline-workload --all-containers=true
```

### 5. Monitor in Real-Time

```bash
# Watch pods
oc get pods -n offline-workload -w

# Watch jobs
oc get jobs -n offline-workload -w

# Watch resource usage
watch -n 2 'oc top pods -n offline-workload'
```

### 6. Modify CPU and Memory

**Quick Method - Edit YAML:**
```bash
# Edit the YAML file
vim workloads/simple-cpu-workload.yaml

# Find resources section and modify:
# resources:
#   requests:
#     cpu: "100m"      # Change this
#     memory: "64Mi"  # Change this
#   limits:
#     cpu: "500m"     # Change this
#     memory: "128Mi" # Change this

# Apply changes
oc apply -f workloads/simple-cpu-workload.yaml
```

**Using oc patch:**
```bash
# Update CPU request
oc patch cronjob simple-cpu-workload -n offline-workload --type='json' -p='[
  {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"}
]'

# Update memory limit
oc patch cronjob simple-cpu-workload -n offline-workload --type='json' -p='[
  {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/limits/memory", "value": "256Mi"}
]'
```

**Using oc edit:**
```bash
oc edit cronjob simple-cpu-workload -n offline-workload
```

For detailed instructions, see **README.md** section "Modify CPU and Memory Values".

### 7. Stop Workloads

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

### 8. Clean Up

```bash
# Using script
./cleanup.sh
```

# Using CLI
oc delete cronjobs --all -n offline-workload
oc delete jobs --all -n offline-workload
oc delete pods --all -n offline-workload

# Delete namespace (removes everything)
oc delete namespace offline-workload
```

## 🔍 Useful One-Liners

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
```

## 📊 Resource Information

```bash
# Get resource requests and limits
oc get cronjob simple-cpu-workload -n offline-workload -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].resources}'

# Get pod resource usage
oc top pod <pod-name> -n offline-workload

# Get node resource usage
oc top nodes
```

## 🎯 Common Tasks

### Suspend a CronJob
```bash
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":true}}'
```

### Resume a CronJob
```bash
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":false}}'
```

### Change Schedule
```bash
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"schedule":"0 * * * *"}}'
```

### Get Last Run Time
```bash
oc get cronjob simple-cpu-workload -n offline-workload -o jsonpath='{.status.lastScheduleTime}'
```

## 📝 Notes

- All workloads use `busybox:latest` image (offline-friendly)
- Workloads run for 15 minutes each
- Scheduled to run every 2 hours
- All workloads are in `offline-workload` namespace
- No external dependencies required
- All documentation is self-contained in this directory

## 📖 Documentation

For detailed information, see:
- **README.md** - Full documentation with all details
- **START-HERE.md** - Quick start guide
- **CLI-COMMANDS.md** - Complete CLI commands reference
