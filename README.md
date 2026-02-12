# ACM Observability Test Workloads

Test workloads for validating Red Hat Advanced Cluster Management (ACM) Multicluster Observability metrics collection.

## Overview

This project deploys test workloads to OpenShift clusters and verifies that metrics are properly collected and available in Thanos. It includes:

- **Namespace Workloads**: CPU, memory, I/O, and network stress tests using CronJobs
- **VM Workloads**: Virtual machine workloads using OpenShift Virtualization with stress-ng

## Prerequisites

### 1. ACM and MCO

- **ACM Operator** installed on the Hub cluster (validated with version 2.16+)
- **Multicluster Observability (MCO)** deployed on the Hub

### 2. OpenShift CLI

```bash
# Verify oc is installed
oc version
```

### 3. Cluster Access

You need access to:
- **Hub cluster**: Where ACM/MCO and Thanos run
- **Spoke cluster(s)**: Where workloads will be deployed

> ⚠️ **VM Workloads**: Requires **OpenShift Virtualization** installed on the spoke cluster. Use `--skip-vm` flag if not available.

### 4. SSH Key (Required for VM Workloads)

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Verify your public key exists
cat ~/.ssh/id_rsa.pub
```

### 5. Optional: jq

```bash
# macOS
brew install jq

# RHEL/Fedora
sudo dnf install jq

# Ubuntu/Debian
sudo apt-get install jq
```

## Setup

### Step 1: Set Up Cluster Context

Login to your cluster and create a named context:

```bash
# Login to your OpenShift cluster
oc login --token=<your-token> --server=<api-url>

# Create a named context (default name is "hub")
oc config rename-context $(oc config current-context) hub

# Verify it works
oc config use-context hub && oc whoami
```

**Single Cluster Setup** (default): If you have one cluster that serves as both Hub and Spoke, you only need the `hub` context. All workloads will deploy to this cluster.

**Multi-Cluster Setup**: If you have separate spoke clusters, set up additional contexts:

```bash
# Namespace Spoke Cluster (for CronJob workloads/ Namespace rightsizing related workload)
oc login --token=<spoke-token> --server=<namespace-spoke-url>
oc config rename-context $(oc config current-context) namespace-spoke

# VM Spoke Cluster (for VM workloads)
oc login --token=<vm-spoke-token> --server=<vm-spoke-url>
oc config rename-context $(oc config current-context) vm-spoke
```

> ⚠️ **Note**: VM Spoke Cluster requires **OpenShift Virtualization** to be installed for VM workloads. Skip VM workloads (`--skip-vm`) if OpenShift Virtualization is not available.

### Step 2: Set Environment Variables

```bash
# ─────────────────────────────────────────────────────────────
# SINGLE CLUSTER SETUP (simplest - just set Hub context)
# ─────────────────────────────────────────────────────────────
export HUB_CONTEXT_NAME="hub"
# Spoke contexts default to Hub if not set

# ─────────────────────────────────────────────────────────────
# MULTI-CLUSTER SETUP (optional - only if using separate spokes)
# ─────────────────────────────────────────────────────────────
# export NAMESPACE_SPOKE_CONTEXT_NAME="namespace-spoke"
# export VM_SPOKE_CONTEXT_NAME="vm-spoke"

# ─────────────────────────────────────────────────────────────
# REQUIRED for VM Workloads: SSH Public Key
# ─────────────────────────────────────────────────────────────
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# ─────────────────────────────────────────────────────────────
# OPTIONAL: Customize namespaces (defaults shown)
# ─────────────────────────────────────────────────────────────
# export NAMESPACE_WORKLOAD_NS="offline-workload"
# export VM_WORKLOAD_NS="auto-vm-test"

