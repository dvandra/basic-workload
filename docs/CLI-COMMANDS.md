# Complete CLI Commands Guide - From Login to Running Workloads

## 📋 Step-by-Step CLI Commands

### Step 0: Install virtctl (Optional but Recommended)

`virtctl` is the CLI tool for managing OpenShift Virtualization VMs. It's recommended for running VM stress tests.

#### Method 1: Download Binary (Linux/macOS/Windows)

```bash
# Get the latest stable version
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)

# Detect your architecture
ARCH="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/')"

# Download virtctl binary
curl -L -o virtctl "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH}"

# Make it executable
chmod +x virtctl

# Move to PATH (Linux/macOS)
sudo mv virtctl /usr/local/bin/

# Verify installation
virtctl version
```

**For Windows (PowerShell):**
```powershell
# Get version
$VERSION = (Invoke-WebRequest -Uri "https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt" -UseBasicParsing).Content.Trim()

# Download (adjust ARCH for your system: windows-amd64)
Invoke-WebRequest -Uri "https://github.com/kubevirt/kubevirt/releases/download/$VERSION/virtctl-$VERSION-windows-amd64.exe" -OutFile "virtctl.exe"

# Add to PATH or use directly
.\virtctl.exe version
```

#### Method 2: Homebrew (macOS/Linux)

```bash
# Install via Homebrew
brew install virtctl

# Verify installation
virtctl version
```

#### Method 3: kubectl Plugin (via krew)

If you have `kubectl` and `krew` installed:

```bash
# Install virt plugin
kubectl krew install virt

# Use as kubectl plugin
kubectl virt version
kubectl virt console <vm-name> -n <namespace>
```

**Note:** With krew, use `kubectl virt` instead of `virtctl`.

#### Verify Installation

```bash
# Check if virtctl is installed
virtctl version

# Or if using krew plugin
kubectl virt version
```

**Example Output:**
```
Client Version: version.Info{Major:"1", Minor:"0", GitVersion:"v1.0.0", ...}
```

---

### Step 1: Login to OpenShift Cluster

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

**Example:**
```bash
oc login https://api.example.openshift.com:6443 -u admin -p <your-password>
oc whoami
# Output: admin
```

### Step 2: Deploy Workloads

**Note**: Run all commands from the workloads repository directory.

**Option A: Using the complete setup script (recommended)**
```bash
chmod +x complete-setup.sh
./complete-setup.sh
```

**Option B: Manual deployment**
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

### Step 4: Run Workloads

**Option A: Using the script**
```bash
./run-workload.sh all
```

**Option B: Manual CLI commands**
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

# Run all at once
oc create job --from=cronjob/simple-cpu-workload cpu-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/simple-memory-workload memory-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/file-io-workload io-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/network-workload network-test-$(date +%s) -n offline-workload && \
oc create job --from=cronjob/combined-workload combined-test-$(date +%s) -n offline-workload
```

### Step 5: Monitor Workloads

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

### Step 6: View Logs

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

### Step 7: Clean Up

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

## 🚀 Quick One-Liners

### Complete Setup and Run
```bash
./complete-setup.sh && ./run-workload.sh all
```

### Check Everything
```bash
oc get cronjobs,jobs,pods -n offline-workload
```

### View All Logs
```bash
oc get pods -n offline-workload -o name | xargs -I {} oc logs {} -n offline-workload --tail=10
```

### Get Resource Usage
```bash
oc top pods -n offline-workload && oc top nodes
```

## 📝 Complete Workflow Example

```bash
# 1. Login
oc login https://api.example.openshift.com:6443 -u admin

# 2. Setup (from workloads directory)
./complete-setup.sh

# 4. Run workloads
./run-workload.sh all

# 5. Monitor
watch -n 2 'oc get pods -n offline-workload'

# 6. View logs
oc logs -f -n offline-workload -l app=simple-cpu

# 7. Clean up (when done)
./cleanup.sh
```

## 🔍 Troubleshooting Commands

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

## 📊 Useful Queries

```bash
# Count running pods
oc get pods -n offline-workload --field-selector=status.phase=Running --no-headers | wc -l

# List all job names
oc get jobs -n offline-workload -o jsonpath='{.items[*].metadata.name}'

# Get last schedule time
oc get cronjob simple-cpu-workload -n offline-workload -o jsonpath='{.status.lastScheduleTime}'

# Get resource requests
oc get cronjob simple-cpu-workload -n offline-workload -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].resources}'
```
