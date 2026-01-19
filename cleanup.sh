#!/bin/bash

# Script to clean up offline workloads

set -e

NAMESPACE="offline-workload"

echo "=========================================="
echo "Cleaning up Offline Workloads"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo "Namespace '$NAMESPACE' does not exist. Nothing to clean up."
    exit 0
fi

echo "Deleting CronJobs..."
oc delete cronjobs --all -n "$NAMESPACE" --ignore-not-found=true

echo ""
echo "Deleting Jobs..."
oc delete jobs --all -n "$NAMESPACE" --ignore-not-found=true

echo ""
echo "Deleting Pods..."
oc delete pods --all -n "$NAMESPACE" --ignore-not-found=true

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "To delete the namespace:"
echo "  oc delete namespace $NAMESPACE"
echo ""
