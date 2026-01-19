#!/bin/bash

# Script to deploy workloads, wait 20 minutes, and query Thanos for metrics
# This script tests CPU and memory utilization metrics from Thanos database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="offline-workload"
WAIT_TIME=1200  # 20 minutes in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Thanos Metrics Test Script"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Wait time: 20 minutes"
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
        --data-urlencode "step=60" \
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
                --data-urlencode "step=60" \
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

# Step 1: Deploy workloads
echo -e "${BLUE}Step 1: Deploying workloads...${NC}"
echo ""

# Create namespace
echo "Creating namespace: $NAMESPACE"
oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - > /dev/null

# Deploy all workloads
echo "Deploying CronJobs..."
for file in simple-cpu-workload.yaml simple-memory-workload.yaml file-io-workload.yaml network-workload.yaml combined-workload.yaml; do
    if [ -f "$SCRIPT_DIR/workloads/$file" ]; then
        echo "  - Deploying $file..."
        oc apply -f "$SCRIPT_DIR/workloads/$file" > /dev/null
    fi
done

echo ""
echo -e "${GREEN}Workloads deployed successfully!${NC}"
echo ""

# Trigger workloads immediately
echo -e "${BLUE}Triggering workloads...${NC}"
TIMESTAMP=$(date +%s)
oc create job --from=cronjob/simple-cpu-workload cpu-test-$TIMESTAMP -n "$NAMESPACE" > /dev/null 2>&1 || true
oc create job --from=cronjob/simple-memory-workload memory-test-$TIMESTAMP -n "$NAMESPACE" > /dev/null 2>&1 || true
oc create job --from=cronjob/file-io-workload io-test-$TIMESTAMP -n "$NAMESPACE" > /dev/null 2>&1 || true
oc create job --from=cronjob/network-workload network-test-$TIMESTAMP -n "$NAMESPACE" > /dev/null 2>&1 || true
oc create job --from=cronjob/combined-workload combined-test-$TIMESTAMP -n "$NAMESPACE" > /dev/null 2>&1 || true

echo -e "${GREEN}Workloads triggered!${NC}"
echo ""

# Step 2: Wait 20 minutes
echo -e "${BLUE}Step 2: Waiting 20 minutes for metrics to accumulate...${NC}"
START_WAIT=$(date)
echo "Start time: $START_WAIT"
echo ""

# Show progress
for i in {1..20}; do
    elapsed=$((i * 60))
    remaining=$((1200 - elapsed))
    echo -ne "\r${YELLOW}Progress: ["
    for j in {1..20}; do
        if [ $j -le $i ]; then
            echo -ne "█"
        else
            echo -ne "░"
        fi
    done
    echo -ne "] ${i}/20 minutes (${remaining}s remaining)${NC}"
    sleep 60
done
echo ""
echo ""
END_WAIT=$(date)
echo -e "${GREEN}Wait complete! End time: $END_WAIT${NC}"
echo ""

# Step 3: Query Thanos
echo -e "${BLUE}Step 3: Querying Thanos for metrics...${NC}"
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

# Calculate time range (last 20 minutes)
END_TIME=$(date +%s)
START_TIME=$((END_TIME - 1200))  # 20 minutes ago

echo "Query time range:"
echo "  Start: $(date -r $START_TIME 2>/dev/null || date -d @$START_TIME 2>/dev/null || echo "N/A")"
echo "  End: $(date -r $END_TIME 2>/dev/null || date -d @$END_TIME 2>/dev/null || echo "N/A")"
echo ""

# Metrics to query
declare -a CPU_METRICS=("cpu_request_hard" "cpu_request" "cpu_usage" "cpu_recommendation")
declare -a MEMORY_METRICS=("memory_request_hard" "memory_request" "memory_usage" "memory_recommendation")

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

# Step 4: Get time series data for last 20 minutes
echo "=========================================="
echo "Time Series Data (Last 20 Minutes)"
echo "=========================================="
echo ""

echo -e "${BLUE}CPU Usage Over Time:${NC}"
cpu_usage_data=$(query_time_series "cpu_usage" "$NAMESPACE" "$THANOS_ENDPOINT" "$START_TIME" "$END_TIME")
if [ -n "$cpu_usage_data" ] && command -v jq &> /dev/null; then
    echo "$cpu_usage_data" | jq -r '.data.result[0].values[]? | "\(.[0] | todate | strftime("%Y-%m-%d %H:%M:%S")): \(.[1])"' 2>/dev/null | head -20 || echo "  Unable to parse time series data"
else
    echo "  Query executed. Install 'jq' for better formatting."
    echo "  Raw response available in variable cpu_usage_data"
fi
echo ""

echo -e "${BLUE}Memory Usage Over Time:${NC}"
memory_usage_data=$(query_time_series "memory_usage" "$NAMESPACE" "$THANOS_ENDPOINT" "$START_TIME" "$END_TIME")
if [ -n "$memory_usage_data" ] && command -v jq &> /dev/null; then
    echo "$memory_usage_data" | jq -r '.data.result[0].values[]? | "\(.[0] | todate | strftime("%Y-%m-%d %H:%M:%S")): \(.[1])"' 2>/dev/null | head -20 || echo "  Unable to parse time series data"
else
    echo "  Query executed. Install 'jq' for better formatting."
    echo "  Raw response available in variable memory_usage_data"
fi
echo ""

# Summary table
echo "=========================================="
echo "Summary Table"
echo "=========================================="
echo ""
printf "%-35s %-25s %-10s\n" "Metric" "Current Value" "Status"
echo "--------------------------------------------------------------------------------"
for metric in "${CPU_METRICS[@]}"; do
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT")
    formatted_value=$(format_cpu "$value")
    if [ "$value" != "N/A" ] && [ -n "$value" ]; then
        status="${GREEN}✓${NC}"
    else
        status="${RED}✗${NC}"
    fi
    printf "%-35s %-25s %-10s\n" "acm_rs:namespace:${metric}" "$formatted_value" "$status"
done
for metric in "${MEMORY_METRICS[@]}"; do
    value=$(get_current_metric "$metric" "$NAMESPACE" "$THANOS_ENDPOINT")
    formatted_value=$(format_bytes "$value")
    if [ "$value" != "N/A" ] && [ -n "$value" ]; then
        status="${GREEN}✓${NC}"
    else
        status="${RED}✗${NC}"
    fi
    printf "%-35s %-25s %-10s\n" "acm_rs:namespace:${metric}" "$formatted_value" "$status"
done
echo ""

echo -e "${GREEN}Test complete!${NC}"
echo ""
echo "To view raw metric data, you can query Thanos directly:"
echo "  oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091"
echo "  Then visit: http://localhost:9091"
echo ""
echo "To query specific metrics manually:"
echo "  curl -k -G --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace=\"$NAMESPACE\"}' \\"
echo "    -H \"Authorization: Bearer \$(oc whoami -t)\" \\"
echo "    \"$THANOS_ENDPOINT/api/v1/query\""
