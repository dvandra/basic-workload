#!/bin/bash

# Check Thanos metrics for namespace workloads
# Queries acm_rs:namespace:* metrics from the Hub cluster
#
# NOTE: Thanos runs on the Hub cluster, so this script switches to the Hub context

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source configuration if available
if [[ -f "$ROOT_DIR/config.sh" ]]; then
    source "$ROOT_DIR/config.sh"
fi

NAMESPACE="${NAMESPACE_WORKLOAD_NS:-offline-workload}"
HUB_CONTEXT="${HUB_CONTEXT_NAME:-hub}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Namespace Workload Metrics Check"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Metrics: acm_rs:namespace:*"
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc command not found. Please install OpenShift CLI.${NC}"
    exit 1
fi

# Switch to Hub context (where Thanos runs)
echo -e "${BLUE}Switching to Hub cluster context: $HUB_CONTEXT${NC}"
if ! oc config use-context "$HUB_CONTEXT" &>/dev/null; then
    echo -e "${RED}Error: Could not switch to Hub context '$HUB_CONTEXT'${NC}"
    echo "Please ensure the Hub context is configured. Run: oc config get-contexts"
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Hub cluster. Please run 'oc login' first.${NC}"
    exit 1
fi

echo -e "${GREEN}Connected to Hub: $(oc whoami) @ $(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}')${NC}"
echo ""

# Get Thanos endpoint from Hub cluster
get_thanos_endpoint() {
    local route=$(oc get route -n openshift-monitoring thanos-querier -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [ -n "$route" ]; then
        echo "https://${route}"
    else
        echo "http://localhost:9091"
    fi
}

THANOS_ENDPOINT=$(get_thanos_endpoint)
echo "Thanos Endpoint: $THANOS_ENDPOINT"
echo ""

# Function to query metric
query_metric() {
    local metric=$1
    local query="last_over_time(acm_rs:namespace:${metric}{namespace=\"${NAMESPACE}\"}[30m])"
    
    local response=$(curl -s -k --connect-timeout 10 --max-time 30 -G \
        --data-urlencode "query=${query}" \
        -H "Authorization: Bearer $(oc whoami -t)" \
        "${THANOS_ENDPOINT}/api/v1/query" 2>&1)
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq -r '.data.result[0].value[1] // "N/A"' 2>/dev/null
    else
        echo "$response" | grep -o '"value":\["[^"]*","[^"]*"\]' | sed 's/.*","\([^"]*\)".*/\1/' | head -1
    fi
}

# Check if metric names exist in Thanos (using last_over_time for stale data)
echo "Step 1: Checking if acm_rs:namespace:* metrics are registered in Thanos..."
global_check=$(curl -s -k --connect-timeout 10 --max-time 30 -G \
    --data-urlencode "query=count(last_over_time(acm_rs:namespace:cpu_request[30m]))" \
    -H "Authorization: Bearer $(oc whoami -t)" \
    "${THANOS_ENDPOINT}/api/v1/query" 2>&1)

if echo "$global_check" | grep -q '"result":\[\]'; then
    echo -e "${RED}✗ acm_rs:namespace:* metrics NOT FOUND in Thanos${NC}"
    echo ""
    echo "Please verify:"
    echo "  1. ACM Operator is installed on Hub (version 2.14+)"
    echo "  2. Multicluster Observability (MCO) is deployed on Hub"
    echo "  3. Spoke cluster is registered and connected"
    exit 1
else
    echo -e "${GREEN}✓ Metrics are registered in Thanos${NC}"
fi
echo ""

# Check if namespace has data
echo "Step 2: Checking if metrics have data for namespace '${NAMESPACE}'..."
ns_check=$(curl -s -k --connect-timeout 10 --max-time 30 -G \
    --data-urlencode "query=last_over_time(acm_rs:namespace:cpu_usage{namespace=\"${NAMESPACE}\"}[30m])" \
    -H "Authorization: Bearer $(oc whoami -t)" \
    "${THANOS_ENDPOINT}/api/v1/query" 2>&1)

if echo "$ns_check" | grep -q '"result":\[\]'; then
    echo -e "${YELLOW}⚠ No data found for namespace '${NAMESPACE}'${NC}"
    echo "Workloads may need more time to generate metrics (wait 15-20 minutes)"
else
    echo -e "${GREEN}✓ Data available for namespace '${NAMESPACE}'${NC}"
fi
echo ""

# Query all metrics
echo "=========================================="
echo "Current Metric Values"
echo "=========================================="
echo ""

declare -a METRICS=("cpu_request" "cpu_usage" "cpu_recommendation" "memory_request" "memory_usage" "memory_recommendation")

printf "%-40s %-20s\n" "Metric" "Value"
echo "------------------------------------------------------------"

for metric in "${METRICS[@]}"; do
    value=$(query_metric "$metric")
    if [ "$value" != "N/A" ] && [ -n "$value" ]; then
        printf "%-40s ${GREEN}%-20s${NC}\n" "acm_rs:namespace:${metric}" "$value"
    else
        printf "%-40s ${RED}%-20s${NC}\n" "acm_rs:namespace:${metric}" "N/A"
    fi
done

echo ""
echo -e "${GREEN}Check complete!${NC}"
