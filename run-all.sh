#!/bin/bash

# =============================================================================
# Master Orchestration Script for ACM Observability Test Workloads
# =============================================================================
#
# This script runs the complete workflow:
# 1. Verify prerequisites and configuration
# 2. Deploy namespace workloads
# 3. Deploy VM workloads
# 4. Wait for metrics to be available
# 5. Check metrics from Thanos
# 6. Optionally cleanup resources
#
# Usage: ./run-all.sh [--skip-vm] [--skip-namespace] [--cleanup-only] [--no-wait]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() { echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"; }
print_step() { echo -e "${BLUE}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}" >&2; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

# Parse command line arguments
SKIP_VM=false
SKIP_NAMESPACE=false
CLEANUP_ONLY=false
NO_WAIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-vm) SKIP_VM=true; shift ;;
        --skip-namespace) SKIP_NAMESPACE=true; shift ;;
        --cleanup-only) CLEANUP_ONLY=true; shift ;;
        --no-wait) NO_WAIT=true; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-vm         Skip VM workload deployment"
            echo "  --skip-namespace  Skip namespace workload deployment"
            echo "  --cleanup-only    Only cleanup resources (no deployment)"
            echo "  --no-wait         Skip waiting for metrics (check immediately)"
            echo "  -h, --help        Show this help message"
            exit 0
            ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

# =============================================================================
# Step 0: Load Configuration
# =============================================================================
print_header "Loading Configuration"

if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
    print_error "config.sh not found!"
    echo "Please create config.sh from the template and configure your settings."
    exit 1
fi

source "$SCRIPT_DIR/config.sh"

# =============================================================================
# Step 1: Display Configuration and Ask for Confirmation
# =============================================================================
print_header "Configuration Summary"

echo "Cluster Contexts:"
echo "  Hub:              $HUB_CONTEXT_NAME"
echo "  Namespace Spoke:  $NAMESPACE_SPOKE_CONTEXT_NAME"
echo "  VM Spoke:         $VM_SPOKE_CONTEXT_NAME"
echo ""
echo "Namespaces:"
echo "  Namespace Workloads: $NAMESPACE_WORKLOAD_NS"
echo "  VM Workloads:        $VM_WORKLOAD_NS"
echo ""
echo "Timing:"
echo "  Metrics Wait Time:   $METRICS_WAIT_TIME seconds ($(($METRICS_WAIT_TIME / 60)) minutes)"
echo "  VM Stress Duration:  $VM_STRESS_DURATION"
echo ""
echo "SSH Configuration:"
if [[ -n "$VM_SSH_PUBLIC_KEY" ]]; then
    echo "  Public Key:  Configured (${#VM_SSH_PUBLIC_KEY} chars)"
else
    echo -e "  Public Key:  ${RED}NOT CONFIGURED${NC}"
fi
echo ""

