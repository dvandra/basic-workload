#!/bin/bash

# Script to check existing workloads and query Thanos for metrics
# Assumes workloads are already deployed and triggered
#
# Queries 6 metrics for the namespace:
# CPU Metrics:
#   - acm_rs:namespace:cpu_request
#   - acm_rs:namespace:cpu_usage
#   - acm_rs:namespace:cpu_recommendation
# Memory Metrics:
#   - acm_rs:namespace:memory_request
#   - acm_rs:namespace:memory_usage
#   - acm_rs:namespace:memory_recommendation
#
# Time Range: Last 4 hours (14400 seconds)
# Query Interval: 5 minutes (300 seconds)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="offline-workload"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Thanos Metrics Check Script"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Time Range: Last 4 hours"
echo ""
echo "Note: This script queries metrics that may take time to appear."
echo "If metrics show 'N/A', workloads may need more time to generate data."
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc command not found. Please install OpenShift CLI.${NC}"
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to OpenShift. Please run 'oc login' first.${NC}"
    exit 1
fi

echo -e "${GREEN}Current user: $(oc whoami)${NC}"
echo -e "${GREEN}Current context: $(oc config current-context)${NC}"
echo ""

# Function to get Thanos query endpoint
get_thanos_endpoint() {
    # Try to find Thanos Query route (always HTTPS)
    local route=$(oc get route -n openshift-monitoring thanos-querier -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    # If route found, use HTTPS
    if [ -n "$route" ]; then
        # Check if route has TLS
        local tls=$(oc get route -n openshift-monitoring thanos-querier -o jsonpath='{.spec.tls}' 2>/dev/null || echo "")
        if [ -n "$tls" ] && [ "$tls" != "null" ]; then
            echo "https://${route}"
        else
            # Route without TLS (unlikely but handle it)
            echo "http://${route}"
        fi
    else
        # Try to find the route with different name patterns
        local alt_route=$(oc get route -n openshift-monitoring -l app=thanos-querier -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
        if [ -n "$alt_route" ]; then
            echo "https://${alt_route}"
        else
            # Try service directly (internal, use HTTP)
            local svc=$(oc get svc -n openshift-monitoring thanos-querier -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
            if [ -n "$svc" ]; then
                echo "http://${svc}:9091"
            else
                # Use port-forward as fallback (HTTP for localhost)
                echo "http://localhost:9091"
            fi
        fi
    fi
}

# Function to setup port-forward if needed
setup_port_forward() {
    local endpoint=$1
    if [[ "$endpoint" == "http://localhost:9091" ]]; then
        echo -e "${YELLOW}Setting up port-forward to Thanos Query...${NC}"
        oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091 > /dev/null 2>&1 &
        PORT_FORWARD_PID=$!
        sleep 5
        if kill -0 $PORT_FORWARD_PID 2>/dev/null; then
            echo -e "${GREEN}Port-forward established (PID: $PORT_FORWARD_PID)${NC}"
        else
            echo -e "${RED}Failed to establish port-forward${NC}"
            exit 1
        fi
    fi
}

# Function to cleanup port-forward
cleanup_port_forward() {
    if [ -n "$PORT_FORWARD_PID" ]; then
        echo -e "${YELLOW}Cleaning up port-forward...${NC}"
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
}

# Function to query Thanos for current value
get_current_metric() {
    local metric=$1
    local namespace=$2
    local endpoint=$3
    
    local query="acm_rs:namespace:${metric}{namespace=\"${namespace}\"}"
    local token=$(oc whoami -t 2>/dev/null)
    
    if [ -z "$token" ]; then
        echo "Error: Cannot get authentication token"
        return 1
    fi
    
    # Add timeout and connection timeout to prevent hanging
    # Use -k to ignore SSL certificate errors for HTTPS
    # Use --max-time instead of timeout command (more portable)
    # Use --fail to fail on HTTP errors
    local response=$(curl -s -k --connect-timeout 10 --max-time 30 --fail -G \
        --data-urlencode "query=${query}" \
        -H "Authorization: Bearer ${token}" \
        "${endpoint}/api/v1/query" 2>&1)
    
    local curl_exit=$?
    
    # Check for timeout or connection errors
    if [ $curl_exit -ne 0 ] || echo "$response" | grep -q "timed out\|timeout\|Operation timed out"; then
        echo "Error: Request timed out after 30 seconds"
        return 1
    fi
    
    # Check for HTTP/HTTPS mismatch error
    if echo "$response" | grep -q "Client sent an HTTP request to an HTTPS server"; then
        # If endpoint was HTTP, try HTTPS instead
        if [[ "$endpoint" == http://* ]]; then
            endpoint="${endpoint/http:/https:}"
            response=$(curl -s -k --connect-timeout 10 --max-time 30 --fail -G \
                --data-urlencode "query=${query}" \
                -H "Authorization: Bearer ${token}" \
                "${endpoint}/api/v1/query" 2>&1)
            curl_exit=$?
        fi
    fi
    
    # Check for connection errors
    if [ $curl_exit -ne 0 ]; then
        if echo "$response" | grep -q "Could not resolve\|Connection refused\|Failed to connect"; then
            echo "Error: Cannot connect to endpoint"
            return 1
        fi
    fi
    
    # Filter out error messages from stderr
    local error_msg=$(echo "$response" | grep -i "error\|Client sent\|SSL\|certificate" || true)
    if [ -n "$error_msg" ] && [ -z "$(echo "$response" | grep -o '{"status"')" ]; then
        # Response contains error, not JSON
        echo "Error: $(echo "$error_msg" | head -1)"
        return 1
    fi
    
    if [ $curl_exit -eq 0 ] && [ -n "$response" ]; then
        # Extract value using jq if available
        if command -v jq &> /dev/null; then
            local value=$(echo "$response" | jq -r '.data.result[0].value[1] // empty' 2>/dev/null)
            if [ -n "$value" ] && [ "$value" != "null" ] && [ "$value" != "empty" ]; then
                echo "$value"
                return 0
            fi
        else
            # Fallback: try to extract value without jq
            local value=$(echo "$response" | grep -o '"value":\["[^"]*","[^"]*"\]' | sed 's/.*","\([^"]*\)".*/\1/' | head -1)
            if [ -n "$value" ] && [ "$value" != "null" ]; then
                echo "$value"
                return 0
            fi
        fi
    fi
    echo "N/A"
    return 1
}

# Function to query Thanos for time series
query_time_series() {
    local metric=$1
    local namespace=$2
    local endpoint=$3
    local start_time=$4
    local end_time=$5
    
    local query="acm_rs:namespace:${metric}{namespace=\"${namespace}\"}"
    local token=$(oc whoami -t)
    
    # Add timeout and connection timeout to prevent hanging
    # Use -k to ignore SSL certificate errors for HTTPS
    # Use --max-time instead of timeout command (more portable)
    local response=$(curl -s -k --connect-timeout 10 --max-time 60 -G \
        --data-urlencode "query=${query}" \
        --data-urlencode "start=${start_time}" \
        --data-urlencode "end=${end_time}" \
        --data-urlencode "step=300" \
        -H "Authorization: Bearer ${token}" \
        "${endpoint}/api/v1/query_range" 2>&1)
    
    local curl_exit=$?
    
    # Check for timeout
    if [ $curl_exit -ne 0 ] || echo "$response" | grep -q "timed out\|timeout\|Operation timed out"; then
        echo ""
        return 1
    fi
    
    # Check for HTTP/HTTPS mismatch error
    if echo "$response" | grep -q "Client sent an HTTP request to an HTTPS server"; then
        # If endpoint was HTTP, try HTTPS instead
        if [[ "$endpoint" == http://* ]]; then
            endpoint="${endpoint/http:/https:}"
            response=$(curl -s -k --connect-timeout 10 --max-time 60 -G \
                --data-urlencode "query=${query}" \
                --data-urlencode "start=${start_time}" \
                --data-urlencode "end=${end_time}" \
                --data-urlencode "step=300" \
                -H "Authorization: Bearer ${token}" \
                "${endpoint}/api/v1/query_range" 2>&1)
            curl_exit=$?
        fi
    fi
    
    # Filter out error messages
    local error_msg=$(echo "$response" | grep -i "error\|Client sent\|SSL\|certificate" || true)
    if [ -n "$error_msg" ] && [ -z "$(echo "$response" | grep -o '{"status"')" ]; then
        # Response contains error, not JSON
        echo ""
        return 1
    fi
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
    else
        echo ""
    fi
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [ "$bytes" == "N/A" ] || [ -z "$bytes" ]; then
        echo "N/A"
        return
    fi
    
    # Use awk for calculation if available
    if command -v awk &> /dev/null; then
        local result=$(echo "$bytes" | awk '{
            if ($1 >= 1073741824) printf "%.2fGi", $1/1073741824
            else if ($1 >= 1048576) printf "%.2fMi", $1/1048576
            else if ($1 >= 1024) printf "%.2fKi", $1/1024
            else printf "%.0fB", $1
        }')
        echo "$result"
    else
        echo "${bytes}B"
    fi
}

# Function to format CPU
format_cpu() {
    local cpu=$1
    if [ "$cpu" == "N/A" ] || [ -z "$cpu" ]; then
        echo "N/A"
        return
    fi
    
    # Use awk for calculation
    if command -v awk &> /dev/null; then
        local result=$(echo "$cpu" | awk '{
            if ($1 >= 1) printf "%.2f cores", $1
            else printf "%.0fm", $1*1000
        }')
        echo "$result"
    else
        echo "${cpu}"
    fi
}

# Step 1: Check if namespace exists
echo -e "${BLUE}Step 1: Checking if namespace exists...${NC}"
if oc get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${GREEN}✓ Namespace '$NAMESPACE' exists${NC}"
else
    echo -e "${RED}✗ Namespace '$NAMESPACE' does not exist${NC}"
    echo "Please deploy workloads first using: ./deploy-offline-workloads.sh"
    exit 1
fi
echo ""

# Step 2: Check if CronJobs exist
echo -e "${BLUE}Step 2: Checking if CronJobs exist...${NC}"
declare -a EXPECTED_CRONJOBS=("simple-cpu-workload" "simple-memory-workload" "file-io-workload" "network-workload" "combined-workload")
CRONJOBS_FOUND=0
CRONJOBS_MISSING=0

for cronjob in "${EXPECTED_CRONJOBS[@]}"; do
    if oc get cronjob "$cronjob" -n "$NAMESPACE" &> /dev/null; then
        echo -e "${GREEN}  ✓ CronJob '$cronjob' exists${NC}"
        CRONJOBS_FOUND=$((CRONJOBS_FOUND + 1))
    else
        echo -e "${YELLOW}  ✗ CronJob '$cronjob' not found${NC}"
        CRONJOBS_MISSING=$((CRONJOBS_MISSING + 1))
    fi
done

echo ""
if [ $CRONJOBS_MISSING -gt 0 ]; then
    echo -e "${YELLOW}Warning: $CRONJOBS_MISSING CronJob(s) missing. Some metrics may not be available.${NC}"
fi
echo ""

# Step 3: Check if Jobs/Pods exist
echo -e "${BLUE}Step 3: Checking if Jobs and Pods exist...${NC}"
JOBS_COUNT=$(oc get jobs -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
PODS_COUNT=$(oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$JOBS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}  ✓ Found $JOBS_COUNT job(s)${NC}"
else
    echo -e "${YELLOW}  ⚠ No jobs found. Workloads may not have been triggered yet.${NC}"
fi

if [ "$PODS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}  ✓ Found $PODS_COUNT pod(s)${NC}"
    echo ""
    echo "  Pod status:"
    oc get pods -n "$NAMESPACE" --no-headers | awk '{print "    " $1 " - " $3}' | head -5
else
    echo -e "${YELLOW}  ⚠ No pods found. Workloads may not be running.${NC}"
fi
echo ""

# Step 4: Query Thanos
echo -e "${BLUE}Step 4: Querying Thanos for metrics...${NC}"
echo ""

# Get Thanos endpoint
THANOS_ENDPOINT=$(get_thanos_endpoint)
echo "Thanos endpoint: $THANOS_ENDPOINT"

# Setup port-forward if needed
if [[ "$THANOS_ENDPOINT" == "http://localhost:9091" ]]; then
    setup_port_forward "$THANOS_ENDPOINT"
    trap cleanup_port_forward EXIT
fi

# Test connection
echo "Testing connection to Thanos..."
token=$(oc whoami -t)
test_response=$(curl -s -k --connect-timeout 10 --max-time 30 -G \
    --data-urlencode "query=up" \
    -H "Authorization: Bearer ${token}" \
    "${THANOS_ENDPOINT}/api/v1/query" 2>&1)

# Check for HTTP/HTTPS mismatch
if echo "$test_response" | grep -q "Client sent an HTTP request to an HTTPS server"; then
    echo -e "${YELLOW}Detected HTTPS requirement, switching endpoint...${NC}"
    if [[ "$THANOS_ENDPOINT" == http://* ]]; then
        THANOS_ENDPOINT="${THANOS_ENDPOINT/http:/https:}"
        echo "Updated endpoint: $THANOS_ENDPOINT"
        test_response=$(curl -s -k --connect-timeout 10 --max-time 30 -G \
            --data-urlencode "query=up" \
            -H "Authorization: Bearer ${token}" \
            "${THANOS_ENDPOINT}/api/v1/query" 2>&1)
    fi
fi

# Check if response contains error
if echo "$test_response" | grep -qi "error\|Client sent"; then
    if [ -z "$(echo "$test_response" | grep -o '{"status"')" ]; then
        echo -e "${RED}Error: Cannot connect to Thanos.${NC}"
        echo "Response: $test_response"
        echo ""
        echo "Please check:"
        echo "  1. Thanos Query service is running"
        echo "  2. You have proper permissions"
        echo "  3. Network connectivity"
        echo "  4. Endpoint protocol (HTTP vs HTTPS)"
        exit 1
    fi
fi

if [ $? -ne 0 ] || [ -z "$test_response" ]; then
    echo -e "${RED}Error: Cannot connect to Thanos. Please check:${NC}"
    echo "  1. Thanos Query service is running"
    echo "  2. You have proper permissions"
    echo "  3. Network connectivity"
    exit 1
fi

echo -e "${GREEN}Connection successful!${NC}"
echo "Thanos Endpoint: ${THANOS_ENDPOINT}"
echo ""

# Test if the acm_rs metrics exist
echo "Checking if acm_rs metrics are available..."
test_metric_response=$(curl -s -k --connect-timeout 10 --max-time 30 -G \
    --data-urlencode "query=acm_rs:namespace:cpu_usage{namespace=\"${NAMESPACE}\"}" \
    -H "Authorization: Bearer $(oc whoami -t)" \
    "${THANOS_ENDPOINT}/api/v1/query" 2>&1)

if echo "$test_metric_response" | grep -q '"status":"success"'; then
    # Check if we got actual data
    if echo "$test_metric_response" | grep -q '"result":\[\]'; then
        echo -e "${YELLOW}Warning: Metrics query succeeded but no data found for namespace '${NAMESPACE}'${NC}"
        echo "This could mean:"
        echo "  1. Workloads haven't been running long enough to generate metrics"
        echo "  2. The namespace name is incorrect"
        echo "  3. Metrics collection hasn't started yet"
        echo ""
        echo "The script will continue but may show 'N/A' for all metrics."
    else
        echo -e "${GREEN}Metrics are available!${NC}"
    fi
else
    echo -e "${YELLOW}Warning: Could not verify metrics availability${NC}"
    echo "Response: $(echo "$test_metric_response" | head -3)"
fi
echo ""

# Calculate time range (last 4 hours)
END_TIME=$(date +%s)
START_TIME=$((END_TIME - 14400))  # 4 hours ago (4 * 60 * 60 = 14400 seconds)

echo "Query time range:"
echo "  Start: $(date -r $START_TIME 2>/dev/null || date -d @$START_TIME 2>/dev/null || echo "N/A")"
echo "  End: $(date -r $END_TIME 2>/dev/null || date -d @$END_TIME 2>/dev/null || echo "N/A")"
echo ""

# Metrics to query - 6 metrics total
declare -a CPU_METRICS=("cpu_request" "cpu_usage" "cpu_recommendation")
declare -a MEMORY_METRICS=("memory_request" "memory_usage" "memory_recommendation")

echo "Metrics to be queried (6 total):"
echo "  CPU Metrics (3):"
for metric in "${CPU_METRICS[@]}"; do
    echo "    - acm_rs:namespace:${metric}"
done
echo "  Memory Metrics (3):"
for metric in "${MEMORY_METRICS[@]}"; do
    echo "    - acm_rs:namespace:${metric}"
done
echo ""

echo "=========================================="
echo "CPU Metrics for namespace: $NAMESPACE"
echo "=========================================="
echo ""

for metric in "${CPU_METRICS[@]}"; do
    echo -e "${BLUE}Metric: acm_rs:namespace:${metric}${NC}"
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT" 2>&1)
    if [ "$value" != "N/A" ] && [ -n "$value" ] && ! echo "$value" | grep -q "error\|Error\|timeout"; then
        formatted_value=$(format_cpu "$value")
        echo -e "  ${GREEN}✓${NC} Current value: ${GREEN}$formatted_value${NC}"
    else
        if echo "$value" | grep -q "error\|Error\|timeout"; then
            echo -e "  ${RED}✗${NC} Error: $(echo "$value" | head -1)${NC}"
        else
            echo -e "  ${RED}✗${NC} Current value: ${RED}N/A (metric not found)${NC}"
        fi
    fi
    echo ""
done

echo "=========================================="
echo "Memory Metrics for namespace: $NAMESPACE"
echo "=========================================="
echo ""

for metric in "${MEMORY_METRICS[@]}"; do
    echo -e "${BLUE}Metric: acm_rs:namespace:${metric}${NC}"
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT" 2>&1)
    if [ "$value" != "N/A" ] && [ -n "$value" ] && ! echo "$value" | grep -q "error\|Error\|timeout"; then
        formatted_value=$(format_bytes "$value")
        echo -e "  ${GREEN}✓${NC} Current value: ${GREEN}$formatted_value${NC}"
    else
        if echo "$value" | grep -q "error\|Error\|timeout"; then
            echo -e "  ${RED}✗${NC} Error: $(echo "$value" | head -1)${NC}"
        else
            echo -e "  ${RED}✗${NC} Current value: ${RED}N/A (metric not found)${NC}"
        fi
    fi
    echo ""
done

# Step 5: Get time series data for last 4 hours
echo "=========================================="
echo "Time Series Data (Last 4 Hours)"
echo "=========================================="
echo ""

# Function to display time series for a metric
display_time_series() {
    local metric=$1
    local namespace=$2
    local endpoint=$3
    local start_time=$4
    local end_time=$5
    local metric_type=$6  # "cpu" or "memory"
    
    # Capitalize first letter (bash 3.2 compatible)
    if [ "$metric_type" = "cpu" ]; then
        local capitalized_type="CPU"
    else
        local capitalized_type="Memory"
    fi
    
    echo -e "${BLUE}${capitalized_type} ${metric} Over Time:${NC}"
    local data=$(query_time_series "$metric" "$namespace" "$endpoint" "$start_time" "$end_time")
    if [ -n "$data" ] && command -v jq &> /dev/null; then
        local count=$(echo "$data" | jq -r '.data.result[0].values | length' 2>/dev/null || echo "0")
        if [ "$count" -gt 0 ]; then
            echo "$data" | jq -r '.data.result[0].values[]? | "\(.[0] | todate | strftime("%Y-%m-%d %H:%M:%S")): \(.[1])"' 2>/dev/null | head -36
        else
            echo -e "  ${YELLOW}No time series data available${NC}"
        fi
    else
        if [ -z "$data" ]; then
            echo -e "  ${YELLOW}No time series data available${NC}"
        else
            echo "  Query executed. Install 'jq' for better formatting."
        fi
    fi
    echo ""
}

# Display time series for CPU metrics
for metric in "${CPU_METRICS[@]}"; do
    display_time_series "$metric" "$NAMESPACE" "$THANOS_ENDPOINT" "$START_TIME" "$END_TIME" "CPU"
done

# Display time series for Memory metrics
for metric in "${MEMORY_METRICS[@]}"; do
    display_time_series "$metric" "$NAMESPACE" "$THANOS_ENDPOINT" "$START_TIME" "$END_TIME" "Memory"
done

# Step 6: Comprehensive Summary Table
echo "=========================================="
echo "All Metrics Summary"
echo "=========================================="
echo ""
echo "All 6 metrics queried:"
echo "  CPU Metrics:"
for metric in "${CPU_METRICS[@]}"; do
    echo "    - acm_rs:namespace:${metric}"
done
echo "  Memory Metrics:"
for metric in "${MEMORY_METRICS[@]}"; do
    echo "    - acm_rs:namespace:${metric}"
done
echo ""

printf "%-45s %-30s %-20s %-10s\n" "Metric" "Current Value (Formatted)" "Raw Value" "Status"
echo "------------------------------------------------------------------------------------------------------------------------"
for metric in "${CPU_METRICS[@]}"; do
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT")
    formatted_value=$(format_cpu "$value")
    if [ "$value" != "N/A" ] && [ -n "$value" ]; then
        status="${GREEN}✓${NC}"
        raw_value="$value"
    else
        status="${RED}✗${NC}"
        raw_value="N/A"
    fi
    printf "%-45s %-30s %-20s %-10s\n" "acm_rs:namespace:${metric}" "$formatted_value" "$raw_value" "$status"
done
for metric in "${MEMORY_METRICS[@]}"; do
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT")
    formatted_value=$(format_bytes "$value")
    if [ "$value" != "N/A" ] && [ -n "$value" ]; then
        status="${GREEN}✓${NC}"
        raw_value="$value"
    else
        status="${RED}✗${NC}"
        raw_value="N/A"
    fi
    printf "%-45s %-30s %-20s %-10s\n" "acm_rs:namespace:${metric}" "$formatted_value" "$raw_value" "$status"
done
echo ""

# Step 7: Detailed Values Table
echo "=========================================="
echo "Detailed Metric Values"
echo "=========================================="
echo ""
echo "CPU Metrics:"
echo "------------"
for metric in "${CPU_METRICS[@]}"; do
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT")
    formatted_value=$(format_cpu "$value")
    echo "  acm_rs:namespace:${metric}:"
    echo "    Formatted: $formatted_value"
    echo "    Raw: $value"
    echo ""
done

echo "Memory Metrics:"
echo "---------------"
for metric in "${MEMORY_METRICS[@]}"; do
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT")
    formatted_value=$(format_bytes "$value")
    echo "  acm_rs:namespace:${metric}:"
    echo "    Formatted: $formatted_value"
    echo "    Raw: $value"
    echo ""
done
echo ""

echo -e "${GREEN}Check complete!${NC}"
echo ""
echo "To view raw metric data, you can query Thanos directly:"
echo "  oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091"
echo "  Then visit: http://localhost:9091"
echo ""
echo "To query specific metrics manually:"
echo "  curl -k -G --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace=\"$NAMESPACE\"}' \\"
echo "    -H \"Authorization: Bearer \$(oc whoami -t)\" \\"
echo "    \"$THANOS_ENDPOINT/api/v1/query\""
