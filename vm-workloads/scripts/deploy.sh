#!/bin/bash

# Deploy VM workloads (Fedora and RHEL VMs with stress testing)
# Creates namespace, deploys VMs, and runs stress tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source configuration if available
if [[ -f "$ROOT_DIR/config.sh" ]]; then
    source "$ROOT_DIR/config.sh"
fi

# Default namespace (use config value if available)
NAMESPACE="${VM_WORKLOAD_NS:-auto-vm-test}"

# VM names
FEDORA_VM="fedora-vm-1"
RHEL_VM="rhel-vm1"

# VM YAML files
WORKLOADS_DIR="$SCRIPT_DIR/../workloads"

# SSH configuration (use config values if available)
SSH_USER="${VM_SSH_USER:-fedora}"
SSH_PASSWORD="${VM_SSH_PASSWORD:-password}"
SSH_KEY="${VM_SSH_PRIVATE_KEY:-$HOME/.ssh/id_rsa}"

# Stress test command
STRESS_DURATION="${VM_STRESS_DURATION:-5m}"
STRESS_CMD="stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout ${STRESS_DURATION} --metrics-brief"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}❌ Error: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Function to check prerequisites
check_prerequisites() {
    if ! command -v oc &> /dev/null; then
        print_error "oc command not found. Please install OpenShift CLI."
        exit 1
    fi

    if ! oc whoami &> /dev/null; then
        print_error "Not logged in to OpenShift. Please run 'oc login' first."
        exit 1
    fi

    # Check SSH key for VM access
    if [[ -z "$VM_SSH_PUBLIC_KEY" ]]; then
        print_warning "VM_SSH_PUBLIC_KEY is not set!"
        echo ""
        echo "VMs will be created but SSH access may not work."
        echo "Set your SSH public key before running:"
        echo "  export VM_SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_rsa.pub)\""
        echo ""
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted. Set VM_SSH_PUBLIC_KEY and try again."
            exit 1
        fi
    else
        print_success "SSH public key configured"
    fi

    print_success "Prerequisites check passed"
}

# Function to create namespace
create_namespace() {
    print_info "Creating namespace '$NAMESPACE'..."
    
    if oc get namespace "$NAMESPACE" &> /dev/null; then
        print_warning "Namespace '$NAMESPACE' already exists"
    else
        oc create namespace "$NAMESPACE" || {
            print_error "Failed to create namespace"
            return 1
        }
        print_success "Namespace '$NAMESPACE' created"
    fi
}

# Function to wait for VM to be running
wait_for_vm_running() {
    local vm_name="$1"
    local max_wait=600  # 10 minutes (RHEL VMs can take longer)
    local elapsed=0
    local last_log=0
    
    print_info "Waiting for VM '$vm_name' to be running (timeout: ${max_wait}s)..."
    
    while [ $elapsed -lt $max_wait ]; do
        local status=$(oc get vm "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "")
        
        if [ "$status" = "Running" ]; then
            echo ""
            print_success "VM '$vm_name' is running (took ${elapsed}s)"
            return 0
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        
        # Log status every 60 seconds
        if [ $((elapsed - last_log)) -ge 60 ]; then
            echo ""
            echo "  [${elapsed}s] VM '$vm_name' status: ${status:-Pending}..."
            last_log=$elapsed
        else
            echo -n "."
        fi
    done
    
    echo ""
    print_warning "VM '$vm_name' did not reach Running state within $max_wait seconds"
    print_info "Current status: $(oc get vm "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo 'Unknown')"
    return 1
}

