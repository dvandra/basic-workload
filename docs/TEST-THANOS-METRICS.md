# Thanos Metrics Test Script

This script deploys workloads, waits 20 minutes for metrics to accumulate, and then queries Thanos for CPU and memory utilization metrics.

## Overview

The script performs the following steps:
1. Deploys all offline workloads to the `offline-workload` namespace
2. Triggers workloads immediately
3. Waits 20 minutes for metrics to accumulate
4. Queries Thanos for the following metrics:
   - `acm_rs:namespace:cpu_request_hard`
   - `acm_rs:namespace:cpu_request`
   - `acm_rs:namespace:cpu_usage`
   - `acm_rs:namespace:cpu_recommendation`
   - `acm_rs:namespace:memory_request_hard`
   - `acm_rs:namespace:memory_request`
   - `acm_rs:namespace:memory_usage`
   - `acm_rs:namespace:memory_recommendation`
5. Displays current values and time series data for the last 20 minutes

## Prerequisites

- Access to an OpenShift cluster
- `oc` CLI tool installed and configured
- Logged in to OpenShift (`oc login`)
- Cluster admin or namespace admin permissions
- Access to Thanos Query service (usually in `openshift-monitoring` namespace)
- Optional: `jq` installed for better JSON parsing (recommended)

## Usage

### Basic Usage

```bash
./test-thanos-metrics.sh
```

**Note**: Run from the workloads repository directory.

### What the Script Does

1. **Deployment Phase**:
   - Creates the `offline-workload` namespace
   - Deploys all 5 CronJobs (CPU, Memory, File I/O, Network, Combined)
   - Triggers jobs immediately to start generating metrics

2. **Waiting Phase**:
   - Waits exactly 20 minutes (1200 seconds)
   - Shows progress bar with elapsed time
   - Allows metrics to accumulate in Thanos

3. **Query Phase**:
   - Automatically detects Thanos Query endpoint
   - Uses OpenShift route if available
   - Falls back to port-forward if needed
   - Queries all 8 metrics for the namespace
   - Retrieves time series data for the last 20 minutes

4. **Output Phase**:
   - Displays current values for all metrics
   - Shows time series data for CPU and memory usage
   - Provides a summary table with status indicators

## Output

The script provides:

1. **Current Metric Values**: Shows the latest value for each metric
2. **Time Series Data**: Displays CPU and memory usage over the last 20 minutes
3. **Summary Table**: Quick overview with status indicators (✓ or ✗)

### Example Output

```
==========================================
CPU Metrics for namespace: offline-workload
==========================================

Metric: acm_rs:namespace:cpu_request_hard
  Current value: 500m

Metric: acm_rs:namespace:cpu_request
  Current value: 300m

Metric: acm_rs:namespace:cpu_usage
  Current value: 250m

...

==========================================
Time Series Data (Last 20 Minutes)
==========================================

CPU Usage Over Time:
2024-01-19 10:00:00: 0.25
2024-01-19 10:01:00: 0.28
2024-01-19 10:02:00: 0.30
...
```

## Troubleshooting

### Cannot Connect to Thanos

If you see connection errors:

1. **Check Thanos Query Service**:
   ```bash
   oc get svc -n openshift-monitoring thanos-querier
   ```

2. **Check Route**:
   ```bash
   oc get route -n openshift-monitoring thanos-querier
   ```

3. **Manual Port-Forward**:
   ```bash
   oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
   ```

### No Metrics Found

If metrics show "N/A":

1. **Verify Namespace**:
   ```bash
   oc get namespace offline-workload
   ```

2. **Check if Workloads are Running**:
   ```bash
   oc get pods -n offline-workload
   oc get jobs -n offline-workload
   ```

3. **Verify Metric Names**: The metric names must match exactly:
   - `acm_rs:namespace:cpu_request_hard`
   - `acm_rs:namespace:cpu_request`
   - etc.

4. **Check Metric Availability**:
   ```bash
   # Query Thanos directly
   oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
   # Then in another terminal:
   curl -k -G \
     --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
     -H "Authorization: Bearer $(oc whoami -t)" \
     "http://localhost:9091/api/v1/query"
   ```

### Time Series Data Not Showing

If time series data is empty:

1. **Install jq** for better parsing:
   ```bash
   # On macOS
   brew install jq
   
   # On Linux
   sudo yum install jq
   # or
   sudo apt-get install jq
   ```

2. **Check Raw Response**: The script stores raw responses in variables. You can inspect them manually.

## Manual Query Examples

If you want to query metrics manually:

```bash
# Get token
TOKEN=$(oc whoami -t)

# Setup port-forward
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091 &

# Query CPU usage
curl -k -G \
  --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:9091/api/v1/query"

# Query time series (last 20 minutes)
END_TIME=$(date +%s)
START_TIME=$((END_TIME - 1200))
curl -k -G \
  --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
  --data-urlencode "start=${START_TIME}" \
  --data-urlencode "end=${END_TIME}" \
  --data-urlencode "step=60" \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:9091/api/v1/query_range"
```

## Expected Metrics

After 20 minutes, you should see:

- **CPU Request Hard**: Sum of all CPU requests (limits) in the namespace
- **CPU Request**: Sum of all CPU requests in the namespace
- **CPU Usage**: Actual CPU usage in the namespace
- **CPU Recommendation**: Recommended CPU allocation
- **Memory Request Hard**: Sum of all memory requests (limits) in the namespace
- **Memory Request**: Sum of all memory requests in the namespace
- **Memory Usage**: Actual memory usage in the namespace
- **Memory Recommendation**: Recommended memory allocation

## Notes

- The script waits exactly 20 minutes to ensure sufficient data collection
- Metrics are queried at the end of the 20-minute period
- Time series data shows values at 1-minute intervals
- All values are formatted for human readability (cores/millicores for CPU, Gi/Mi/Ki for memory)
- The script automatically cleans up port-forward on exit

## Cleanup

After testing, you can clean up:

```bash
./cleanup.sh
```

Or manually:

```bash
oc delete namespace offline-workload
```