# ─────────────────────────────────────────────────────────────
# OPTIONAL: Customize timing (defaults shown)
# ─────────────────────────────────────────────────────────────
# export METRICS_WAIT_TIME="1200"     # 20 minutes
# export VM_STRESS_DURATION="5m"       # 5 minutes
```

**Tip**: You can run these `export` commands directly in your terminal session. For persistence across sessions, add them to your `~/.bashrc` or `~/.zshrc`.

### Step 3: Make Scripts Executable (First Time Only)

```bash
chmod +x *.sh namespace-workloads/scripts/*.sh vm-workloads/scripts/*.sh
```

### Step 4: Verify Configuration (Recommended)

```bash
./show-config.sh
```

This will display all configuration values and verify cluster connectivity.

## Quick Start

### Single Cluster (Simplest)

```bash
# 1. Login and create context
oc login --token=<token> --server=<url>
oc config rename-context $(oc config current-context) hub

# 2. Set environment variables
export HUB_CONTEXT_NAME="hub"
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# 3. Run (after completing Setup steps 3 & 4)
./run-all.sh
```

### Multi-Cluster

```bash
# 1. Set up all contexts (see Setup Step 1)
# 2. Set environment variables
export HUB_CONTEXT_NAME="hub"
export NAMESPACE_SPOKE_CONTEXT_NAME="namespace-spoke"
export VM_SPOKE_CONTEXT_NAME="vm-spoke"
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# 3. Run (after completing Setup steps 3 & 4)
./run-all.sh
```

## Usage

### Complete Workflow

```bash
./run-all.sh
```

Options:
- `--skip-vm`: Skip VM workload deployment
- `--skip-namespace`: Skip namespace workload deployment
- `--cleanup-only`: Only cleanup resources
- `--no-wait`: Skip waiting for metrics

### Manual Execution

```bash
# Deploy namespace workloads (on spoke cluster)
oc config use-context $NAMESPACE_SPOKE_CONTEXT_NAME
./namespace-workloads/scripts/deploy.sh

# Deploy VM workloads (on spoke cluster)
oc config use-context $VM_SPOKE_CONTEXT_NAME
./vm-workloads/scripts/deploy.sh

# Wait 15-20 minutes for metrics to be collected...

# Check metrics over last 5 days (range + instant queries)
./namespace-workloads/scripts/check-thanos-metrics-5days.sh

# Cleanup (deletes workloads AND namespaces by default)
./cleanup.sh

# Cleanup options
./cleanup.sh --keep-namespace   # Keep namespaces, only delete resources
./cleanup.sh --skip-vm          # Skip VM cleanup
./cleanup.sh --skip-namespace   # Skip namespace cleanup
```

### Cluster Context Flow

| Action | Context Used |
|--------|--------------|
| Deploy namespace workloads | `namespace-spoke` |
| Deploy VM workloads | `vm-spoke` |
| Check Thanos metrics (last 5 days) | `hub` (Thanos) |

## Project Structure

```
basic-workload/
├── README.md                           # This file
├── LICENSE                             # License file
├── config.sh                           # Default configuration (env vars override)
├── show-config.sh                      # Display and verify configuration
├── run-all.sh                          # Master orchestration script
├── cleanup.sh                          # Cleanup resources (deletes namespaces by default)
│
├── namespace-workloads/                # ── Namespace Workloads ──
│   ├── workloads/                      # CronJob YAML definitions
│   │   ├── simple-cpu-workload.yaml    #   CPU stress test
│   │   ├── simple-memory-workload.yaml #   Memory stress test
│   │   ├── file-io-workload.yaml       #   File I/O stress test
│   │   ├── network-workload.yaml       #   Network stress test
│   │   └── combined-workload.yaml      #   Combined workload
│   └── scripts/
│       ├── deploy.sh                   # Deploy CronJob workloads to spoke
│       ├── check-metrics.sh            # Query acm_rs:namespace:* from Hub Thanos
│       └── check-thanos-metrics-5days.sh # 5-day range + instant Thanos queries
│
├── vm-workloads/                       # ── VM Workloads ──
│   ├── workloads/                      # VM YAML definitions
│   │   ├── fedora-vm-1.yaml            #   Fedora VM with stress-ng
│   │   ├── fedora-vm-2.yaml            #   Second Fedora VM
│   │   └── rhel-vm.yaml                #   RHEL VM
│   └── scripts/
│       ├── deploy.sh                   # Deploy VMs + run stress test
│       └── check-metrics.sh            # Query acm_rs_vm:namespace:* from Hub Thanos
│
└── docs/
    └── TROUBLESHOOTING.md              # Common issues and solutions
```

## Configuration Reference

| Environment Variable | Required | Default | Description |
|---------------------|----------|---------|-------------|
| `HUB_CONTEXT_NAME` | Yes | `hub` | Hub cluster context (where Thanos runs) |
| `NAMESPACE_SPOKE_CONTEXT_NAME` | No | `$HUB_CONTEXT_NAME` | Namespace workload cluster (defaults to Hub) |
| `VM_SPOKE_CONTEXT_NAME` | No | `$HUB_CONTEXT_NAME` | VM workload cluster (defaults to Hub) |
| `VM_SSH_PUBLIC_KEY` | Yes (VM) | `~/.ssh/id_rsa.pub` | SSH public key for VM access |
| `NAMESPACE_WORKLOAD_NS` | No | `offline-workload` | Namespace for CronJob workloads |
| `VM_WORKLOAD_NS` | No | `auto-vm-test` | Namespace for VM workloads |
| `METRICS_WAIT_TIME` | No | `1200` | Seconds to wait for metrics (20 min) |
| `VM_STRESS_DURATION` | No | `5m` | Duration of VM stress test |

**Note**: For single-cluster setups, only `HUB_CONTEXT_NAME` and `VM_SSH_PUBLIC_KEY` are required. Spoke contexts automatically default to the Hub context.

## Metrics Collected

### Namespace Workload Metrics (`acm_rs:namespace:*`)

| Metric | Description |
|--------|-------------|
| `acm_rs:namespace:cpu_request` | Sum of CPU requests |
| `acm_rs:namespace:cpu_usage` | Actual CPU usage |
| `acm_rs:namespace:cpu_recommendation` | Recommended CPU allocation |
| `acm_rs:namespace:memory_request` | Sum of memory requests |
| `acm_rs:namespace:memory_usage` | Actual memory usage |
| `acm_rs:namespace:memory_recommendation` | Recommended memory allocation |

### VM Workload Metrics (`acm_rs_vm:namespace:*`)

| Metric | Description |
|--------|-------------|
| `acm_rs_vm:namespace:cpu_request` | Sum of VM CPU requests |
| `acm_rs_vm:namespace:cpu_usage` | Actual VM CPU usage |
| `acm_rs_vm:namespace:cpu_recommendation` | Recommended VM CPU allocation |
| `acm_rs_vm:namespace:memory_request` | Sum of VM memory requests |
| `acm_rs_vm:namespace:memory_usage` | Actual VM memory usage |
| `acm_rs_vm:namespace:memory_recommendation` | Recommended VM memory allocation |

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

### Quick Checks

```bash
# Verify ACM is installed (on Hub)
oc config use-context $HUB_CONTEXT_NAME
oc get multiclusterobservability -A

# Check Thanos endpoint (on Hub)
oc get route -n openshift-monitoring thanos-querier

# Manual metric query
curl -k -G \
  --data-urlencode 'query=last_over_time(acm_rs:namespace:cpu_usage{namespace="offline-workload"}[30m])' \
  -H "Authorization: Bearer $(oc whoami -t)" \
  "https://$(oc get route -n openshift-monitoring thanos-querier -o jsonpath='{.spec.host}')/api/v1/query"
```
