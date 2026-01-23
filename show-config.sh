#!/bin/bash

# =============================================================================
# Show Current Configuration
# =============================================================================
# Displays all environment variables and their values that will be used
# by the workload scripts. Run this before ./run-all.sh to verify your setup.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  ACM Observability Workloads - Configuration Check${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Source config to get defaults
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    # Suppress the SSH warning when sourcing
    source "$SCRIPT_DIR/config.sh" 2>/dev/null
fi

# Function to check if value is set or using default
check_value() {
    local name=$1
    local value=$2
    local default=$3
    local required=$4
    
    if [[ -z "$value" ]]; then
        if [[ "$required" == "yes" ]]; then
            echo -e "  ${RED}✗${NC} $name: ${RED}NOT SET (REQUIRED)${NC}"
            return 1
        else
            echo -e "  ${YELLOW}○${NC} $name: ${YELLOW}not set${NC} (optional)"
        fi
    elif [[ "$value" == "$default" ]]; then
        echo -e "  ${GREEN}✓${NC} $name: $value ${BLUE}(default)${NC}"
    else
        echo -e "  ${GREEN}✓${NC} $name: $value"
    fi
    return 0
}

# Track errors
ERRORS=0

# -----------------------------------------------------------------------------
echo -e "${BLUE}Cluster Contexts:${NC}"
echo ""

# Function to get cluster URL for a context
get_cluster_url() {
    local context=$1
    if oc config use-context "$context" &>/dev/null 2>&1; then
        oc config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null
    else
        echo "N/A"
    fi
}

# Get URLs for each context
HUB_URL=$(get_cluster_url "$HUB_CONTEXT_NAME")
NS_SPOKE_URL=$(get_cluster_url "$NAMESPACE_SPOKE_CONTEXT_NAME")
VM_SPOKE_URL=$(get_cluster_url "$VM_SPOKE_CONTEXT_NAME")

check_value "HUB_CONTEXT_NAME" "$HUB_CONTEXT_NAME" "hub" "yes" || ERRORS=$((ERRORS+1))
if [[ -n "$HUB_URL" && "$HUB_URL" != "N/A" ]]; then
    echo -e "      ${CYAN}→ $HUB_URL${NC}"
fi

check_value "NAMESPACE_SPOKE_CONTEXT_NAME" "$NAMESPACE_SPOKE_CONTEXT_NAME" "$HUB_CONTEXT_NAME" "no"
if [[ "$NAMESPACE_SPOKE_CONTEXT_NAME" != "$HUB_CONTEXT_NAME" && -n "$NS_SPOKE_URL" && "$NS_SPOKE_URL" != "N/A" ]]; then
    echo -e "      ${CYAN}→ $NS_SPOKE_URL${NC}"
elif [[ "$NAMESPACE_SPOKE_CONTEXT_NAME" == "$HUB_CONTEXT_NAME" ]]; then
    echo -e "      ${CYAN}→ (same as Hub)${NC}"
fi

check_value "VM_SPOKE_CONTEXT_NAME" "$VM_SPOKE_CONTEXT_NAME" "$HUB_CONTEXT_NAME" "no"
if [[ "$VM_SPOKE_CONTEXT_NAME" != "$HUB_CONTEXT_NAME" && -n "$VM_SPOKE_URL" && "$VM_SPOKE_URL" != "N/A" ]]; then
    echo -e "      ${CYAN}→ $VM_SPOKE_URL${NC}"
elif [[ "$VM_SPOKE_CONTEXT_NAME" == "$HUB_CONTEXT_NAME" ]]; then
    echo -e "      ${CYAN}→ (same as Hub)${NC}"
fi

if [[ "$NAMESPACE_SPOKE_CONTEXT_NAME" == "$HUB_CONTEXT_NAME" && "$VM_SPOKE_CONTEXT_NAME" == "$HUB_CONTEXT_NAME" ]]; then
    echo ""
    echo -e "  ${BLUE}ℹ️  Single cluster mode: All workloads will deploy to Hub${NC}"
