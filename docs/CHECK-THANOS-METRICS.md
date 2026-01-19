# Check Thanos Metrics - User Guide

This guide explains how to use the `check-thanos-metrics.sh` script to verify workloads and query Thanos metrics on your OpenShift cluster.

## Overview

The `check-thanos-metrics.sh` script:
- Verifies that workloads are deployed and running
- Checks if namespace, CronJobs, Jobs, and Pods exist
- Queries Thanos for CPU and memory utilization metrics
- Displays current values and time series data for the last 4 hours

## Prerequisites

Before running the script, ensure:

1. **OpenShift CLI (`oc`) is installed**
   ```bash
   oc version
   ```

2. **You are logged in to OpenShift**
   ```bash
   oc whoami
   ```
   If not logged in, see [Login Instructions](#login-to-openshift) below.

3. **Workloads are already deployed**
   - The `offline-workload` namespace should exist
   - CronJobs should be deployed
   - Jobs should have been triggered (workloads should be running or have run)

4. **You have proper permissions**
   - Access to the `offline-workload` namespace
   - Access to the `openshift-monitoring` namespace (for Thanos Query)

5. **Optional but recommended: `jq` installed**
   ```bash
   # On macOS
   brew install jq
   
   # On Linux (RHEL/CentOS)
   sudo yum install jq
   
   # On Linux (Ubuntu/Debian)
   sudo apt-get install jq
   ```

## Quick Start

```bash
# Run the script (from workloads directory)
./check-thanos-metrics.sh
```

## Step-by-Step Instructions

### Step 1: Login to OpenShift

If you're not already logged in:

```bash
# Interactive login (recommended)
oc login <your-openshift-api-url>

# Or with username and password
oc login <your-openshift-api-url> -u <username> -p <password>

# Or with token
oc login <your-openshift-api-url> --token=<your-token>
```

**Verify login:**
```bash
oc whoami
oc config current-context
```

**Example:**
```bash
oc login https://api.example.openshift.com:6443 -u admin
oc whoami
# Output: admin
```

### Step 2: Make Script Executable (First Time Only)

**Note**: Run all commands from the workloads repository directory.

```bash
chmod +x check-thanos-metrics.sh
```

### Step 3: Run the Script

```bash
./check-thanos-metrics.sh
```

## Complete Example

Here's a complete example from start to finish:

```bash
# 1. Login to OpenShift
oc login https://api.example.openshift.com:6443 -u admin

# 2. Make script executable (if first time)
chmod +x check-thanos-metrics.sh

# 3. Run the script (from workloads directory)
./check-thanos-metrics.sh
```

## What the Script Does

The script performs the following checks and queries:

### 1. Verification Phase

- ✅ Checks if namespace `offline-workload` exists
- ✅ Verifies all 5 CronJobs exist:
  - `simple-cpu-workload`
  - `simple-memory-workload`
  - `file-io-workload`
  - `network-workload`
  - `combined-workload`
- ✅ Checks if Jobs and Pods are running
- ✅ Displays pod status

### 2. Thanos Connection Phase

- ✅ Automatically detects Thanos Query endpoint
- ✅ Uses OpenShift route if available
- ✅ Falls back to port-forward if needed
- ✅ Tests connection to Thanos

### 3. Metrics Query Phase

Queries **6 metrics** for the namespace:

**CPU Metrics (3 metrics):**
- `acm_rs:namespace:cpu_request` - Sum of all CPU requests
- `acm_rs:namespace:cpu_usage` - Actual CPU usage
- `acm_rs:namespace:cpu_recommendation` - Recommended CPU allocation

**Memory Metrics (3 metrics):**
- `acm_rs:namespace:memory_request` - Sum of all memory requests
- `acm_rs:namespace:memory_usage` - Actual memory usage
- `acm_rs:namespace:memory_recommendation` - Recommended memory allocation

### 4. Output Phase

- ✅ Displays current values for **all 6 metrics** (formatted and raw)
- ✅ Shows time series data for **all 6 metrics** (last 4 hours, 5-minute intervals)
- ✅ Provides comprehensive summary table with status indicators
- ✅ Detailed values table showing both formatted and raw values

## Expected Output

The script will display:

```
==========================================
Thanos Metrics Check Script
==========================================
Namespace: offline-workload

Current user: admin
Current context: admin/api-example-com:6443

Step 1: Checking if namespace exists...
✓ Namespace 'offline-workload' exists

Step 2: Checking if CronJobs exist...
  ✓ CronJob 'simple-cpu-workload' exists
  ✓ CronJob 'simple-memory-workload' exists
  ...

Step 3: Checking if Jobs and Pods exist...
  ✓ Found 5 job(s)
  ✓ Found 3 pod(s)

Step 4: Querying Thanos for metrics...
Thanos endpoint: https://thanos-querier-openshift-monitoring.apps.example.com
Connection successful!

==========================================
CPU Metrics for namespace: offline-workload
==========================================

Metric: acm_rs:namespace:cpu_request
  Current value: 300m

...

==========================================
Time Series Data (Last 4 Hours)
==========================================

CPU Usage Over Time:
2024-01-19 10:00:00: 0.25
2024-01-19 10:01:00: 0.28
...

==========================================
Summary Table
==========================================
...
```

## Troubleshooting

### Issue: "Permission denied"

**Error:**
```bash
bash: ./check-thanos-metrics.sh: Permission denied
```

**Solution:**
```bash
chmod +x check-thanos-metrics.sh
```

### Issue: "Not logged in to OpenShift"

**Error:**
```
Error: Not logged in to OpenShift. Please run 'oc login' first.
```

**Solution:**
```bash
oc login <your-openshift-api-url> -u <username> -p <password>
```

### Issue: "Namespace does not exist"

**Error:**
```
✗ Namespace 'offline-workload' does not exist
```

**Solution:**
Deploy workloads first:
```bash
./deploy-offline-workloads.sh
```

### Issue: "Cannot connect to Thanos"

**Error:**
```
Error: Cannot connect to Thanos. Please check:
  1. Thanos Query service is running
  2. You have proper permissions
  3. Network connectivity
```

**Solutions:**

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
   Then run the script again.

4. **Check Permissions:**
   ```bash
   oc auth can-i get pods -n openshift-monitoring
   oc auth can-i get routes -n openshift-monitoring
   ```

### Issue: "No metrics found" or "N/A"

**Possible Causes:**

1. **Workloads not running:**
   ```bash
   oc get pods -n offline-workload
   oc get jobs -n offline-workload
   ```

2. **Metrics not available yet:**
   - Wait a few minutes after workloads start
   - Metrics may take time to propagate to Thanos

3. **Wrong metric names:**
   - Verify metric names match exactly
   - Check if metrics exist in Thanos:
     ```bash
     oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
     # Then query manually
     curl -k -G \
       --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
       -H "Authorization: Bearer $(oc whoami -t)" \
       "http://localhost:9091/api/v1/query"
     ```

4. **Namespace mismatch:**
   - Ensure namespace is exactly `offline-workload`
   - Check: `oc get namespace offline-workload`

### Issue: "Time series data not showing"

**Solution:**
Install `jq` for better JSON parsing:
```bash
# On macOS
brew install jq

# On Linux
sudo yum install jq
# or
sudo apt-get install jq
```

## Manual Query Examples

If you want to query metrics manually:

### Setup Port-Forward

```bash
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
```

### Query Current Value

```bash
TOKEN=$(oc whoami -t)

curl -k -G \
  --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:9091/api/v1/query"
```

### Query Time Series (Last 4 Hours)

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

## Understanding the Metrics

The script queries **6 metrics** for the `offline-workload` namespace:

### CPU Metrics (3 metrics)

1. **acm_rs:namespace:cpu_request**
   - Description: Sum of all CPU requests in the namespace
   - Unit: Cores or millicores
   - Example: If you have 3 pods with CPU requests of 100m, 200m, and 300m, this would be 600m

2. **acm_rs:namespace:cpu_usage**
   - Description: Actual CPU usage in the namespace
   - Unit: Cores or millicores
   - Example: Current CPU consumption across all pods in the namespace

3. **acm_rs:namespace:cpu_recommendation**
   - Description: Recommended CPU allocation based on usage patterns
   - Unit: Cores or millicores
   - Example: System recommendation for optimal CPU allocation

### Memory Metrics (3 metrics)

1. **acm_rs:namespace:memory_request**
   - Description: Sum of all memory requests in the namespace
   - Unit: Bytes (formatted as GiB, MiB, or KiB)
   - Example: If you have 3 pods with memory requests of 128Mi, 256Mi, and 512Mi, this would be 896Mi

2. **acm_rs:namespace:memory_usage**
   - Description: Actual memory usage in the namespace
   - Unit: Bytes (formatted as GiB, MiB, or KiB)
   - Example: Current memory consumption across all pods in the namespace

3. **acm_rs:namespace:memory_recommendation**
   - Description: Recommended memory allocation based on usage patterns
   - Unit: Bytes (formatted as GiB, MiB, or KiB)
   - Example: System recommendation for optimal memory allocation

## All Metrics Displayed

The script displays:

1. **Current Values Section**: Shows formatted and raw values for all 6 metrics
2. **Time Series Data Section**: Shows historical data (last 4 hours) for all 6 metrics
3. **Summary Table**: Quick overview of all 6 metrics with status indicators
4. **Detailed Values Table**: Complete breakdown showing both formatted and raw values for all 6 metrics

## Value Formatting

- **CPU values**: Displayed in cores (e.g., "1.5 cores") or millicores (e.g., "500m")
- **Memory values**: Displayed in GiB (e.g., "2.5Gi"), MiB (e.g., "512Mi"), or KiB (e.g., "128Ki")

## Notes

- The script queries **6 metrics** for the namespace
- Time series data is displayed for **all 6 metrics** (not just usage metrics)
- Time range: Last 4 hours with 5-minute intervals (48 data points per metric)
- All values are formatted for human readability (CPU in cores/millicores, Memory in GiB/MiB/KiB)
- Raw values are also displayed for precise measurements
- The script automatically cleans up port-forward on exit
- If metrics show "N/A", it means the metric was not found in Thanos
- Status indicators (✓ or ✗) show whether each metric was successfully retrieved

## Related Scripts

- **`deploy-offline-workloads.sh`**: Deploy workloads if not already deployed
- **`test-thanos-metrics.sh`**: Deploy, wait 20 minutes, then query metrics
- **`status.sh`**: Quick status check of workloads
- **`cleanup.sh`**: Clean up all workloads

## Getting Help

If you encounter issues:

1. Check the troubleshooting section above
2. Verify prerequisites are met
3. Check OpenShift cluster status: `oc cluster-info`
4. Verify Thanos is running: `oc get pods -n openshift-monitoring | grep thanos`
5. Check workload status: `oc get all -n offline-workload`

## Summary

The `check-thanos-metrics.sh` script is a simple way to:
- ✅ Verify workloads are deployed
- ✅ Query Thanos for CPU and memory metrics
- ✅ View current values and historical data
- ✅ Get a quick overview of resource utilization

Just run `./check-thanos-metrics.sh` after ensuring workloads are deployed and running!
