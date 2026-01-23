# Troubleshooting Guide

Common issues and solutions for ACM Observability Test Workloads.

## Table of Contents

- [Prerequisites Issues](#prerequisites-issues)
- [Cluster Context Issues](#cluster-context-issues)
- [Namespace Workload Issues](#namespace-workload-issues)
- [VM Workload Issues](#vm-workload-issues)
- [Thanos Metrics Issues](#thanos-metrics-issues)
- [Manual Commands Reference](#manual-commands-reference)

---

## Prerequisites Issues

### ACM/MCO Not Installed

**Symptom**: Metrics queries return empty results.

**Check**:
```bash
# Verify ACM is installed
oc get multiclusterobservability -A

# Check ACM hub components
oc get pods -n open-cluster-management
```

**Solution**: Install ACM Operator (version 2.14+) and deploy Multicluster Observability.

### OpenShift CLI Not Found

**Symptom**: `oc: command not found`

**Solution**:
```bash
# macOS
brew install openshift-cli

# Linux - Download from Red Hat
# https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
```

### jq Not Installed

**Symptom**: JSON parsing errors or raw JSON output.

**Solution**:
```bash
# macOS
brew install jq

# RHEL/CentOS
sudo yum install jq

# Ubuntu/Debian
sudo apt-get install jq
```

---

## Cluster Context Issues

### Context Not Found

**Symptom**: `error: no context exists with the name: "hub"`

**Solution**: Create the context:
```bash
oc login --token=<token> --server=<url>
oc config rename-context $(oc config current-context) hub
```

### Token Expired

**Symptom**: `error: You must be logged in to the server (Unauthorized)`

**Solution**: Re-login and recreate the context:
```bash
oc login --token=<new-token> --server=<url>
oc config delete-context hub
oc config rename-context $(oc config current-context) hub
```

### List Available Contexts

```bash
oc config get-contexts
```

---

## Namespace Workload Issues

### CronJobs Not Creating Jobs

**Check**:
```bash
# Check CronJob status
oc get cronjobs -n offline-workload
oc describe cronjob simple-cpu-workload -n offline-workload

# Check if suspended
oc get cronjob simple-cpu-workload -n offline-workload -o jsonpath='{.spec.suspend}'
```

**Solution**: Resume if suspended:
```bash
oc patch cronjob simple-cpu-workload -n offline-workload -p '{"spec":{"suspend":false}}'
```

### Pods Failing

**Check**:
```bash
# Check pod status
oc get pods -n offline-workload

# Check pod events
oc describe pod <pod-name> -n offline-workload

# Check logs
oc logs <pod-name> -n offline-workload
```

**Common Issues**:
- **ImagePullBackOff**: busybox image not available
- **CrashLoopBackOff**: Check logs for errors
- **Pending**: Insufficient resources

### Image Pull Errors

**Check**:
```bash
oc run test-pod --image=busybox:latest --rm -it --restart=Never -n offline-workload -- /bin/sh
```

**Solution**: The workloads use `busybox:latest`. Ensure the image is accessible or update YAML files to use a different image.

### Insufficient Resources

**Check**:
```bash
oc describe nodes
oc top nodes
```

**Solution**: Reduce resource requests/limits in YAML files:
```yaml
resources:
  requests:
    cpu: "50m"
    memory: "32Mi"
  limits:
    cpu: "200m"
    memory: "64Mi"
```

### Manually Trigger a Job

```bash
oc create job --from=cronjob/simple-cpu-workload manual-cpu-test -n offline-workload
```

### Check Workload Status

```bash
# All resources
oc get all -n offline-workload

# Resource usage
oc top pods -n offline-workload

# Logs
oc logs -f -n offline-workload -l app=simple-cpu
```

---

## VM Workload Issues

### OpenShift Virtualization Not Installed

**Check**:
```bash
oc get crd virtualmachines.kubevirt.io
```

**Solution**: Install OpenShift Virtualization operator from OperatorHub.

### VM Not Starting

**Check**:
```bash
oc get vm -n auto-vm-test
oc describe vm fedora-vm-1 -n auto-vm-test
oc get events -n auto-vm-test --sort-by='.lastTimestamp'
```

**Common Issues**:
- **ImagePullBackOff**: Check image URL and registry access
- **Pending**: Check cluster resources
- **CrashLoopBackOff**: Check VM logs

**Start a stopped VM**:
```bash
virtctl start fedora-vm-1 -n auto-vm-test
```

### SSH Connection Failed

**Check SSH access**:
```bash
# Get VM IP
oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}'

# Try SSH
ssh fedora@<vm-ip>
```

**If SSH key not injected**:
1. Check if `VM_SSH_PUBLIC_KEY` is set in `config.sh`
2. Delete and recreate VMs
3. Check cloud-init completed:
   ```bash
   virtctl exec fedora-vm-1 -n auto-vm-test -- cat /etc/vm_status
   ```

### Stress Test Not Running

**Check**:
```bash
# Verify stress-ng is installed
virtctl exec fedora-vm-1 -n auto-vm-test -- which stress-ng

# Check if stress is running
virtctl exec fedora-vm-1 -n auto-vm-test -- pgrep stress-ng
```

**Manually run stress**:
```bash
virtctl exec fedora-vm-1 -n auto-vm-test -- stress-ng --cpu 2 --vm 1 --vm-bytes 99% --timeout 5m
```

### Delete and Recreate VMs

```bash
# Delete VMs
oc delete vm --all -n auto-vm-test

# Delete namespace (removes everything)
oc delete namespace auto-vm-test

# Recreate
cd vm-workloads/scripts
./create-and-stress-test.sh
```

---

## Thanos Metrics Issues

### No Metrics Data Found

**Symptom**: `Warning: Metrics query succeeded but no data found`

**Causes**:
1. Workloads haven't been running long enough (wait 20+ minutes)
2. Wrong namespace name
3. ACM/MCO not properly configured

**Check metrics availability**:
```bash
# Test with 30-minute lookback
curl -k -G \
  --data-urlencode 'query=last_over_time(acm_rs:namespace:cpu_usage{namespace="offline-workload"}[30m])' \
  -H "Authorization: Bearer $(oc whoami -t)" \
  "https://$(oc get route -n openshift-monitoring thanos-querier -o jsonpath='{.spec.host}')/api/v1/query"
```

### Cannot Connect to Thanos

**Check**:
```bash
# Get Thanos route
oc get route -n openshift-monitoring thanos-querier

# Test connection
curl -k -I "https://$(oc get route -n openshift-monitoring thanos-querier -o jsonpath='{.spec.host}')"
```

**Solution**: Ensure you have access to `openshift-monitoring` namespace.

### Metrics Show N/A

**Why**: Thanos data is sent every 15 minutes. Instant queries may miss data.

**Solution**: Use `last_over_time(...[30m])` to get the latest value within 30 minutes:
```bash
# Instead of
acm_rs:namespace:cpu_usage{namespace="offline-workload"}

# Use
last_over_time(acm_rs:namespace:cpu_usage{namespace="offline-workload"}[30m])
```

---

## Manual Commands Reference

### Namespace Workloads

```bash
# Deploy
oc apply -f workloads/

# Trigger job manually
oc create job --from=cronjob/simple-cpu-workload test-$(date +%s) -n offline-workload

# Check status
oc get cronjobs,jobs,pods -n offline-workload

# View logs
oc logs -f -n offline-workload -l app=simple-cpu

# Cleanup
oc delete cronjobs,jobs,pods --all -n offline-workload
```

### VM Workloads

```bash
# List VMs
oc get vm -n auto-vm-test

# Start/Stop VM
virtctl start fedora-vm-1 -n auto-vm-test
virtctl stop fedora-vm-1 -n auto-vm-test

# Console access
virtctl console fedora-vm-1 -n auto-vm-test

# Execute command
virtctl exec fedora-vm-1 -n auto-vm-test -- <command>

# SSH into VM
ssh fedora@$(oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}')
```

### Thanos Queries

```bash
# Setup port-forward (alternative to route)
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091 &

# Query via route
THANOS_URL="https://$(oc get route -n openshift-monitoring thanos-querier -o jsonpath='{.spec.host}')"
TOKEN=$(oc whoami -t)

# Current value with 30min lookback
curl -k -G \
  --data-urlencode 'query=last_over_time(acm_rs:namespace:cpu_usage{namespace="offline-workload"}[30m])' \
  -H "Authorization: Bearer $TOKEN" \
  "$THANOS_URL/api/v1/query" | jq .

# Time series (last 4 hours)
END=$(date +%s)
START=$((END - 14400))
curl -k -G \
  --data-urlencode 'query=acm_rs:namespace:cpu_usage{namespace="offline-workload"}' \
  --data-urlencode "start=$START" \
  --data-urlencode "end=$END" \
  --data-urlencode "step=300" \
  -H "Authorization: Bearer $TOKEN" \
  "$THANOS_URL/api/v1/query_range" | jq .
```

### Modify Workload Resources

```bash
# Edit YAML directly
vi workloads/simple-cpu-workload.yaml
oc apply -f workloads/simple-cpu-workload.yaml

# Or use patch
oc patch cronjob simple-cpu-workload -n offline-workload --type='json' \
  -p='[{"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"}]'
```

---

## Getting Help

If you encounter issues not covered here:

1. Check OpenShift events: `oc get events -n <namespace> --sort-by='.lastTimestamp'`
2. Check operator logs: `oc logs -n open-cluster-management <pod-name>`
3. Verify ACM/MCO documentation for your version