fi

echo ""

# -----------------------------------------------------------------------------
echo -e "${BLUE}Namespaces:${NC}"
echo ""

check_value "NAMESPACE_WORKLOAD_NS" "$NAMESPACE_WORKLOAD_NS" "offline-workload" "no"
check_value "VM_WORKLOAD_NS" "$VM_WORKLOAD_NS" "auto-vm-test" "no"

echo ""

# -----------------------------------------------------------------------------
echo -e "${BLUE}SSH Configuration (for VM workloads):${NC}"
echo ""

if [[ -n "$VM_SSH_PUBLIC_KEY" ]]; then
    # Show truncated key
    KEY_LENGTH=${#VM_SSH_PUBLIC_KEY}
    KEY_PREVIEW="${VM_SSH_PUBLIC_KEY:0:30}...${VM_SSH_PUBLIC_KEY: -20}"
    echo -e "  ${GREEN}✓${NC} VM_SSH_PUBLIC_KEY: ${KEY_LENGTH} chars"
    echo -e "      ${BLUE}Preview: $KEY_PREVIEW${NC}"
else
    echo -e "  ${RED}✗${NC} VM_SSH_PUBLIC_KEY: ${RED}NOT SET${NC}"
    echo -e "      ${YELLOW}Required for VM workloads. Set with:${NC}"
    echo -e "      ${CYAN}export VM_SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_rsa.pub)\"${NC}"
    ERRORS=$((ERRORS+1))
fi

check_value "VM_SSH_USER" "$VM_SSH_USER" "fedora" "no"

echo ""

# -----------------------------------------------------------------------------
echo -e "${BLUE}Timing:${NC}"
echo ""

WAIT_MINS=$((METRICS_WAIT_TIME / 60))
echo -e "  ${GREEN}✓${NC} METRICS_WAIT_TIME: ${METRICS_WAIT_TIME}s (${WAIT_MINS} minutes)"
check_value "VM_STRESS_DURATION" "$VM_STRESS_DURATION" "5m" "no"

echo ""

# -----------------------------------------------------------------------------
echo -e "${BLUE}Context Connectivity:${NC}"
echo ""

# Store server URLs in simple variables (bash 3.x compatible)
HUB_SERVER_URL=""
NS_SPOKE_SERVER_URL=""
VM_SPOKE_SERVER_URL=""

check_context() {
    local context=$1
    local desc=$2
    local var_name=$3
    
    if oc config use-context "$context" &>/dev/null; then
        if oc whoami &>/dev/null 2>&1; then
            local user=$(oc whoami 2>/dev/null)
            local server=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
            # Store server URL in the appropriate variable
            eval "${var_name}=\"${server}\""
            echo -e "  ${GREEN}✓${NC} $desc ($context): $user @ $server"
            return 0
        else
            echo -e "  ${RED}✗${NC} $desc ($context): ${RED}Auth failed - token may be expired${NC}"
            return 1
        fi
    else
        echo -e "  ${RED}✗${NC} $desc ($context): ${RED}Context not found${NC}"
        return 1
    fi
}

check_context "$HUB_CONTEXT_NAME" "Hub" "HUB_SERVER_URL" || ERRORS=$((ERRORS+1))

if [[ "$NAMESPACE_SPOKE_CONTEXT_NAME" != "$HUB_CONTEXT_NAME" ]]; then
    check_context "$NAMESPACE_SPOKE_CONTEXT_NAME" "Namespace Spoke" "NS_SPOKE_SERVER_URL" || ERRORS=$((ERRORS+1))
else
    NS_SPOKE_SERVER_URL="$HUB_SERVER_URL"
fi

if [[ "$VM_SPOKE_CONTEXT_NAME" != "$HUB_CONTEXT_NAME" && "$VM_SPOKE_CONTEXT_NAME" != "$NAMESPACE_SPOKE_CONTEXT_NAME" ]]; then
    check_context "$VM_SPOKE_CONTEXT_NAME" "VM Spoke" "VM_SPOKE_SERVER_URL" || ERRORS=$((ERRORS+1))
elif [[ "$VM_SPOKE_CONTEXT_NAME" == "$HUB_CONTEXT_NAME" ]]; then
    VM_SPOKE_SERVER_URL="$HUB_SERVER_URL"
else
    VM_SPOKE_SERVER_URL="$NS_SPOKE_SERVER_URL"
fi

echo ""

# -----------------------------------------------------------------------------
echo -e "${BLUE}Cluster Analysis:${NC}"
echo ""

# Check if Hub and Namespace Spoke are the same cluster
if [[ "$NAMESPACE_SPOKE_CONTEXT_NAME" == "$HUB_CONTEXT_NAME" ]]; then
    echo -e "  ${BLUE}ℹ️${NC}  Hub & Namespace Spoke: ${CYAN}Same context${NC} (single cluster mode)"
elif [[ "$HUB_SERVER_URL" == "$NS_SPOKE_SERVER_URL" ]]; then
    echo -e "  ${YELLOW}⚠️${NC}  Hub & Namespace Spoke: ${YELLOW}Same cluster${NC} (different context names, same server)"
    echo -e "      Hub server:    $HUB_SERVER_URL"
    echo -e "      NS Spoke server: $NS_SPOKE_SERVER_URL"
else
    echo -e "  ${GREEN}✓${NC} Hub & Namespace Spoke: ${GREEN}Different clusters${NC}"
    echo -e "      Hub:       $HUB_SERVER_URL"
    echo -e "      NS Spoke:  $NS_SPOKE_SERVER_URL"
fi

# Check if Hub and VM Spoke are the same cluster
if [[ "$VM_SPOKE_CONTEXT_NAME" == "$HUB_CONTEXT_NAME" ]]; then
    echo -e "  ${BLUE}ℹ️${NC}  Hub & VM Spoke: ${CYAN}Same context${NC} (single cluster mode)"
elif [[ "$HUB_SERVER_URL" == "$VM_SPOKE_SERVER_URL" ]]; then
    echo -e "  ${YELLOW}⚠️${NC}  Hub & VM Spoke: ${YELLOW}Same cluster${NC} (different context names, same server)"
    echo -e "      Hub server:  $HUB_SERVER_URL"
    echo -e "      VM Spoke:    $VM_SPOKE_SERVER_URL"
else
    echo -e "  ${GREEN}✓${NC} Hub & VM Spoke: ${GREEN}Different clusters${NC}"
    echo -e "      Hub:       $HUB_SERVER_URL"
    echo -e "      VM Spoke:  $VM_SPOKE_SERVER_URL"
fi

# Check if Namespace Spoke and VM Spoke are the same
if [[ "$NAMESPACE_SPOKE_CONTEXT_NAME" != "$VM_SPOKE_CONTEXT_NAME" ]]; then
    if [[ "$NS_SPOKE_SERVER_URL" == "$VM_SPOKE_SERVER_URL" ]]; then
        echo -e "  ${BLUE}ℹ️${NC}  NS Spoke & VM Spoke: ${CYAN}Same cluster${NC}"
    else
        echo -e "  ${GREEN}✓${NC} NS Spoke & VM Spoke: ${GREEN}Different clusters${NC}"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}  ✗ Configuration has $ERRORS issue(s). Please fix before running.${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "See README.md for setup instructions."
    exit 1
else
    echo -e "${GREEN}  ✓ Configuration looks good! Ready to run.${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next step:"
    echo -e "  ${CYAN}./run-all.sh${NC}"
    echo ""
    echo "Or run with options:"
    echo "  ./run-all.sh --skip-vm          # Skip VM workloads"
    echo "  ./run-all.sh --skip-namespace   # Skip namespace workloads"
    echo "  ./run-all.sh --no-wait          # Skip waiting for metrics"
fi

echo ""
