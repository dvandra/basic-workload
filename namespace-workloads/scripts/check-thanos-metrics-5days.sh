#!/bin/bash
#
# Query Thanos for ACM recording-rule metrics (regular + VM) for the last 5 days.
#
# Behavior:
# - Prefers ACM Observability Query Frontend Route (if present)
# - Falls back to OpenShift Monitoring thanos-querier Route (if present)
# - Falls back to port-forward (no token needed) to:
#     1) observability-thanos-query-frontend :9090
#     2) thanos-querier :9091
#
# Outputs:
# - Instant query: sum(metric) and (optional) topk namespaces
# - Range query (last 5 days): sum(metric) time series (prints a small sample)
#
# Usage:
#   ./namespace-workloads/scripts/check-thanos-metrics-5days.sh
#

set -e

# -----------------------------
# Config
# -----------------------------
RANGE_DAYS="${RANGE_DAYS:-5}"
STEP_SECONDS="${STEP_SECONDS:-300}"      # 5 minutes
TOPK_NAMESPACES="${TOPK_NAMESPACES:-5}"  # set 0 to disable topk output

# Prefer ACM Observability (recommended for acm_rs_vm:namespace:* metrics).
# If set to 0, we will allow openshift-monitoring thanos-querier route to be used first.
PREFER_ACM_OBSERVABILITY="${PREFER_ACM_OBSERVABILITY:-1}"

# -----------------------------
# Colors
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PORT_FORWARD_PID=""
THANOS_ENDPOINT=""
NEED_TOKEN="1"

cleanup_port_forward() {
  if [ -n "${PORT_FORWARD_PID:-}" ]; then
    kill "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}Error: '${cmd}' not found in PATH${NC}"
    exit 1
  fi
}

get_token() {
  oc whoami -t 2>/dev/null || true
}

get_route_host() {
  local ns="$1"
  local name="$2"
  oc get route -n "$ns" "$name" -o jsonpath='{.spec.host}' 2>/dev/null || true
}

route_has_tls() {
  local ns="$1"
  local name="$2"
  local tls
  tls="$(oc get route -n "$ns" "$name" -o jsonpath='{.spec.tls}' 2>/dev/null || true)"
  if [ -n "$tls" ] && [ "$tls" != "null" ]; then
    return 0
  fi
  return 1
}

pick_thanos_endpoint() {
  # 1) ACM Observability query-frontend route
  local host
  host="$(get_route_host open-cluster-management-observability observability-thanos-query-frontend)"
  if [ -n "$host" ]; then
    if route_has_tls open-cluster-management-observability observability-thanos-query-frontend; then
      echo "https://${host}"
    else
      echo "http://${host}"
    fi
    return 0
  fi

  # If we prefer ACM Observability and there is no route, go straight to port-forward
  # instead of using openshift-monitoring's thanos-querier (which may not have ACM VM metrics).
  if [ "$PREFER_ACM_OBSERVABILITY" = "1" ]; then
    echo "http://localhost:9090"
    return 0
  fi

  # 2) OpenShift monitoring thanos-querier route (fallback if explicitly allowed)
  host="$(get_route_host openshift-monitoring thanos-querier)"
  if [ -n "$host" ]; then
    if route_has_tls openshift-monitoring thanos-querier; then
      echo "https://${host}"
    else
      echo "http://${host}"
    fi
    return 0
  fi

  # 3) No routes found -> port-forward to localhost (prefer 9090)
  echo "http://localhost:9090"
}

start_port_forward() {
  local endpoint="$1"

  if [[ "$endpoint" == "http://localhost:9090" ]]; then
    echo -e "${YELLOW}No route found. Port-forwarding query-frontend to localhost:9090...${NC}"
    oc -n open-cluster-management-observability port-forward svc/observability-thanos-query-frontend 9090:9090 >/dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    if kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
      NEED_TOKEN="0"
      THANOS_ENDPOINT="http://localhost:9090"
      return 0
    fi
    echo -e "${YELLOW}Query-frontend port-forward failed. Trying thanos-querier to localhost:9091...${NC}"
    oc -n openshift-monitoring port-forward svc/thanos-querier 9091:9091 >/dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    if kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
      THANOS_ENDPOINT="http://localhost:9091"
      NEED_TOKEN="0"
      return 0
    fi
    echo -e "${RED}Error: Failed to establish port-forward to either query-frontend or querier.${NC}"
    exit 1
  fi
}

probe_has_series() {
  # returns 0 if query returns at least 1 series
  local q="$1"
  local body
  body="$(curl_thanos "/api/v1/query" --data-urlencode "query=${q}" 2>/dev/null || true)"
  if ! json_status_ok "$body"; then
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    local n
    n="$(echo "$body" | jq -r '.data.result | length' 2>/dev/null || echo "0")"
    [ "$n" != "0" ] && [ "$n" != "null" ]
    return $?
  fi
  # crude fallback: check for "result":[]
  echo "$body" | grep -q '"result":\[' && ! echo "$body" | grep -q '"result":\[\]'
}

