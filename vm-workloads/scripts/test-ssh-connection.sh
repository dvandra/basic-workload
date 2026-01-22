#!/bin/bash

# Quick script to test SSH connection to VM
# Usage: ./test-ssh-connection.sh [vm-name] [vm-ip]

set -e

NAMESPACE="auto-vm-test"
VM_NAME="${1:-fedora-vm-1}"
VM_IP="${2:-}"

SSH_USER="fedora"
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_PASSWORD="password"

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

# Get IP if not provided
if [ -z "$VM_IP" ]; then
    print_info "Getting VM IP address..."
    VM_IP=$(oc get vmi "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")
    if [ -z "$VM_IP" ]; then
        VM_IP=$(oc get vm "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")
    fi
fi

if [ -z "$VM_IP" ] || [ "$VM_IP" = "null" ]; then
    print_error "Could not get VM IP address"
    exit 1
fi

print_success "VM IP: $VM_IP"
echo ""

# Test network connectivity
print_info "Testing network connectivity..."
if ping -c 1 -W 2 "$VM_IP" &>/dev/null; then
    print_success "Network connectivity: OK"
else
    print_warning "Network connectivity: Failed (may be normal in some clusters)"
fi
echo ""

# Test SSH port
print_info "Testing SSH port (22)..."
if timeout 5 bash -c "echo > /dev/tcp/$VM_IP/22" 2>/dev/null; then
    print_success "SSH port (22) is open"
else
    print_warning "SSH port (22) is not accessible"
fi
echo ""

# Try SSH with key
print_info "Testing SSH connection with key..."
if [ -f "$SSH_KEY" ]; then
    print_info "Using SSH key: $SSH_KEY"
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null "$SSH_USER@$VM_IP" "echo 'SSH works'" 2>&1; then
        print_success "SSH connection with key: SUCCESS"
        exit 0
    else
        print_warning "SSH connection with key: FAILED"
    fi
else
    print_warning "SSH key not found: $SSH_KEY"
fi
echo ""

# Try SSH with password (if sshpass available)
if command -v sshpass &> /dev/null; then
    print_info "Testing SSH connection with password..."
    if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null "$SSH_USER@$VM_IP" "echo 'SSH works'" 2>&1; then
        print_success "SSH connection with password: SUCCESS"
        exit 0
    else
        print_warning "SSH connection with password: FAILED"
    fi
else
    print_info "sshpass not available, skipping password test"
fi
echo ""

# Try virtctl ssh
if command -v virtctl &> /dev/null; then
    print_info "Testing virtctl ssh..."
    if virtctl ssh "$VM_NAME" -n "$NAMESPACE" --username "$SSH_USER" "echo 'SSH works'" 2>&1; then
        print_success "virtctl ssh: SUCCESS"
        exit 0
    else
        print_warning "virtctl ssh: FAILED or not supported in this version"
    fi
fi
echo ""

# Show verbose SSH attempt
print_info "Attempting verbose SSH connection..."
echo "Command: ssh -v -i $SSH_KEY $SSH_USER@$VM_IP 'echo test'"
echo ""
ssh -v -i "$SSH_KEY" -o ConnectTimeout=10 "$SSH_USER@$VM_IP" "echo 'test'" 2>&1 | head -30 || true

echo ""
print_info "Troubleshooting suggestions:"
echo "  1. Check VM console: virtctl console $VM_NAME -n $NAMESPACE"
echo "  2. In VM, check SSH: systemctl status sshd"
echo "  3. In VM, check authorized_keys: cat ~fedora/.ssh/authorized_keys"
echo "  4. In VM, check cloud-init: cat /etc/vm_status"
echo "  5. Check VM logs: oc logs -n $NAMESPACE -l kubevirt.io/domain=$VM_NAME"
