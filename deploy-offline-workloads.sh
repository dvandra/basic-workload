#!/bin/bash

# Script to deploy offline workloads to OpenShift cluster
# These workloads run entirely within the cluster, no external dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="offline-workload"

echo "=========================================="
echo "Deploying Offline Workloads to OpenShift"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo "Error: oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

echo "Current user: $(oc whoami)"
echo "Current context: $(oc config current-context)"
echo ""

# Create namespace
echo "Creating namespace: $NAMESPACE"
oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f -

echo ""
echo "Deploying CronJobs..."
echo ""

# Deploy all workloads
for file in simple-cpu-workload.yaml simple-memory-workload.yaml file-io-workload.yaml network-workload.yaml combined-workload.yaml; do
    if [ -f "$SCRIPT_DIR/workloads/$file" ]; then
        echo "Deploying $file..."
        oc apply -f "$SCRIPT_DIR/workloads/$file"
    fi
done

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "CronJobs deployed in $NAMESPACE:"
oc get cronjobs -n "$NAMESPACE"
echo ""
echo "To manually trigger workloads:"
echo "  ./run-workload.sh cpu"
echo "  ./run-workload.sh memory"
echo "  ./run-workload.sh io"
echo "  ./run-workload.sh network"
echo "  ./run-workload.sh combined"
echo "  ./run-workload.sh all"
echo ""
echo "To view status:"
echo "  oc get jobs,pods -n $NAMESPACE"
echo ""