curl_thanos() {
  # Args: <path> <querystring... already urlencoded with --data-urlencode>
  local path="$1"
  shift

  local token=""
  if [ "$NEED_TOKEN" = "1" ]; then
    token="$(get_token)"
    if [ -z "$token" ]; then
      echo -e "${YELLOW}No token available for route access. Falling back to port-forward...${NC}" >&2
      THANOS_ENDPOINT="http://localhost:9090"
      NEED_TOKEN="0"
      start_port_forward "$THANOS_ENDPOINT"
    fi
  fi

  if [ "$NEED_TOKEN" = "1" ]; then
    curl -s -k --connect-timeout 10 --max-time 60 -G \
      -H "Authorization: Bearer ${token}" \
      "$@" \
      "${THANOS_ENDPOINT}${path}"
  else
    curl -s --connect-timeout 10 --max-time 60 -G \
      "$@" \
      "${THANOS_ENDPOINT}${path}"
  fi
}

json_status_ok() {
  echo "$1" | grep -q '"status":"success"'
}

print_json_error() {
  local body="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq -r '.error // .errorType // .status // "unknown error"' 2>/dev/null | head -1
  else
    echo "$body" | head -1
  fi
}

instant_sum() {
  local metric_full="$1"
  local q="sum(${metric_full})"
  local body
  body="$(curl_thanos "/api/v1/query" --data-urlencode "query=${q}" 2>&1)"

  if ! json_status_ok "$body"; then
    echo "Error: $(print_json_error "$body")"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq -r '.data.result[0].value[1] // "N/A"' 2>/dev/null
  else
    # very small fallback
    echo "$body" | grep -o '"value":\["[^"]*","[^"]*"\]' | sed 's/.*","\([^"]*\)".*/\1/' | head -1
  fi
}

instant_topk() {
  local metric_full="$1"
  local k="$2"
  local q="topk(${k}, ${metric_full})"
  local body
  body="$(curl_thanos "/api/v1/query" --data-urlencode "query=${q}" 2>&1)"

  if ! json_status_ok "$body"; then
    echo "Error: $(print_json_error "$body")"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    # prints: namespace=value
    echo "$body" | jq -r '.data.result[]? | "\(.metric.namespace // "unknown")=\(.value[1])"' 2>/dev/null
  else
    echo "Install jq to see topk namespaces"
  fi
}

range_sum_sample() {
  local metric_full="$1"
  local start="$2"
  local end="$3"
  local step="$4"
  local q="sum(${metric_full})"
  local body

  body="$(curl_thanos "/api/v1/query_range" \
    --data-urlencode "query=${q}" \
    --data-urlencode "start=${start}" \
    --data-urlencode "end=${end}" \
    --data-urlencode "step=${step}" 2>&1)"

  if ! json_status_ok "$body"; then
    echo "Error: $(print_json_error "$body")"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    local points
    points="$(echo "$body" | jq -r '.data.result[0].values | length' 2>/dev/null || echo "0")"
    echo "points=${points}"
    # print last 3 points (timestamp + value)
    echo "$body" | jq -r '.data.result[0].values[-3:][]? | "\(. [0])=\(. [1])"' 2>/dev/null
  else
    echo "Install jq to see range sample"
  fi
}

