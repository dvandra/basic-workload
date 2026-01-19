#!/bin/bash

# Script to manually trigger offline workloads
# Usage: ./run-workload.sh [cpu|memory|io|network|combined|all]

set -e

NAMESPACE="offline-workload"
WORKLOAD_TYPE="${1:-all}"

if [ -z "$1" ]; then
    echo "Usage: $0 [cpu|memory|io|network|combined|all]"
    exit 1
fi

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

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo "Error: Namespace '$NAMESPACE' does not exist. Run ./deploy-offline-workloads.sh first."
    exit 1
fi

TIMESTAMP=$(date +%s)

case "$WORKLOAD_TYPE" in
    cpu)
        echo "Triggering CPU workload..."
        oc create job --from=cronjob/simple-cpu-workload cpu-test-$TIMESTAMP -n "$NAMESPACE"
        echo "Job created: cpu-test-$TIMESTAMP"
        ;;
    memory)
        echo "Triggering Memory workload..."
        oc create job --from=cronjob/simple-memory-workload memory-test-$TIMESTAMP -n "$NAMESPACE"
        echo "Job created: memory-test-$TIMESTAMP"
        ;;
    io)
        echo "Triggering File I/O workload..."
        oc create job --from=cronjob/file-io-workload io-test-$TIMESTAMP -n "$NAMESPACE"
        echo "Job created: io-test-$TIMESTAMP"
        ;;
    network)
        echo "Triggering Network workload..."
        oc create job --from=cronjob/network-workload network-test-$TIMESTAMP -n "$NAMESPACE"
        echo "Job created: network-test-$TIMESTAMP"
        ;;
    combined)
        echo "Triggering Combined workload..."
        oc create job --from=cronjob/combined-workload combined-test-$TIMESTAMP -n "$NAMESPACE"
        echo "Job created: combined-test-$TIMESTAMP"
        ;;
    all)
        echo "Triggering all workloads..."
        oc create job --from=cronjob/simple-cpu-workload cpu-test-$TIMESTAMP -n "$NAMESPACE"
        oc create job --from=cronjob/simple-memory-workload memory-test-$TIMESTAMP -n "$NAMESPACE"
        oc create job --from=cronjob/file-io-workload io-test-$TIMESTAMP -n "$NAMESPACE"
        oc create job --from=cronjob/network-workload network-test-$TIMESTAMP -n "$NAMESPACE"
        oc create job --from=cronjob/combined-workload combined-test-$TIMESTAMP -n "$NAMESPACE"
        echo "All workloads triggered!"
        ;;
    *)
        echo "Error: Unknown workload type '$WORKLOAD_TYPE'"
        echo "Usage: $0 [cpu|memory|io|network|combined|all]"
        exit 1
        ;;
esac

echo ""
echo "To view status:"
echo "  oc get jobs,pods -n $NAMESPACE"
echo ""
echo "To view logs:"
echo "  oc logs -f -n $NAMESPACE -l job-name=<job-name>"
echo ""
