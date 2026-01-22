#!/bin/bash

# Combined script: Create Fedora VMs, Run Stress Test, and Create RHEL VM
# Usage: ./create-and-stress-test.sh

set -e

# Default namespace
NAMESPACE="auto-vm-test"

# VM names
FEDORA_VM="fedora-vm-1"
RHEL_VM="rhel-vm"

# VM YAML files (relative to scripts directory)
FEDORA_YAML_DIR="../vms"
RHEL_YAML="../vms/rhel-vm.yaml"

# SSH configuration
SSH_USER="${VM_SSH_USER:-fedora}"
SSH_PASSWORD="${VM_SSH_PASSWORD:-password}"
SSH_KEY="${VM_SSH_PRIVATE_KEY:-$HOME/.ssh/id_rsa}"

# Stress test command
STRESS_CMD="stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief"

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

# Function to update SSH key in YAML files
update_ssh_key() {
    local ssh_key="${VM_SSH_PUBLIC_KEY:-}"
    
    if [ -z "$ssh_key" ] && [ -f "$HOME/.ssh/id_rsa.pub" ]; then
        ssh_key=$(cat "$HOME/.ssh/id_rsa.pub")
        print_info "Using SSH key from default location: $HOME/.ssh/id_rsa.pub"
    fi
    
    if [ -z "$ssh_key" ]; then
        print_warning "No SSH public key provided (VM_SSH_PUBLIC_KEY not set)"
        print_info "VMs will be created with placeholder SSH key"
        return 0
    fi
    
    print_info "Updating SSH public key in YAML files..."
    
    # Update all YAML files
    for yaml_file in "$FEDORA_YAML_DIR"/*.yaml "$RHEL_YAML"; do
        if [ -f "$yaml_file" ] && grep -q "YOUR_SSH_PUBLIC_KEY_HERE" "$yaml_file"; then
            if command -v perl &> /dev/null; then
                perl -i -pe "s|YOUR_SSH_PUBLIC_KEY_HERE|$ssh_key|g" "$yaml_file"
            else
                local escaped_key=$(printf '%s\n' "$ssh_key" | sed 's/[[\.*^$()+?{|]/\\&/g')
                sed -i.bak "s|YOUR_SSH_PUBLIC_KEY_HERE|$escaped_key|g" "$yaml_file"
                rm -f "${yaml_file}.bak" 2>/dev/null || true
            fi
            print_info "Updated SSH key in: $(basename $yaml_file)"
        fi
    done
    
    print_success "SSH key updated in YAML files"
}

# Function to wait for VM to be running
wait_for_vm_running() {
    local vm_name="$1"
    local max_wait=300
    local elapsed=0
    
    print_info "Waiting for VM '$vm_name' to be running..."
    
    while [ $elapsed -lt $max_wait ]; do
        local status=$(oc get vm "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "")
        
        if [ "$status" = "Running" ]; then
            print_success "VM '$vm_name' is running"
            return 0
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    echo ""
    print_warning "VM '$vm_name' did not reach Running state within $max_wait seconds"
    return 1
}

# Function to create Fedora VMs
create_fedora_vms() {
    print_info "Creating Fedora VMs..."
    echo ""
    
    for yaml_file in "$FEDORA_YAML_DIR"/fedora-vm*.yaml; do
        if [ -f "$yaml_file" ]; then
            print_info "Applying: $(basename $yaml_file)"
            oc apply -f "$yaml_file" || {
                print_error "Failed to apply $yaml_file"
                return 1
            }
            print_success "Applied: $(basename $yaml_file)"
        fi
    done
    
    echo ""
    
    # Wait for Fedora VMs to be running
    print_info "Waiting for Fedora VMs to start..."
    echo ""
    
    wait_for_vm_running "fedora-vm-1"
    if oc get vm fedora-vm-2 -n "$NAMESPACE" &> /dev/null; then
        wait_for_vm_running "fedora-vm-2"
    fi
    
    print_success "Fedora VMs created and running"
    echo ""
}

# Function to create RHEL VM
create_rhel_vm() {
    print_info "Creating RHEL VM..."
    echo ""
    
    if [ ! -f "$RHEL_YAML" ]; then
        print_warning "RHEL YAML file not found: $RHEL_YAML (skipping)"
        return 0
    fi
    
    print_info "Applying: $(basename $RHEL_YAML)"
    oc apply -f "$RHEL_YAML" || {
        print_error "Failed to apply $RHEL_YAML"
        return 1
    }
    print_success "Applied: $(basename $RHEL_YAML)"
    echo ""
    
    # Wait for RHEL VM to be running
    print_info "Waiting for RHEL VM to start..."
    echo ""
    
    wait_for_vm_running "$RHEL_VM"
    
    print_success "RHEL VM created and running"
    echo ""
}

# Function to get VM IP
get_vm_ip() {
    local vm_name="$1"
    local max_wait=60
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        local ip=$(oc get vmi "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")
        
        if [ -z "$ip" ] || [ "$ip" = "null" ]; then
            ip=$(oc get vm "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")
        fi
        
        if [ -n "$ip" ] && [ "$ip" != "null" ] && [ "$ip" != "" ]; then
            echo "$ip"
            return 0
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    return 1
}

# Function to wait for cloud-init to complete
wait_for_cloud_init() {
    local vm_name="$1"
    local max_wait=300
    local elapsed=0
    
    print_info "Waiting for cloud-init to complete (installing packages including stress-ng)..."
    print_info "This may take 2-5 minutes depending on network speed..."
    echo ""
    
    while [ $elapsed -lt $max_wait ]; do
        local ready=false
        
        # Try virtctl exec first (most reliable)
        if command -v virtctl &> /dev/null; then
            # Check if we can execute commands
            if virtctl exec "$vm_name" -n "$NAMESPACE" -- echo "test" &>/dev/null 2>&1; then
                # Check if stress-ng is installed
                if virtctl exec "$vm_name" -n "$NAMESPACE" -- which stress-ng &>/dev/null 2>&1; then
                    # Check if cloud-init completed (vm_status file exists)
                    if virtctl exec "$vm_name" -n "$NAMESPACE" -- test -f /etc/vm_status &>/dev/null 2>&1; then
                        local status=$(virtctl exec "$vm_name" -n "$NAMESPACE" -- cat /etc/vm_status 2>/dev/null | head -1 || echo "")
                        echo ""
                        print_success "Cloud-init completed: ${status:-VM Ready}"
                        print_success "stress-ng is installed and ready"
                        ready=true
                    fi
                fi
            fi
        fi
        
        # Fallback: try via port-forward + SSH if virtctl didn't work
        if [ "$ready" = false ]; then
            local vmi_pod=$(oc get pods -n "$NAMESPACE" -l kubevirt.io/domain="$vm_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            
            if [ -n "$vmi_pod" ]; then
                # Kill any existing port-forward on 2222
                lsof -ti:2222 2>/dev/null | xargs kill -9 2>/dev/null || true
                
                oc port-forward "$vmi_pod" -n "$NAMESPACE" 2222:22 > /tmp/port-forward-ci.log 2>&1 &
                local pf_pid=$!
                sleep 3
                
                if kill -0 $pf_pid 2>/dev/null; then
                    # Check via SSH
                    local check_cmd="which stress-ng >/dev/null 2>&1 && test -f /etc/vm_status"
                    if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
                        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -p 2222 "$SSH_USER@localhost" "$check_cmd" &>/dev/null 2>&1; then
                            ready=true
                        fi
                    elif command -v sshpass &> /dev/null; then
                        if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -p 2222 "$SSH_USER@localhost" "$check_cmd" &>/dev/null 2>&1; then
                            ready=true
                        fi
                    fi
                    kill $pf_pid 2>/dev/null || true
                fi
            fi
        fi
        
        if [ "$ready" = true ]; then
            return 0
        fi
        
        # Show progress
        if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo ""
            print_info "Still waiting for cloud-init and package installation... ($elapsed seconds elapsed)"
        else
            echo -n "."
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    echo ""
    print_warning "Cloud-init check timed out after $max_wait seconds"
    print_info "Proceeding anyway - stress test methods will verify if stress-ng is available"
    print_info "If stress-ng is not ready, you'll see a clear error message"
    return 0  # Don't fail - let the stress test methods handle the check
}

# Function to wait for SSH
wait_for_ssh() {
    local host="$1"
    local user="$2"
    local max_wait=300  # 5 minutes
    local elapsed=0
    
    print_info "Waiting for SSH to be available on $host..."
    
    while [ $elapsed -lt $max_wait ]; do
        local ssh_works=false
        
        if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
            if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$user@$host" "echo 'SSH ready'" &>/dev/null 2>&1; then
                ssh_works=true
            fi
        fi
        
        if [ "$ssh_works" = false ] && command -v sshpass &> /dev/null; then
            if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$user@$host" "echo 'SSH ready'" &>/dev/null 2>&1; then
                ssh_works=true
            fi
        fi
        
        if [ "$ssh_works" = true ]; then
            print_success "SSH is available on $host"
            return 0
        fi
        
        if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo ""
            print_info "Still waiting... ($elapsed seconds elapsed)"
        else
            echo -n "."
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    echo ""
    print_warning "SSH did not become available on $host within $max_wait seconds"
    return 1
}

# Function to run stress test via virtctl exec
run_stress_via_virtctl_exec() {
    if ! command -v virtctl &> /dev/null; then
        return 1
    fi
    
    print_info "Trying virtctl exec (no SSH needed)..."
    
    # First check if stress-ng is available
    if ! virtctl exec "$FEDORA_VM" -n "$NAMESPACE" -- which stress-ng &>/dev/null 2>&1; then
        print_warning "stress-ng not found via virtctl exec - VM may still be installing packages"
        return 1
    fi
    
    if virtctl exec "$FEDORA_VM" -n "$NAMESPACE" -- echo "test" &>/dev/null 2>&1; then
        print_success "virtctl exec is working and stress-ng is available!"
        echo ""
        print_info "Running stress test via virtctl exec..."
        echo "Command: $STRESS_CMD"
        echo ""
        echo "--- Output ---"
        
        virtctl exec "$FEDORA_VM" -n "$NAMESPACE" -- bash -c "$STRESS_CMD" || {
            print_error "Failed to run stress test via virtctl exec"
            return 1
        }
        
        echo "--- End Output ---"
        echo ""
        print_success "Stress test completed"
        return 0
    else
        print_warning "virtctl exec not available or not working"
        return 1
    fi
}

# Function to run stress test via port-forwarding
run_stress_via_port_forward() {
    local vm_ip="$1"
    local user="$2"
    
    print_info "Trying port-forwarding + SSH..."
    
    local vmi_pod=$(oc get pods -n "$NAMESPACE" -l kubevirt.io/domain="$FEDORA_VM" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$vmi_pod" ]; then
        vmi_pod=$(oc get pods -n "$NAMESPACE" -l kubevirt.io=virt-launcher -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "virt-launcher-$FEDORA_VM-" | head -1 || echo "")
    fi
    
    if [ -z "$vmi_pod" ]; then
        print_warning "Could not find VMI pod for port-forwarding"
        return 1
    fi
    
    print_info "Found VMI pod: $vmi_pod"
    print_info "Setting up port-forward (localhost:2222 -> VM:22)..."
    
    oc port-forward "$vmi_pod" -n "$NAMESPACE" 2222:22 > /tmp/port-forward.log 2>&1 &
    local pf_pid=$!
    
    sleep 3
    
    if ! kill -0 $pf_pid 2>/dev/null; then
        print_error "Port-forward failed"
        return 1
    fi
    
    print_success "Port-forward established (PID: $pf_pid)"
    
    print_info "Waiting for SSH via port-forward..."
    local ssh_ready=false
    for i in {1..30}; do
        if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
            if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o UserKnownHostsFile=/dev/null -p 2222 "$user@localhost" "echo test" &>/dev/null 2>&1; then
                ssh_ready=true
                break
            fi
        elif command -v sshpass &> /dev/null; then
            if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o UserKnownHostsFile=/dev/null -p 2222 "$user@localhost" "echo test" &>/dev/null 2>&1; then
                ssh_ready=true
                break
            fi
        fi
        sleep 1
    done
    
    if [ "$ssh_ready" = false ]; then
        kill $pf_pid 2>/dev/null || true
        print_warning "SSH not available via port-forward"
        return 1
    fi
    
    print_success "SSH is available via port-forward"
    
    # Check if stress-ng is available before running
    print_info "Checking if stress-ng is installed..."
    local stress_ng_available=false
    if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 "$user@localhost" "which stress-ng" &>/dev/null 2>&1; then
            stress_ng_available=true
        fi
    elif command -v sshpass &> /dev/null; then
        if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 "$user@localhost" "which stress-ng" &>/dev/null 2>&1; then
            stress_ng_available=true
        fi
    fi
    
    if [ "$stress_ng_available" = false ]; then
        kill $pf_pid 2>/dev/null || true
        print_warning "stress-ng not found - VM may still be installing packages"
        print_info "Wait a few minutes and try again, or check manually:"
        print_info "  virtctl console $FEDORA_VM -n $NAMESPACE"
        return 1
    fi
    
    print_success "stress-ng is available"
    echo ""
    print_info "Running stress test via port-forward..."
    echo "Command: $STRESS_CMD"
    echo ""
    echo "--- Output ---"
    
    local result=1
    if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 "$user@localhost" "$STRESS_CMD"
        result=$?
    elif command -v sshpass &> /dev/null; then
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 "$user@localhost" "$STRESS_CMD"
        result=$?
    else
        print_error "Need SSH key or sshpass for port-forward method"
        kill $pf_pid 2>/dev/null || true
        return 1
    fi
    
    kill $pf_pid 2>/dev/null || true
    
    echo "--- End Output ---"
    echo ""
    
    if [ $result -eq 0 ]; then
        print_success "Stress test completed"
        return 0
    else
        print_error "Failed to run stress test"
        return 1
    fi
}

# Function to run stress test via direct SSH
run_stress_via_ssh() {
    local vm_ip="$1"
    local user="$2"
    
    print_info "Trying direct SSH connection..."
    
    if wait_for_ssh "$vm_ip" "$user" "$SSH_PASSWORD" 60; then
        echo ""
        print_info "Running stress test via direct SSH..."
        echo "Command: $STRESS_CMD"
        echo ""
        echo "--- Output ---"
        
        if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$vm_ip" "$STRESS_CMD" || {
                print_error "Failed to run stress test"
                return 1
            }
        elif command -v sshpass &> /dev/null; then
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$vm_ip" "$STRESS_CMD" || {
                print_error "Failed to run stress test"
                return 1
            }
        else
            print_error "Cannot run stress test: Need SSH key or sshpass"
            return 1
        fi
        
        echo "--- End Output ---"
        echo ""
        print_success "Stress test completed"
        return 0
    else
        return 1
    fi
}

# Function to run stress test
run_stress_test() {
    echo ""
    print_info "Starting stress test on $FEDORA_VM..."
    echo ""
    
    # Get VM IP
    local vm_ip=$(get_vm_ip "$FEDORA_VM")
    
    if [ -z "$vm_ip" ]; then
        print_warning "Could not get IP address for $FEDORA_VM"
        print_info "Trying alternative connection methods..."
    else
        print_info "VM IP: $vm_ip"
    fi
    echo ""
    
    # Try multiple methods
    if run_stress_via_virtctl_exec; then
        return 0
    fi
    echo ""
    
    if [ -n "$vm_ip" ]; then
        if run_stress_via_port_forward "$vm_ip" "$SSH_USER"; then
            return 0
        fi
        echo ""
        
        if run_stress_via_ssh "$vm_ip" "$SSH_USER"; then
            return 0
        fi
    else
        if run_stress_via_port_forward "" "$SSH_USER"; then
            return 0
        fi
    fi
    echo ""
    
    print_warning "All automated methods failed"
    print_info "You can run the stress test manually:"
    echo "  virtctl console $FEDORA_VM -n $NAMESPACE"
    echo "  Login: fedora / password"
    echo "  Then run: $STRESS_CMD"
    return 1
}

# Main script
main() {
    echo "=========================================="
    echo "VM Creation and Stress Test"
    echo "=========================================="
    echo ""
    echo "This script will:"
    echo "  1. Create Fedora VMs (fedora-vm-1, fedora-vm-2)"
    echo "  2. Run stress test on fedora-vm-1"
    echo "  3. Create RHEL VM (rhel-vm)"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Create namespace
    create_namespace
    echo ""
    
    # Update SSH keys
    update_ssh_key
    echo ""
    
    # Step 1: Create Fedora VMs
    echo "=========================================="
    echo "Step 1: Creating Fedora VMs"
    echo "=========================================="
    echo ""
    create_fedora_vms
    
    # Step 2: Run stress test
    echo "=========================================="
    echo "Step 2: Running Stress Test"
    echo "=========================================="
    echo ""
    
    # Wait for cloud-init to complete (install packages)
    wait_for_cloud_init "$FEDORA_VM"
    echo ""
    
    run_stress_test
    
    # Step 3: Create RHEL VM
    echo ""
    echo "=========================================="
    echo "Step 3: Creating RHEL VM"
    echo "=========================================="
    echo ""
    create_rhel_vm
    
    # Final summary
    echo ""
    echo "=========================================="
    echo "All Tasks Completed"
    echo "=========================================="
    echo ""
    print_success "Fedora VMs: Created"
    print_success "Stress Test: Completed"
    print_success "RHEL VM: Created"
    echo ""
}

# Run main function
main "$@"
