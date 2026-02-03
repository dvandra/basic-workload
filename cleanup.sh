#!/bin/bash

# Script to clean up workloads (namespace and VM)
# Usage: ./cleanup.sh [--skip-vm] [--skip-namespace] [--keep-namespace]
#
# By default, cleans up BOTH namespace and VM workloads AND deletes the namespaces

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration if available, otherwise use defaults
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh" 2>/dev/null
fi

NAMESPACE="${NAMESPACE_WORKLOAD_NS:-offline-workload}"
VM_NAMESPACE="${VM_WORKLOAD_NS:-auto-vm-test}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments - default is to clean BOTH and delete namespaces
CLEANUP_NAMESPACE=true
CLEANUP_VM=true
DELETE_NAMESPACE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-vm)
            CLEANUP_VM=false
            shift
            ;;
        --skip-namespace)
            CLEANUP_NAMESPACE=false
            shift
            ;;
        --namespace-only)
            CLEANUP_NAMESPACE=true
            CLEANUP_VM=false
            shift
            ;;
        --vm-only)
            CLEANUP_NAMESPACE=false
            CLEANUP_VM=true
            shift
            ;;
        --keep-namespace|--keep-namespaces)
            DELETE_NAMESPACE=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "By default, cleans up BOTH namespace and VM workloads AND deletes namespaces."
            echo ""
            echo "Options:"
            echo "  --skip-vm          Skip VM workload cleanup"
            echo "  --skip-namespace   Skip namespace workload cleanup"
            echo "  --namespace-only   Cleanup only namespace workloads"
            echo "  --vm-only          Cleanup only VM workloads"
            echo "  --keep-namespace   Keep namespaces (don't delete them)"
            echo "  -h, --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Full cleanup (delete everything including namespaces)"
            echo "  $0 --keep-namespace   # Cleanup resources but keep namespaces"
            echo "  $0 --skip-vm          # Cleanup only namespace workloads"
            echo "  $0 --skip-namespace   # Cleanup only VM workloads"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "Cleaning up Workloads"
echo "=========================================="
echo ""

if [[ "$CLEANUP_NAMESPACE" == "true" ]]; then
    echo -e "${BLUE}Namespace to clean:${NC} $NAMESPACE"
fi
if [[ "$CLEANUP_VM" == "true" ]]; then
    echo -e "${BLUE}VM Namespace to clean:${NC} $VM_NAMESPACE"
fi
if [[ "$DELETE_NAMESPACE" == "true" ]]; then
    echo -e "${YELLOW}Namespaces will be DELETED${NC}"
else
    echo -e "${BLUE}Namespaces will be kept (--keep-namespace)${NC}"
fi
echo ""

# Cleanup namespace workloads
if [[ "$CLEANUP_NAMESPACE" == "true" ]]; then
    echo -e "${BLUE}── Namespace Workloads ──${NC}"
    echo ""
    
    # Switch to namespace spoke context
    if [[ -n "$NAMESPACE_SPOKE_CONTEXT_NAME" ]]; then
        echo -e "Switching to context: ${NAMESPACE_SPOKE_CONTEXT_NAME}"
        oc config use-context "$NAMESPACE_SPOKE_CONTEXT_NAME" &>/dev/null || {
            echo -e "${YELLOW}Warning: Could not switch to context '$NAMESPACE_SPOKE_CONTEXT_NAME'${NC}"
        }
    fi
    
    if ! oc get namespace "$NAMESPACE" &>/dev/null; then
        echo -e "  ${YELLOW}Namespace '$NAMESPACE' does not exist. Nothing to clean up.${NC}"
    else
        echo "  Deleting CronJobs..."
        oc delete cronjobs --all -n "$NAMESPACE" --ignore-not-found=true || true

        echo "  Deleting Jobs..."
        oc delete jobs --all -n "$NAMESPACE" --ignore-not-found=true || true

        echo "  Deleting Pods..."
        oc delete pods --all -n "$NAMESPACE" --ignore-not-found=true || true

        echo -e "  ${GREEN}✅ Namespace workloads cleaned${NC}"
        
        # Delete namespace if requested
        if [[ "$DELETE_NAMESPACE" == "true" ]]; then
            echo ""
            echo "  Deleting namespace '$NAMESPACE'..."
            oc delete namespace "$NAMESPACE" --ignore-not-found=true || true
            echo -e "  ${GREEN}✅ Namespace '$NAMESPACE' deleted${NC}"
        fi
    fi
    echo ""
fi

# Cleanup VM workloads
if [[ "$CLEANUP_VM" == "true" ]]; then
    echo -e "${BLUE}── VM Workloads ──${NC}"
    echo ""
    
    # Switch to VM spoke context
    if [[ -n "$VM_SPOKE_CONTEXT_NAME" ]]; then
        echo -e "Switching to context: ${VM_SPOKE_CONTEXT_NAME}"
        oc config use-context "$VM_SPOKE_CONTEXT_NAME" &>/dev/null || {
            echo -e "${YELLOW}Warning: Could not switch to context '$VM_SPOKE_CONTEXT_NAME'${NC}"
        }
    fi
    
    if ! oc get namespace "$VM_NAMESPACE" &>/dev/null; then
        echo -e "  ${YELLOW}Namespace '$VM_NAMESPACE' does not exist. Nothing to clean up.${NC}"
    else
        echo "  Deleting VMs..."
        oc delete vm --all -n "$VM_NAMESPACE" --ignore-not-found=true || true

        echo "  Deleting VMIs..."
        oc delete vmi --all -n "$VM_NAMESPACE" --ignore-not-found=true || true

        echo "  Deleting Services..."
        oc delete svc --all -n "$VM_NAMESPACE" --ignore-not-found=true || true

        echo "  Deleting DataVolumes..."
        oc delete dv --all -n "$VM_NAMESPACE" --ignore-not-found=true || true

        echo "  Deleting PVCs..."
        oc delete pvc --all -n "$VM_NAMESPACE" --ignore-not-found=true || true

        echo -e "  ${GREEN}✅ VM workloads cleaned${NC}"
        
        # Delete namespace if requested
        if [[ "$DELETE_NAMESPACE" == "true" ]]; then
            echo ""
            echo "  Deleting namespace '$VM_NAMESPACE'..."
            oc delete namespace "$VM_NAMESPACE" --ignore-not-found=true || true
            echo -e "  ${GREEN}✅ Namespace '$VM_NAMESPACE' deleted${NC}"
        fi
    fi
    echo ""
fi

echo "=========================================="
echo -e "${GREEN}Cleanup Complete!${NC}"
echo "=========================================="