# Validate SSH key for VM workloads
if [[ "$SKIP_VM" != "true" && -z "$VM_SSH_PUBLIC_KEY" ]]; then
    print_warning "VM_SSH_PUBLIC_KEY is not set but VM workloads are enabled!"
    echo ""
    echo "VMs require an SSH public key for access. Set it with:"
    echo -e "  ${CYAN}export VM_SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_rsa.pub)\"${NC}"
    echo ""
    read -p "Continue without SSH key? VMs may not be accessible. (y/N): " ssh_confirm
    if [[ ! "$ssh_confirm" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Please set VM_SSH_PUBLIC_KEY and try again."
        echo "Or use --skip-vm to skip VM workloads."
        exit 1
    fi
fi

# =============================================================================
# Step 2: Verify Prerequisites
# =============================================================================
print_header "Verifying Prerequisites"

# Check oc command
print_step "Checking OpenShift CLI..."
if ! command -v oc &>/dev/null; then
    print_error "oc command not found. Please install OpenShift CLI."
    exit 1
fi
print_success "OpenShift CLI found"

# Check jq (optional but recommended)
print_step "Checking jq..."
if command -v jq &>/dev/null; then
    print_success "jq found"
else
    print_warning "jq not found (optional but recommended for better output)"
fi

# Check script permissions
print_step "Checking script permissions..."
SCRIPTS_TO_CHECK=(
    "$SCRIPT_DIR/namespace-workloads/scripts/deploy.sh"
    "$SCRIPT_DIR/namespace-workloads/scripts/check-metrics.sh"
    "$SCRIPT_DIR/vm-workloads/scripts/deploy.sh"
    "$SCRIPT_DIR/vm-workloads/scripts/check-metrics.sh"
    "$SCRIPT_DIR/cleanup.sh"
)

for script in "${SCRIPTS_TO_CHECK[@]}"; do
    if [[ -f "$script" && ! -x "$script" ]]; then
        print_warning "Making $script executable..."
        chmod +x "$script"
    fi
done
print_success "Script permissions OK"

# =============================================================================
# Step 3: Verify Cluster Contexts
# =============================================================================
print_header "Verifying Cluster Contexts"

verify_cluster_context() {
    local context_name=$1
    local description=$2
    
    print_step "Checking $description ($context_name)..."
    
    if ! oc config use-context "$context_name" &>/dev/null; then
        print_error "Context '$context_name' not found!"
        echo "Available contexts:"
        oc config get-contexts -o name 2>/dev/null | sed 's/^/  /'
        return 1
    fi
    
    if ! oc whoami &>/dev/null; then
        print_error "Cannot authenticate to '$context_name'. Token may have expired."
        echo "Please re-login and recreate the context."
        return 1
    fi
    
    local user=$(oc whoami)
    local server=$(oc config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    print_success "$description: $user @ $server"
    return 0
}

CONTEXT_ERRORS=0

# Always verify Hub context (needed for Thanos queries)
if ! verify_cluster_context "$HUB_CONTEXT_NAME" "Hub (Thanos)"; then
    CONTEXT_ERRORS=$((CONTEXT_ERRORS + 1))
fi

if [[ "$SKIP_NAMESPACE" != "true" ]]; then
    if ! verify_cluster_context "$NAMESPACE_SPOKE_CONTEXT_NAME" "Namespace Spoke"; then
        CONTEXT_ERRORS=$((CONTEXT_ERRORS + 1))
    fi
fi

if [[ "$SKIP_VM" != "true" ]]; then
    if ! verify_cluster_context "$VM_SPOKE_CONTEXT_NAME" "VM Spoke"; then
        CONTEXT_ERRORS=$((CONTEXT_ERRORS + 1))
    fi
fi

if [[ $CONTEXT_ERRORS -gt 0 ]]; then
    print_error "Failed to verify $CONTEXT_ERRORS cluster context(s)."
    echo ""
    echo "Please set up contexts using:"
    echo "  oc login --token=<token> --server=<url>"
    echo "  oc config rename-context \$(oc config current-context) <context-name>"
    exit 1
fi

print_success "All cluster contexts verified"

# =============================================================================
# Confirmation Prompt
# =============================================================================
echo ""
if [[ "$CLEANUP_ONLY" == "true" ]]; then
    echo "This will CLEANUP resources from:"
else
    echo "This will deploy workloads to:"
fi

if [[ "$SKIP_NAMESPACE" != "true" ]]; then
    echo "  - Namespace workloads → $NAMESPACE_SPOKE_CONTEXT_NAME ($NAMESPACE_WORKLOAD_NS)"
fi
if [[ "$SKIP_VM" != "true" ]]; then
    echo "  - VM workloads → $VM_SPOKE_CONTEXT_NAME ($VM_WORKLOAD_NS)"
fi
echo ""

read -p "Do you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# =============================================================================
# Cleanup Only Mode
# =============================================================================
if [[ "$CLEANUP_ONLY" == "true" ]]; then
    print_header "Cleaning Up Resources"
    
    if [[ "$SKIP_NAMESPACE" != "true" ]]; then
        print_step "Cleaning namespace workloads..."
        oc config use-context "$NAMESPACE_SPOKE_CONTEXT_NAME"
        "$SCRIPT_DIR/cleanup.sh" --namespace-only || true
    fi
    
    if [[ "$SKIP_VM" != "true" ]]; then
        print_step "Cleaning VM workloads..."
        oc config use-context "$VM_SPOKE_CONTEXT_NAME"
        "$SCRIPT_DIR/cleanup.sh" --vm-only || true
    fi
    
    print_header "Cleanup Complete"
    exit 0
fi

# =============================================================================
# Step 4: Deploy Namespace Workloads
# =============================================================================
NAMESPACE_DEPLOY_TIME=""

if [[ "$SKIP_NAMESPACE" != "true" ]]; then
    print_header "Step 1: Deploying Namespace Workloads"
    
    print_step "Switching to namespace spoke context..."
    oc config use-context "$NAMESPACE_SPOKE_CONTEXT_NAME"
    
    print_step "Running namespace-workloads/scripts/deploy.sh..."
    NAMESPACE_DEPLOY_TIME=$(date +%s)
    "$SCRIPT_DIR/namespace-workloads/scripts/deploy.sh"
    
    print_success "Namespace workloads deployed"
else
    print_info "Skipping namespace workloads (--skip-namespace)"
fi

# =============================================================================
# Step 5: Deploy VM Workloads
# =============================================================================
VM_DEPLOY_TIME=""

if [[ "$SKIP_VM" != "true" ]]; then
    print_header "Step 2: Deploying VM Workloads"
    
    print_step "Switching to VM spoke context..."
    oc config use-context "$VM_SPOKE_CONTEXT_NAME"
    
    print_step "Running vm-workloads/scripts/deploy.sh..."
    print_info "This will take approximately 5 minutes for the stress test to complete."
    
    VM_DEPLOY_TIME=$(date +%s)
    "$SCRIPT_DIR/vm-workloads/scripts/deploy.sh"
    
    print_success "VM workloads deployed"
else
    print_info "Skipping VM workloads (--skip-vm)"
fi

# =============================================================================
# Step 6: Wait for Metrics
# =============================================================================
if [[ "$NO_WAIT" != "true" ]]; then
    print_header "Step 3: Waiting for Metrics"
    
    print_info "Thanos metrics are sent every 15 minutes."
    print_info "Waiting $((METRICS_WAIT_TIME / 60)) minutes for metrics to be available..."
    echo ""
    
    # Progress bar
    elapsed=0
    while [[ $elapsed -lt $METRICS_WAIT_TIME ]]; do
        remaining=$((METRICS_WAIT_TIME - elapsed))
        mins=$((remaining / 60))
        secs=$((remaining % 60))
        
        # Calculate progress percentage
        pct=$((elapsed * 100 / METRICS_WAIT_TIME))
        filled=$((pct / 2))
        empty=$((50 - filled))
        
        printf "\r  [%-50s] %3d%% - %02d:%02d remaining" \
            "$(printf '%*s' $filled | tr ' ' '█')$(printf '%*s' $empty | tr ' ' '░')" \
            $pct $mins $secs
        
        sleep 10
        elapsed=$((elapsed + 10))
    done
    echo ""
    print_success "Wait complete"
else
    print_info "Skipping wait (--no-wait)"
fi

# =============================================================================
# Step 7: Check Namespace Metrics (from Hub cluster)
# =============================================================================
if [[ "$SKIP_NAMESPACE" != "true" ]]; then
    print_header "Step 4: Checking Namespace Workload Metrics"
    
    print_info "Metrics are queried from Hub cluster (where Thanos runs)"
    print_step "Running namespace-workloads/scripts/check-metrics.sh..."
    "$SCRIPT_DIR/namespace-workloads/scripts/check-metrics.sh" || true
fi

# =============================================================================
# Step 8: Check VM Metrics (from Hub cluster)
# =============================================================================
if [[ "$SKIP_VM" != "true" ]]; then
    print_header "Step 5: Checking VM Workload Metrics"
    
    print_info "Metrics are queried from Hub cluster (where Thanos runs)"
    print_step "Running vm-workloads/scripts/check-metrics.sh..."
    "$SCRIPT_DIR/vm-workloads/scripts/check-metrics.sh" || true
fi

# =============================================================================
# Step 9: Cleanup Prompt
# =============================================================================
print_header "Workflow Complete"

echo "All steps completed successfully!"
echo ""
echo "Resources deployed:"
if [[ "$SKIP_NAMESPACE" != "true" ]]; then
    echo "  - Namespace: $NAMESPACE_WORKLOAD_NS (on $NAMESPACE_SPOKE_CONTEXT_NAME)"
fi
if [[ "$SKIP_VM" != "true" ]]; then
    echo "  - VM Namespace: $VM_WORKLOAD_NS (on $VM_SPOKE_CONTEXT_NAME)"
fi
echo ""

read -p "Do you want to cleanup all deployed resources? (y/N): " cleanup_confirm
if [[ "$cleanup_confirm" =~ ^[Yy]$ ]]; then
    print_header "Cleaning Up Resources"
    
    if [[ "$SKIP_NAMESPACE" != "true" ]]; then
        print_step "Cleaning namespace workloads..."
        oc config use-context "$NAMESPACE_SPOKE_CONTEXT_NAME"
        "$SCRIPT_DIR/cleanup.sh" --namespace-only || true
    fi
    
    if [[ "$SKIP_VM" != "true" ]]; then
        print_step "Cleaning VM workloads..."
        oc config use-context "$VM_SPOKE_CONTEXT_NAME"
        "$SCRIPT_DIR/cleanup.sh" --vm-only || true
    fi
    
    print_success "Cleanup complete"
else
    echo ""
    echo "To cleanup later, run:"
    echo "  ./run-all.sh --cleanup-only"
fi

print_header "Done"
