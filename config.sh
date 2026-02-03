#!/bin/bash

# =============================================================================
# Configuration File for ACM Observability Workloads
# =============================================================================
#
# This file provides DEFAULT values. Environment variables take precedence.
#
# RECOMMENDED: Set environment variables instead of editing this file:
#
#   export HUB_CONTEXT_NAME="hub"
#   export NAMESPACE_SPOKE_CONTEXT_NAME="namespace-spoke"
#   export VM_SPOKE_CONTEXT_NAME="vm-spoke"
#   export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
#
# See README.md for complete setup instructions.
# =============================================================================

# -----------------------------------------------------------------------------
# Cluster Context Names
# -----------------------------------------------------------------------------
# These are the kubectl/oc context names for your clusters.
# Environment variables override these defaults.
#
# SINGLE CLUSTER SETUP (default):
#   If you only have one cluster, just set HUB_CONTEXT_NAME.
#   Spoke contexts default to Hub, so all workloads deploy to the same cluster.
#
# MULTI-CLUSTER SETUP:
#   Set separate context names for each cluster:
#     export HUB_CONTEXT_NAME="hub"
#     export NAMESPACE_SPOKE_CONTEXT_NAME="namespace-spoke"
#     export VM_SPOKE_CONTEXT_NAME="vm-spoke"

export HUB_CONTEXT_NAME="${HUB_CONTEXT_NAME:-hub}"
export NAMESPACE_SPOKE_CONTEXT_NAME="${NAMESPACE_SPOKE_CONTEXT_NAME:-$HUB_CONTEXT_NAME}"
export VM_SPOKE_CONTEXT_NAME="${VM_SPOKE_CONTEXT_NAME:-$HUB_CONTEXT_NAME}"

# -----------------------------------------------------------------------------
# Namespace Configuration
# -----------------------------------------------------------------------------
# Namespaces where workloads will be deployed

export NAMESPACE_WORKLOAD_NS="${NAMESPACE_WORKLOAD_NS:-offline-workload}"
export VM_WORKLOAD_NS="${VM_WORKLOAD_NS:-auto-vm-test}"

# -----------------------------------------------------------------------------
# SSH Configuration for VM Workloads (REQUIRED for VM workloads)
# -----------------------------------------------------------------------------
# SSH public key to inject into VMs for access
#
# IMPORTANT: Set VM_SSH_PUBLIC_KEY before running VM workloads:
#   export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

export VM_SSH_PUBLIC_KEY="${VM_SSH_PUBLIC_KEY:-$(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo '')}"
export VM_SSH_PRIVATE_KEY="${VM_SSH_PRIVATE_KEY:-$HOME/.ssh/id_rsa}"
export VM_SSH_USER="${VM_SSH_USER:-fedora}"
export VM_SSH_PASSWORD="${VM_SSH_PASSWORD:-password}"

# -----------------------------------------------------------------------------
# Timing Configuration
# -----------------------------------------------------------------------------
# Wait time before checking metrics (in seconds)
# Thanos data is sent every 15 minutes, so 20 minutes ensures data is available

export METRICS_WAIT_TIME="${METRICS_WAIT_TIME:-1200}"  # 20 minutes

# Stress test duration for VMs
export VM_STRESS_DURATION="${VM_STRESS_DURATION:-5m}"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Switch to a specific cluster context
switch_context() {
    local context_name=$1
    if ! oc config use-context "$context_name" &>/dev/null; then
        echo "Error: Could not switch to context '$context_name'"
        echo "Please ensure the context exists. Run: oc config get-contexts"
        return 1
    fi
    return 0
}

# Verify a context exists and is accessible
verify_context() {
    local context_name=$1
    if ! oc config use-context "$context_name" &>/dev/null; then
        return 1
    fi
    if ! oc whoami &>/dev/null; then
        return 1
    fi
    return 0
}

# Get script directory (useful for sourcing from subdirectories)
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# -----------------------------------------------------------------------------
# Validation (runs when sourced)
# -----------------------------------------------------------------------------

# Warn if SSH key is not set for VM workloads
if [[ -z "$VM_SSH_PUBLIC_KEY" ]]; then
    echo "⚠️  Warning: VM_SSH_PUBLIC_KEY is not set."
    echo "   VM workloads require an SSH key. Set it with:"
    echo "   export VM_SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_rsa.pub)\""
    echo ""
fi
