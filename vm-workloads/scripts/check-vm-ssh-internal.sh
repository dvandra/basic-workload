#!/bin/bash

# Script to check SSH status inside VM via virt-launcher pod
# Usage: ./check-vm-ssh-internal.sh [vm-name]

set -e

NAMESPACE="auto-vm-test"
VM_NAME="${1:-fedora-vm-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}❌ $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Get virt-launcher pod
get_virt_launcher_pod() {
    local pod=$(oc get pods -n "$NAMESPACE" -l kubevirt.io/domain="$VM_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    echo "$pod"
}

# Check if we can use virtctl exec
check_via_virtctl() {
    if ! command -v virtctl &> /dev/null; then
        return 1
    fi
    
    print_info "Checking SSH status via virtctl exec..."
    
    # Check if SSH process is running
    if virtctl exec "$VM_NAME" -n "$NAMESPACE" -- pgrep -f "/usr/sbin/sshd" &>/dev/null; then
        print_success "SSH daemon (sshd) is running"
        
        # Check SSH port
        if virtctl exec "$VM_NAME" -n "$NAMESPACE" -- netstat -tlnp 2>/dev/null | grep -q ":22 " || \
           virtctl exec "$VM_NAME" -n "$NAMESPACE" -- ss -tlnp 2>/dev/null | grep -q ":22 "; then
            print_success "SSH is listening on port 22"
        else
            print_warning "SSH port 22 may not be listening"
        fi
        
        # Check authorized_keys
        if virtctl exec "$VM_NAME" -n "$NAMESPACE" -- test -f /home/fedora/.ssh/authorized_keys 2>/dev/null; then
            print_success "SSH authorized_keys file exists"
            local key_count=$(virtctl exec "$VM_NAME" -n "$NAMESPACE" -- wc -l < /home/fedora/.ssh/authorized_keys 2>/dev/null || echo "0")
            print_info "Number of SSH keys: $key_count"
        else
            print_warning "SSH authorized_keys file not found"
        fi
        
        # Check cloud-init status
        if virtctl exec "$VM_NAME" -n "$NAMESPACE" -- test -f /etc/vm_status 2>/dev/null; then
            print_success "Cloud-init completed (/etc/vm_status exists)"
            local status=$(virtctl exec "$VM_NAME" -n "$NAMESPACE" -- cat /etc/vm_status 2>/dev/null || echo "")
            print_info "VM Status: $status"
        else
            print_warning "Cloud-init may not have completed"
        fi
        
        return 0
    else
        print_error "SSH daemon (sshd) is NOT running"
        return 1
    fi
}

# Check via console (manual)
check_via_console() {
    print_info "To check SSH manually via console:"
    echo "  virtctl console $VM_NAME -n $NAMESPACE"
    echo ""
    echo "Then in the VM console, run:"
    echo "  pgrep -f /usr/sbin/sshd"
    echo "  systemctl status sshd"
    echo "  netstat -tlnp | grep :22"
    echo "  cat /home/fedora/.ssh/authorized_keys"
    echo "  cat /etc/vm_status"
}

main() {
    echo "=========================================="
    echo "VM SSH Internal Status Check"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    if ! command -v oc &> /dev/null; then
        print_error "oc command not found"
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        print_error "Not logged in to OpenShift"
        exit 1
    fi
    
    # Check VM status
    print_info "Checking VM status..."
    local status=$(oc get vm "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "")
    
    if [ "$status" != "Running" ]; then
        print_error "VM '$VM_NAME' is not running (Status: $status)"
        exit 1
    fi
    
    print_success "VM is running"
    echo ""
    
    # Try virtctl exec
    if check_via_virtctl; then
        echo ""
        print_success "SSH appears to be configured correctly"
        echo ""
        print_info "Since direct SSH connection times out, use port-forwarding:"
        echo "  ./run-stress-via-port-forward.sh"
        exit 0
    else
        echo ""
        print_warning "Could not check SSH status via virtctl exec"
        echo ""
        check_via_console
        exit 1
    fi
}

main "$@"
