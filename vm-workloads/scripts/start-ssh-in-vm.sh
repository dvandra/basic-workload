#!/bin/bash

# Script to start SSH in VM via console
# Usage: ./start-ssh-in-vm.sh [vm-name]

set -e

NAMESPACE="auto-vm-test"
VM_NAME="${1:-fedora-vm-1}"
SSH_USER="fedora"
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

main() {
    echo "=========================================="
    echo "Start SSH in VM via Console"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    if ! command -v virtctl &> /dev/null; then
        print_error "virtctl command not found"
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
    
    print_info "Instructions to start SSH:"
    echo ""
    echo "1. Connect to VM console:"
    echo "   virtctl console $VM_NAME -n $NAMESPACE"
    echo ""
    echo "2. Login with:"
    echo "   Username: $SSH_USER"
    echo "   Password: $SSH_PASSWORD"
    echo ""
    echo "3. Once logged in, run these commands:"
    echo ""
    echo "   # Check if SSH is installed"
    echo "   which sshd || sudo dnf install -y openssh-server"
    echo ""
    echo "   # Generate SSH host keys if missing"
    echo "   sudo ssh-keygen -A"
    echo ""
    echo "   # Start SSH service"
    echo "   sudo systemctl start sshd"
    echo "   sudo systemctl enable sshd"
    echo ""
    echo "   # Or if systemd is not ready, use nohup:"
    echo "   sudo mkdir -p /var/run/sshd"
    echo "   sudo nohup /usr/sbin/sshd > /dev/null 2>&1 &"
    echo ""
    echo "   # Verify SSH is running"
    echo "   pgrep -f /usr/sbin/sshd"
    echo "   sudo netstat -tlnp | grep :22"
    echo ""
    echo "   # Check authorized_keys"
    echo "   cat ~/.ssh/authorized_keys"
    echo ""
    echo "4. Exit console: Press Ctrl+] or Ctrl+5"
    echo ""
    echo "5. Then test SSH:"
    echo "   ./test-ssh-connection.sh $VM_NAME"
    echo ""
    
    read -p "Do you want to open the console now? (y/N): " open_console
    if [[ "$open_console" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Opening console... (Press Ctrl+] or Ctrl+5 to exit)"
        echo ""
        virtctl console "$VM_NAME" -n "$NAMESPACE"
    else
        print_info "Run the commands above manually when ready"
    fi
}

main "$@"