main() {
  require_cmd oc
  require_cmd curl

  if ! oc whoami >/dev/null 2>&1; then
    echo -e "${RED}Error: Not logged in to OpenShift. Run 'oc login' first.${NC}"
    exit 1
  fi

  echo "=========================================="
  echo "Thanos Metrics Check (Last ${RANGE_DAYS} days)"
  echo "=========================================="
  echo ""

  THANOS_ENDPOINT="$(pick_thanos_endpoint)"
  echo "Selected endpoint: ${THANOS_ENDPOINT}"

  if [[ "$THANOS_ENDPOINT" == http://localhost:* ]]; then
    start_port_forward "$THANOS_ENDPOINT"
    trap cleanup_port_forward EXIT
    echo "Port-forward PID: ${PORT_FORWARD_PID}"
  fi

  echo ""
  echo -e "${BLUE}Testing Thanos connectivity...${NC}"
  test_body="$(curl_thanos "/api/v1/query" --data-urlencode "query=up" 2>&1)"
  if ! json_status_ok "$test_body"; then
    echo -e "${RED}Error: Thanos query failed: $(print_json_error "$test_body")${NC}"
    echo "Raw response (first lines):"
    echo "$test_body" | head -5
    exit 1
  fi
  echo -e "${GREEN}Connection OK${NC}"

  # If we ended up using openshift-monitoring route (or any non-local endpoint) and VM metrics
  # are missing, automatically fall back to ACM Observability port-forward (most common setup).
  if [[ "$THANOS_ENDPOINT" != http://localhost:* ]]; then
    if ! probe_has_series "acm_rs_vm:namespace:cpu_usage"; then
      if [ "$PREFER_ACM_OBSERVABILITY" = "1" ]; then
        echo -e "${YELLOW}VM metrics not found on ${THANOS_ENDPOINT}. Switching to ACM Observability query-frontend via port-forward...${NC}"
        THANOS_ENDPOINT="http://localhost:9090"
        NEED_TOKEN="0"
        start_port_forward "$THANOS_ENDPOINT"
        trap cleanup_port_forward EXIT
        echo "Selected endpoint: ${THANOS_ENDPOINT}"
      fi
    fi
  fi

  END_TIME="$(date +%s)"
  START_TIME="$((END_TIME - (RANGE_DAYS * 86400)))"

  echo ""
  echo "Query range:"
  echo "  start=$(date -r "$START_TIME" 2>/dev/null || date -d "@$START_TIME" 2>/dev/null || echo "$START_TIME")"
  echo "  end=$(date -r "$END_TIME" 2>/dev/null || date -d "@$END_TIME" 2>/dev/null || echo "$END_TIME")"
  echo "  step=${STEP_SECONDS}s"

  declare -a CPU_METRICS=("cpu_request" "cpu_usage" "cpu_recommendation")
  declare -a MEM_METRICS=("memory_request" "memory_usage" "memory_recommendation")

  # VM metrics (explicit list / order as requested)
  declare -a VM_CPU_METRICS=("cpu_recommendation" "cpu_usage" "cpu_request")
  declare -a VM_MEM_METRICS=("memory_request" "memory_usage" "memory_recommendation")

  echo ""
  echo "=========================================="
  echo "Instant metrics (sum across all namespaces)"
  echo "=========================================="

  for metric in "${CPU_METRICS[@]}"; do
    full="acm_rs:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    v="$(instant_sum "$full" || true)"
    echo "  sum: $v"
    if [ "${TOPK_NAMESPACES}" -gt 0 ]; then
      echo "  top${TOPK_NAMESPACES}:"
      instant_topk "$full" "$TOPK_NAMESPACES" | sed 's/^/    /' || true
    fi
  done

  for metric in "${MEM_METRICS[@]}"; do
    full="acm_rs:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    v="$(instant_sum "$full" || true)"
    echo "  sum: $v"
    if [ "${TOPK_NAMESPACES}" -gt 0 ]; then
      echo "  top${TOPK_NAMESPACES}:"
      instant_topk "$full" "$TOPK_NAMESPACES" | sed 's/^/    /' || true
    fi
  done

  for metric in "${VM_CPU_METRICS[@]}"; do
    full="acm_rs_vm:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    v="$(instant_sum "$full" || true)"
    echo "  sum: $v"
    if [ "${TOPK_NAMESPACES}" -gt 0 ]; then
      echo "  top${TOPK_NAMESPACES}:"
      instant_topk "$full" "$TOPK_NAMESPACES" | sed 's/^/    /' || true
    fi
  done

  for metric in "${VM_MEM_METRICS[@]}"; do
    full="acm_rs_vm:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    v="$(instant_sum "$full" || true)"
    echo "  sum: $v"
    if [ "${TOPK_NAMESPACES}" -gt 0 ]; then
      echo "  top${TOPK_NAMESPACES}:"
      instant_topk "$full" "$TOPK_NAMESPACES" | sed 's/^/    /' || true
    fi
  done

  echo ""
  echo "=========================================="
  echo "Range metrics (sum over last ${RANGE_DAYS} days, sample output)"
  echo "=========================================="

  for metric in "${CPU_METRICS[@]}"; do
    full="acm_rs:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    range_sum_sample "$full" "$START_TIME" "$END_TIME" "$STEP_SECONDS" | sed 's/^/  /' || true
  done
  for metric in "${MEM_METRICS[@]}"; do
    full="acm_rs:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    range_sum_sample "$full" "$START_TIME" "$END_TIME" "$STEP_SECONDS" | sed 's/^/  /' || true
  done
  for metric in "${VM_CPU_METRICS[@]}"; do
    full="acm_rs_vm:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    range_sum_sample "$full" "$START_TIME" "$END_TIME" "$STEP_SECONDS" | sed 's/^/  /' || true
  done
  for metric in "${VM_MEM_METRICS[@]}"; do
    full="acm_rs_vm:namespace:${metric}"
    echo ""
    echo -e "${BLUE}${full}${NC}"
    range_sum_sample "$full" "$START_TIME" "$END_TIME" "$STEP_SECONDS" | sed 's/^/  /' || true
  done

  echo ""
  echo -e "${GREEN}Done.${NC}"
}

main "$@"

