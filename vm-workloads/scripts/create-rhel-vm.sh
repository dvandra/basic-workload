#!/bin/bash

# Script to create RHEL VM from YAML files
# Usage: ./create-rhel-vm.sh

set -e

# Default namespace
NAMESPACE="auto-vm-test"

# VM YAML files (relative to scripts directory)
RHEL_YAML="../vms/rhel-vm.yaml"

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

    # Check if logged in to OpenShift
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
    
    # Try to get SSH key from default location if not set
    if [ -z "$ssh_key" ] && [ -f "$HOME/.ssh/id_rsa.pub" ]; then
        ssh_key=$(cat "$HOME/.ssh/id_rsa.pub")
        print_info "Using SSH key from default location: $HOME/.ssh/id_rsa.pub"
    fi
    
    if [ -z "$ssh_key" ]; then
        print_warning "No SSH public key provided (VM_SSH_PUBLIC_KEY not set)"
        print_info "VMs will be created with placeholder SSH key"
        print_info "To use SSH keys, set: export VM_SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_rsa.pub)\""
        return 0
    fi
    
    print_info "Updating SSH public key in YAML files..."
    
    # Update SSH key in YAML files
    for yaml_file in "$RHEL_YAML"; do
        if [ ! -f "$yaml_file" ]; then
            continue
        fi
        # Check if file contains the placeholder
        if grep -q "YOUR_SSH_PUBLIC_KEY_HERE" "$yaml_file"; then
            # Use perl for better handling of special characters
            if command -v perl &> /dev/null; then
                perl -i -pe "s|YOUR_SSH_PUBLIC_KEY_HERE|$ssh_key|g" "$yaml_file"
            else
                # Fallback to sed with proper escaping
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
    local max_wait=300  # 5 minutes
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

# Main script
main() {
    echo "=========================================="
    echo "OpenShift Virtualization VM Creator"
    echo "Creating RHEL VM"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Check if YAML file exists
    if [ ! -f "$RHEL_YAML" ]; then
        print_error "RHEL YAML file not found: $RHEL_YAML"
        exit 1
    fi
    
    # Create namespace
    create_namespace
    echo ""
    
    # Update SSH keys if provided
    update_ssh_key
    echo ""
    
    # Apply YAML files
    print_info "Applying VM YAML files..."
    echo ""
    
    # Apply RHEL VM
    print_info "Applying: $RHEL_YAML"
    oc apply -f "$RHEL_YAML" || {
        print_error "Failed to apply $RHEL_YAML"
        exit 1
    }
    print_success "Applied: $RHEL_YAML"
    
    echo ""
    
    # Wait for VM to be running
    print_info "Waiting for VM to start..."
    echo ""
    
    wait_for_vm_running "rhel-vm"
    echo ""
    
    print_success "RHEL VM creation completed!"
    echo ""
}

# Run main function
main "$@"
