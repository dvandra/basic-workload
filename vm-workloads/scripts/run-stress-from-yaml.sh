#!/bin/bash

# Script to run stress test on fedora-vm-1
# Usage: ./run-stress-from-yaml.sh

set -e

# Default namespace
NAMESPACE="auto-vm-test"

# VM name (stress test target)
VM_NAME="fedora-vm-1"

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
NC='\033[0m' # No Color

# Function to print colored output
print_error() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    # Check if oc is installed
    if ! command -v oc &> /dev/null; then
        print_error "oc command not found. Please install OpenShift CLI."
        exit 1
    fi

    # Check if ssh is installed
    if ! command -v ssh &> /dev/null; then
        print_error "ssh command not found. Please install OpenSSH client."
        exit 1
    fi

    # Check if logged in to OpenShift
    if ! oc whoami &> /dev/null; then
        print_error "Not logged in to OpenShift. Please run 'oc login' first."
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to get VM IP address
get_vm_ip() {
    local vm_name="$1"
    local max_wait=60
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        # Try VMI first (most reliable)
        local ip=$(oc get vmi "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")
        
        # Fallback to VM status
        if [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "" ]; then
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

# Function to wait for cloud-init to complete and stress-ng to be installed
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

# Function to wait for SSH to be available
wait_for_ssh() {
    local host="$1"
    local user="$2"
    local max_wait=300  # 5 minutes
    local elapsed=0
    local check_interval=10
    
    print_info "Waiting for SSH to be available on $host..."
    print_info "This may take a few minutes while the VM finishes booting..."
    echo ""
    
    # Check if SSH key is available
    local use_key=false
    if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
        use_key=true
        print_info "Using SSH key: $SSH_KEY"
    else
        print_info "Using password authentication (password: $SSH_PASSWORD)"
    fi
    
    while [ $elapsed -lt $max_wait ]; do
        local ssh_works=false
        
        # Try SSH key first if available
        if [ "$use_key" = true ]; then
            if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$user@$host" "echo 'SSH ready'" &>/dev/null 2>&1; then
                ssh_works=true
            fi
        fi
        
        # Fallback to password (requires sshpass)
        if [ "$ssh_works" = false ] && command -v sshpass &> /dev/null; then
            if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$user@$host" "echo 'SSH ready'" &>/dev/null 2>&1; then
                ssh_works=true
            fi
        fi
        
        if [ "$ssh_works" = true ]; then
            echo ""
            print_success "SSH is available on $host"
            return 0
        fi
        
        # Show progress every 30 seconds
        if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo ""
            print_info "Still waiting... ($elapsed seconds elapsed)"
        else
            echo -n "."
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo ""
    print_warning "SSH did not become available on $host within $max_wait seconds"
    return 1
}

# Function to run stress test via virtctl exec (no SSH needed)
run_stress_via_virtctl_exec() {
    if ! command -v virtctl &> /dev/null; then
        return 1
    fi
    
    print_info "Trying virtctl exec (no SSH needed)..."
    
    # First check if stress-ng is available
    if ! virtctl exec "$VM_NAME" -n "$NAMESPACE" -- which stress-ng &>/dev/null 2>&1; then
        print_warning "stress-ng not found via virtctl exec - VM may still be installing packages"
        return 1
    fi
    
    # Check if virtctl exec works
    if virtctl exec "$VM_NAME" -n "$NAMESPACE" -- echo "test" &>/dev/null 2>&1; then
        print_success "virtctl exec is working and stress-ng is available!"
        echo ""
        print_info "Running stress test via virtctl exec..."
        echo "Command: $STRESS_CMD"
        echo ""
        echo "--- Output ---"
        
        virtctl exec "$VM_NAME" -n "$NAMESPACE" -- bash -c "$STRESS_CMD" || {
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
    
    # Get VMI pod
    local vmi_pod=$(oc get pods -n "$NAMESPACE" -l kubevirt.io/domain="$VM_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$vmi_pod" ]; then
        # Try alternative methods to find pod
        vmi_pod=$(oc get pods -n "$NAMESPACE" -l kubevirt.io=virt-launcher -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "virt-launcher-$VM_NAME-" | head -1 || echo "")
    fi
    
    if [ -z "$vmi_pod" ]; then
        print_warning "Could not find VMI pod for port-forwarding"
        return 1
    fi
    
    print_info "Found VMI pod: $vmi_pod"
    print_info "Setting up port-forward (localhost:2222 -> VM:22)..."
    
    # Start port-forward in background
    oc port-forward "$vmi_pod" -n "$NAMESPACE" 2222:22 > /tmp/port-forward.log 2>&1 &
    local pf_pid=$!
    
    # Wait for port-forward to establish
    sleep 3
    
    # Check if port-forward is still running
    if ! kill -0 $pf_pid 2>/dev/null; then
        print_error "Port-forward failed. Check /tmp/port-forward.log"
        return 1
    fi
    
    print_success "Port-forward established (PID: $pf_pid)"
    
    # Wait for SSH via port-forward
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
        print_info "  virtctl console $VM_NAME -n $NAMESPACE"
        return 1
    fi
    
    print_success "stress-ng is available"
    echo ""
    print_info "Running stress test via port-forward..."
    echo "Command: $STRESS_CMD"
    echo ""
    echo "--- Output ---"
    
    # Run stress test via port-forward
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
    
    # Cleanup port-forward
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
run_stress_test() {
    local vm_name="$1"
    local vm_ip="$2"
    local user="$3"
    
    # Check if stress-ng is available first
    print_info "Checking if stress-ng is installed..."
    local stress_ng_available=false
    if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$user@$vm_ip" "which stress-ng" &>/dev/null 2>&1; then
            stress_ng_available=true
        fi
    elif command -v sshpass &> /dev/null; then
        if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$user@$vm_ip" "which stress-ng" &>/dev/null 2>&1; then
            stress_ng_available=true
        fi
    fi
    
    if [ "$stress_ng_available" = false ]; then
        print_warning "stress-ng not found - VM may still be installing packages"
        print_info "Wait a few minutes and try again, or check manually:"
        print_info "  virtctl console $vm_name -n $NAMESPACE"
        return 1
    fi
    
    print_success "stress-ng is available"
    echo ""
    print_info "Running stress test on $vm_name ($vm_ip)..."
    echo "Command: $STRESS_CMD"
    echo ""
    echo "--- Output ---"
    
    # Try SSH key first
    if [ -f "$SSH_KEY" ] && [ -r "$SSH_KEY" ]; then
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$vm_ip" "$STRESS_CMD" || {
            print_error "Failed to run stress test via direct SSH"
            return 1
        }
    elif command -v sshpass &> /dev/null; then
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$vm_ip" "$STRESS_CMD" || {
            print_error "Failed to run stress test via direct SSH"
            return 1
        }
    else
        print_error "Cannot run stress test: Need SSH key or sshpass"
        print_info "Install sshpass or set VM_SSH_PRIVATE_KEY environment variable"
        return 1
    fi
    
    echo "--- End Output ---"
    echo ""
    print_success "Stress test completed"
}

# Main script
main() {
    echo "=========================================="
    echo "OpenShift Virtualization VM Stress Test"
    echo "Running on fedora-vm-1"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Check if namespace exists
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist"
        echo "Please create VMs first using: ./create-vms-from-yaml.sh"
        exit 1
    fi
    
    # Check if VM is running
    print_info "Checking VM status..."
    local status=$(oc get vm "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "")
    
    if [ "$status" != "Running" ]; then
        print_error "VM '$VM_NAME' is not running (Status: $status)"
        echo "Please start it: virtctl start $VM_NAME -n $NAMESPACE"
        exit 1
    fi
    
    print_success "VM '$VM_NAME' is running"
    echo ""
    
    # Get VM IP
    print_info "Getting VM IP address..."
    local vm_ip=$(get_vm_ip "$VM_NAME")
    
    if [ -z "$vm_ip" ]; then
        print_error "Could not get IP address for $VM_NAME"
        exit 1
    fi
    
    print_success "VM IP: $vm_ip"
    echo ""
    
    # Wait for cloud-init to complete and stress-ng to be installed
    wait_for_cloud_init "$VM_NAME"
    echo ""
    
    # Try multiple methods automatically (no manual steps needed)
    echo ""
    print_info "Attempting to run stress test automatically..."
    echo ""
    
    # Method 1: Try virtctl exec first (no SSH needed)
    if run_stress_via_virtctl_exec; then
        print_success "Stress test completed successfully via virtctl exec!"
        exit 0
    fi
    echo ""
    
    # Method 2: Try port-forwarding + SSH
    if run_stress_via_port_forward "$vm_ip" "$SSH_USER"; then
        print_success "Stress test completed successfully via port-forwarding!"
        exit 0
    fi
    echo ""
    
    # Method 3: Try direct SSH (if VM IP is accessible)
    print_info "Trying direct SSH connection..."
    if wait_for_ssh "$vm_ip" "$SSH_USER" "$SSH_PASSWORD" 60; then
        echo ""
        if run_stress_test "$VM_NAME" "$vm_ip" "$SSH_USER"; then
            print_success "Stress test completed successfully via direct SSH!"
            exit 0
        fi
    fi
    echo ""
    
    # If all methods failed, show manual options
    print_warning "All automated methods failed"
    echo ""
    print_info "Manual options:"
    echo ""
    echo "Option 1: Use VM console"
    echo "  virtctl console $VM_NAME -n $NAMESPACE"
    echo "  Login: fedora / password"
    echo "  Then run: $STRESS_CMD"
    echo ""
    echo "Option 2: Check SSH status"
    echo "  ./check-vm-ssh-internal.sh $VM_NAME"
    echo ""
    echo "Option 3: Use port-forwarding manually"
    echo "  VMI_POD=\$(oc get pods -n $NAMESPACE -l kubevirt.io/domain=$VM_NAME -o jsonpath='{.items[0].metadata.name}')"
    echo "  oc port-forward \$VMI_POD -n $NAMESPACE 2222:22"
    echo "  # In another terminal:"
    echo "  ssh -p 2222 fedora@localhost"
    echo ""
    exit 1
    
    echo ""
    print_success "Stress test completed successfully!"
}

# Run main function
main "$@"
