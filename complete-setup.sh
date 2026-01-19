#!/bin/bash

# Complete setup script for offline workloads
# This script handles everything from login to running workloads

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="offline-workload"

echo "=========================================="
echo "Complete Offline Workloads Setup"
echo "=========================================="
echo ""

# Step 1: Check if oc is installed
echo "Step 1: Checking OpenShift CLI..."
if ! command -v oc &> /dev/null; then
    echo "❌ Error: oc command not found."
    echo "Please install OpenShift CLI first:"
    echo "  https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
    exit 1
fi
echo "✅ OpenShift CLI found"
echo ""

# Step 2: Check if logged in
echo "Step 2: Checking OpenShift login status..."
if ! oc whoami &> /dev/null; then
    echo "❌ Not logged in to OpenShift"
    echo ""
    echo "Please login first using one of these methods:"
    echo ""
    echo "Method 1: Interactive login"
    echo "  oc login <your-openshift-api-url>"
    echo ""
    echo "Method 2: With username and password"
    echo "  oc login <your-openshift-api-url> -u <username> -p <password>"
    echo ""
    echo "Method 3: With token"
    echo "  oc login <your-openshift-api-url> --token=<your-token>"
    echo ""
    echo "After logging in, run this script again."
    exit 1
fi

CURRENT_USER=$(oc whoami)
CURRENT_CONTEXT=$(oc config current-context)
echo "✅ Logged in as: $CURRENT_USER"
echo "✅ Current context: $CURRENT_CONTEXT"
echo ""

# Step 3: Create namespace
echo "Step 3: Creating namespace..."
oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - > /dev/null
echo "✅ Namespace '$NAMESPACE' ready"
echo ""

# Step 4: Deploy CronJobs
echo "Step 4: Deploying CronJobs..."
for file in simple-cpu-workload.yaml simple-memory-workload.yaml file-io-workload.yaml network-workload.yaml combined-workload.yaml; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        oc apply -f "$SCRIPT_DIR/$file" > /dev/null
        echo "  ✅ Deployed $file"
    fi
done
echo ""

# Step 5: Verify deployment
echo "Step 5: Verifying deployment..."
CronJob_COUNT=$(oc get cronjobs -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$CronJob_COUNT" -ge 5 ]; then
    echo "✅ All CronJobs deployed successfully ($CronJob_COUNT CronJobs)"
else
    echo "⚠️  Warning: Expected 5 CronJobs, found $CronJob_COUNT"
fi
echo ""

# Step 6: Summary
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Namespace: $NAMESPACE"
echo "CronJobs deployed:"
oc get cronjobs -n "$NAMESPACE" --no-headers | awk '{print "  - " $1}'
echo ""
echo "Next steps:"
echo "  1. Run workloads: ./run-workload.sh all"
echo "  2. Check status: ./status.sh"
echo "  3. View logs: oc logs -f -n $NAMESPACE -l app=simple-cpu"
echo ""
