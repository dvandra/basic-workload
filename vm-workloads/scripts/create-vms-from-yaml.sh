#!/bin/bash

# Script to create VMs from YAML files
# Usage: ./create-vms-from-yaml.sh

set -e

# Default namespace
NAMESPACE="auto-vm-test"

# VM YAML files directory (relative to scripts directory)
VM_DIR="../vms"

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
    
    # Escape special characters in SSH key for sed
    local escaped_key=$(echo "$ssh_key" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # Update SSH key in YAML files
    for yaml_file in "$VM_DIR"/*.yaml; do
        if [ -f "$yaml_file" ]; then
            # Check if file contains the placeholder
            if grep -q "YOUR_SSH_PUBLIC_KEY_HERE" "$yaml_file"; then
                # Create temp file with updated SSH key
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
        fi
    done
    
    print_success "SSH key updated in YAML files"
}

# Function to wait for VM IP
wait_for_vm_ip() {
    local vm_name="$1"
    local max_wait=300  # 5 minutes
    local elapsed=0
    
    print_info "Waiting for VM '$vm_name' to get an IP address..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Try VMI first (most reliable)
        local ip=$(oc get vmi "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")
        
        # Fallback to VM status
        if [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "" ]; then
            ip=$(oc get vm "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || echo "")
        fi
        
        if [ -n "$ip" ] && [ "$ip" != "null" ] && [ "$ip" != "" ]; then
            print_success "VM '$vm_name' IP: $ip"
            echo "$ip"
            return 0
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    echo ""
    print_warning "VM '$vm_name' did not get an IP address within $max_wait seconds"
    return 1
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
    echo "Using YAML files"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Check if VM directory exists
    if [ ! -d "$VM_DIR" ]; then
        print_error "VM directory '$VM_DIR' not found"
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
    
    for yaml_file in "$VM_DIR"/*.yaml; do
        if [ -f "$yaml_file" ]; then
            print_info "Applying: $yaml_file"
            oc apply -f "$yaml_file" || {
                print_error "Failed to apply $yaml_file"
                exit 1
            }
            print_success "Applied: $yaml_file"
        fi
    done
    
    echo ""
    
    # Wait for VMs to be running
    print_info "Waiting for VMs to start..."
    echo ""
    
    wait_for_vm_running "fedora-vm-1"
    wait_for_vm_running "fedora-vm-2"
    echo ""
    
    # Get VM IPs
    print_info "Getting VM IP addresses..."
    echo ""
    
    VM1_IP=$(wait_for_vm_ip "fedora-vm-1" || echo "")
    VM2_IP=$(wait_for_vm_ip "fedora-vm-2" || echo "")
    echo ""
    
    # Display summary
    echo "=========================================="
    echo "VM Creation Summary"
    echo "=========================================="
    echo ""
    echo "fedora-vm-1 (stress test target):"
    echo "  IP Address: ${VM1_IP:-Not assigned yet}"
    echo "  Status: $(oc get vm fedora-vm-1 -n $NAMESPACE -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo 'Unknown')"
    echo ""
    echo "fedora-vm-2:"
    echo "  IP Address: ${VM2_IP:-Not assigned yet}"
    echo "  Status: $(oc get vm fedora-vm-2 -n $NAMESPACE -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo 'Unknown')"
    echo ""
    
    # Show Service info
    local nodeport=$(oc get service fedora-vm-1-ssh-service -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    if [ -n "$nodeport" ]; then
        echo "SSH Service (NodePort): $nodeport"
        echo "  Access via: ssh -p $nodeport fedora@<node-ip>"
        echo ""
    fi
    
    print_success "VM creation completed!"
    echo ""
    echo "Next steps:"
    echo "  1. Wait a few minutes for VMs to fully boot"
    echo "  2. Run stress test: ./run-stress-from-yaml.sh"
    echo ""
}

# Run main function
main "$@"
