#!/bin/bash

# Script to check status of offline workloads

NAMESPACE="offline-workload"

echo "=========================================="
echo "Offline Workloads Status"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo "Namespace '$NAMESPACE' does not exist."
    exit 1
fi

echo "=== CronJobs ==="
oc get cronjobs -n "$NAMESPACE" 2>/dev/null || echo "No CronJobs found"
echo ""

echo "=== Running Jobs ==="
oc get jobs -n "$NAMESPACE" 2>/dev/null | grep -v "No resources" || echo "No running jobs"
echo ""

echo "=== Pods ==="
oc get pods -n "$NAMESPACE" 2>/dev/null | grep -v "No resources" || echo "No pods found"
echo ""

echo "=== Resource Usage ==="
oc top pods -n "$NAMESPACE" 2>/dev/null || echo "Metrics not available"
echo ""