# Function to create VMs from YAML files
create_vms() {
    print_info "Creating VMs from YAML files..."
    echo ""
    
    for yaml_file in "$WORKLOADS_DIR"/*.yaml; do
        if [ -f "$yaml_file" ]; then
            print_info "Applying: $(basename $yaml_file)"
            # Replace namespace in YAML and apply
            sed "s/namespace: auto-vm-test/namespace: $NAMESPACE/g" "$yaml_file" | oc apply -f - || {
                print_error "Failed to apply $yaml_file"
                return 1
            }
            print_success "Applied: $(basename $yaml_file)"
        fi
    done
    
    echo ""
    
    # Wait for VMs to be running
    print_info "Waiting for VMs to start..."
    echo ""
    
    wait_for_vm_running "fedora-vm-1"
    if oc get vm fedora-vm-2 -n "$NAMESPACE" &> /dev/null; then
        wait_for_vm_running "fedora-vm-2"
    fi
    if oc get vm rhel-vm1 -n "$NAMESPACE" &> /dev/null; then
        wait_for_vm_running "rhel-vm1"
    fi
    
    print_success "VMs created and running"
    echo ""
}

# Function to wait for stress-ng to be installed
wait_for_stress_ng() {
    local max_attempts=10
    local wait_seconds=30
    local attempt=1
    
    print_info "Waiting for stress-ng to be installed (checking every ${wait_seconds}s, max ${max_attempts} attempts)..."
    echo ""
    
    while [ $attempt -le $max_attempts ]; do
        echo -n "  Attempt $attempt/$max_attempts: "
        
        if virtctl exec "$FEDORA_VM" -n "$NAMESPACE" -- which stress-ng &>/dev/null 2>&1; then
            echo -e "${GREEN}stress-ng found!${NC}"
            return 0
        else
            echo "not ready yet, waiting ${wait_seconds}s..."
            sleep $wait_seconds
            attempt=$((attempt + 1))
        fi
    done
    
    return 1
}

# Function to run stress test via virtctl exec
run_stress_test() {
    echo ""
    print_info "Starting stress test on $FEDORA_VM..."
    echo ""
    
    if ! command -v virtctl &> /dev/null; then
        print_warning "virtctl not found - skipping stress test"
        print_info "Install virtctl to run stress tests automatically"
        return 0
    fi
    
    # Initial wait for VM to boot and start cloud-init
    print_info "Waiting for VM to boot and start cloud-init (60 seconds)..."
    sleep 60
    
    # Wait for stress-ng to be installed (with retries)
    if ! wait_for_stress_ng; then
        print_warning "stress-ng not installed after waiting. VM cloud-init may have failed."
        print_info "You can try running stress test manually later:"
        echo "  virtctl exec $FEDORA_VM -n $NAMESPACE -- $STRESS_CMD"
        return 0
    fi
    
    # Run the stress test
    print_info "Running stress test via virtctl exec..."
    echo "Command: $STRESS_CMD"
    echo ""
    echo "--- Output ---"
    
    virtctl exec "$FEDORA_VM" -n "$NAMESPACE" -- bash -c "$STRESS_CMD" || {
        print_warning "Stress test failed - you can run manually later"
        return 0
    }
    
    echo "--- End Output ---"
    echo ""
    print_success "Stress test completed successfully!"
}

# Main script
main() {
    echo "=========================================="
    echo "Deploy VM Workloads"
    echo "=========================================="
    echo ""
    echo "This script will:"
    echo "  1. Create namespace '$NAMESPACE'"
    echo "  2. Deploy Fedora and RHEL VMs"
    echo "  3. Run stress test on Fedora VM"
    echo ""
    
    check_prerequisites
    echo ""
    
    create_namespace
    echo ""
    
    create_vms
    
    run_stress_test
    
    echo ""
    echo "=========================================="
    echo "Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Namespace: $NAMESPACE"
    echo "VMs deployed:"
    oc get vm -n "$NAMESPACE" --no-headers | awk '{print "  - " $1 " (" $2 ")"}'
    echo ""
    echo "Next steps:"
    echo "  1. Wait 15-20 minutes for metrics to be collected"
    echo "  2. Check metrics from project root:"
    echo "     ./vm-workloads/scripts/check-metrics.sh"
    echo "     Or use ./run-all.sh which handles everything"
    echo ""
}

main "$@"
