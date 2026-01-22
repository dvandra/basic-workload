# VM Stress Test - OpenShift Virtualization

Complete guide for creating VMs and running stress tests in OpenShift Virtualization.

> **Security Note**: This project uses default passwords (`password`) for testing purposes only. **Always change passwords in YAML files (`vms/*.yaml`) before using in production environments.** SSH keys are recommended over passwords for better security.

## Quick Reference

**One-command setup (recommended):**
```bash
cd vm-workloads/scripts
chmod +x *.sh
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"  # Optional
./create-and-stress-test.sh
```

**Individual steps:**
```bash
cd vm-workloads/scripts
chmod +x *.sh
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"  # Optional
./create-vms-from-yaml.sh      # Create Fedora VMs
./run-stress-from-yaml.sh      # Run stress test
./create-rhel-vm.sh            # Create RHEL VM
```

**Check status:**
```bash
oc get vm,vmi -n auto-vm-test
./check-vm-ssh-internal.sh fedora-vm-1
```

**Clean up:**
```bash
oc delete vm --all -n auto-vm-test
oc delete namespace auto-vm-test
```

## Quick Start

### Option 1: Combined Script (Recommended)

```bash
# 1. Navigate to scripts directory
cd vm-workloads/scripts

# 2. Set SSH key (optional but recommended)
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# 3. Run everything in one command
./create-and-stress-test.sh
```

This single script will:
- Create Fedora VMs (fedora-vm-1, fedora-vm-2)
- Run stress test on fedora-vm-1
- Create RHEL VM (rhel-vm)

### Option 2: Individual Scripts

```bash
# 1. Navigate to scripts directory
cd vm-workloads/scripts

# 2. Set SSH key (optional but recommended)
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# 3. Create Fedora VMs
./create-vms-from-yaml.sh

# 4. Wait 2-3 minutes for VMs to boot

# 5. Run stress test
./run-stress-from-yaml.sh

# 6. Create RHEL VM
./create-rhel-vm.sh
```

## Overview

This project uses:
- **YAML files** to define VMs (Kubernetes-style manifests)
- **nohup /usr/sbin/sshd** to start SSH (reliable during cloud-init)
- **Automated scripts** that try multiple connection methods

### VM Specifications

- **Namespace**: `auto-vm-test`
- **Fedora VMs** (created by `create-vms-from-yaml.sh`):
  - `fedora-vm-1` - Fedora Linux (stress test target)
  - `fedora-vm-2` - Fedora Linux (not used for stress tests)
- **RHEL VM** (created by `create-rhel-vm.sh`):
  - `rhel-vm` - Red Hat Enterprise Linux 10
- **Resources**: 2 CPU, 4GB RAM per VM
- **Images**:
  - Fedora: `quay.io/containerdisks/fedora:latest`
  - RHEL: `registry.redhat.io/rhel10/rhel-guest-image:latest`
- **Credentials**:
  - Fedora: `fedora` / `password` (change in YAML files for production)
  - RHEL: `rhel` / `password` (change in YAML files for production)

### Stress Test Command

```bash
stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief
```

Runs for 15 minutes, stressing 2 CPUs and 1 VM with 99% memory.

## Prerequisites

### Required

1. **OpenShift CLI (`oc`)** installed and logged in
2. **OpenShift Virtualization** enabled on your cluster
3. **SSH client** (usually pre-installed)

### Optional (but recommended)

4. **virtctl** - For direct VM command execution (faster than SSH)
5. **sshpass** - For password-based SSH (if not using SSH keys)

### Installation and Setup

#### 1. Install OpenShift CLI (`oc`)

**macOS:**
```bash
brew install openshift-cli
```

**Linux:**
```bash
# Download from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
# Or use package manager
```

**Verify installation:**
```bash
oc version
```

#### 2. Login to OpenShift Cluster

```bash
# Login to your OpenShift cluster
oc login <your-cluster-url>

# Verify you're logged in
oc whoami
```

#### 3. Verify OpenShift Virtualization is Enabled

```bash
# Check if KubeVirt is installed
oc get csv -n openshift-cnv | grep kubevirt

# Check if VirtualMachine CRD exists
oc get crd virtualmachines.kubevirt.io
```

#### 4. Install virtctl (Optional but Recommended)

**macOS:**
```bash
brew install virtctl
```

**Linux/Manual:**
```bash
# Download from https://github.com/kubevirt/kubevirt/releases
# Or use package manager
```

**Verify installation:**
```bash
virtctl version
```

#### 5. Install sshpass (Optional - for password-based SSH)

**macOS:**
```bash
brew install hudochenkov/sshpass/sshpass
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt-get install sshpass

# RHEL/CentOS
sudo yum install sshpass
```

#### 6. Generate SSH Key (If you don't have one)

```bash
# Generate SSH key pair (if you don't have one)
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# Your public key will be at:
# ~/.ssh/id_rsa.pub
```

### Verify All Prerequisites

Run this checklist:

```bash
# 1. Check oc
oc version && echo "✅ oc is installed"

# 2. Check login
oc whoami && echo "✅ Logged in to OpenShift"

# 3. Check Virtualization
oc get crd virtualmachines.kubevirt.io && echo "✅ OpenShift Virtualization enabled"

# 4. Check virtctl (optional)
virtctl version 2>/dev/null && echo "✅ virtctl installed" || echo "⚠️  virtctl not installed (optional)"

# 5. Check SSH key (optional)
[ -f ~/.ssh/id_rsa.pub ] && echo "✅ SSH key found" || echo "⚠️  SSH key not found (will use password auth)"
```

## Detailed Steps

### Step 0: Navigate to Scripts Directory

**Important**: All scripts must be run from the `vm-workloads/scripts/` directory.

```bash
cd vm-workloads/scripts
```

### Step 1: Set SSH Key (Optional but Recommended)

**If you have an SSH key:**
```bash
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
```

**If you don't have an SSH key, generate one:**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
```

**What this does:**
- Automatically updates the YAML files in the `vms/` directory with your SSH key
- Replaces `YOUR_SSH_PUBLIC_KEY_HERE` placeholder in the YAML files
- Enables key-based authentication (more secure than passwords)

**Note**: If you skip this step, the scripts will use password-based authentication (`password`).

### Step 2: Create VMs

**Make scripts executable (first time only):**
```bash
chmod +x *.sh
```

**For Fedora VMs:**
```bash
./create-vms-from-yaml.sh
```

**For RHEL VM:**
```bash
./create-rhel-vm.sh
```

**Or use the combined script (creates everything):**
```bash
./create-and-stress-test.sh
```

**What this does:**
- Creates `auto-vm-test` namespace (if it doesn't exist)
- Updates SSH keys in YAML files (if `VM_SSH_PUBLIC_KEY` is set)
- Applies YAML files from `vms/` directory
- Waits for VMs to reach "Running" status (up to 5 minutes)
- Shows VM status and IP addresses

**Expected wait time**: 2-5 minutes for VMs to fully boot

### Step 3: Wait for VMs to Boot

VMs need 2-5 minutes to:
- Complete cloud-init
- Install packages (stress-ng, openssh-server)
- Start SSH service
- Configure network

**Check VM status:**
```bash
# List all VMs
oc get vm -n auto-vm-test

# List VM instances (running VMs)
oc get vmi -n auto-vm-test

# Get detailed VM status
oc get vm fedora-vm-1 -n auto-vm-test -o yaml

# Watch VM status (press Ctrl+C to exit)
watch -n 2 'oc get vm,vmi -n auto-vm-test'
```

**Verify VM is ready:**
```bash
# Check if SSH is running inside VM
./check-vm-ssh-internal.sh fedora-vm-1
```

**Expected status**: All VMs should show `Running` status

### Step 4: Run Stress Test

**If using combined script (`create-and-stress-test.sh`):**
- Stress test runs automatically after VM creation
- No manual step needed

**If using individual scripts:**
```bash
./run-stress-from-yaml.sh
```

**What this does:**
- Checks VM is running
- Gets VM IP address
- Tries multiple connection methods automatically:
  1. **virtctl exec** (no SSH needed) - fastest, requires virtctl
  2. **Port-forwarding + SSH** - if VM IP not accessible, sets up `oc port-forward` automatically
  3. **Direct SSH** - if VM IP is accessible from your machine
- Runs stress test on `fedora-vm-1` only
- Shows progress and metrics in real-time

**Stress test duration**: 15 minutes

**Monitor during test:**
```bash
# In another terminal, watch VM resource usage
watch -n 5 'oc get vm,vmi -n auto-vm-test'
```

## Files Structure

All files are located within the `vm-workloads/` directory:

```
workloads/
└── vm-workloads/               # VM-related files
    ├── docs/                   # Documentation
    │   ├── README.md          # This file - main documentation
    │   ├── COMPLETE-GUIDE.md  # Complete guide for combined script
    │   └── SECURITY.md        # Security notice
    ├── scripts/                # Executable scripts
    │   ├── create-and-stress-test.sh    # Combined script: Everything in one
    │   ├── create-vms-from-yaml.sh      # Create Fedora VMs only
    │   ├── create-rhel-vm.sh            # Create RHEL VM only
    │   ├── run-stress-from-yaml.sh       # Run stress test only
    │   ├── check-vm-ssh-internal.sh      # Helper: Check SSH status in VM
    │   ├── test-ssh-connection.sh       # Helper: Test SSH connection
    │   └── start-ssh-in-vm.sh            # Helper: Start SSH manually
    └── vms/                    # VM YAML definitions
        ├── fedora-vm-1.yaml    # First Fedora VM (stress test target)
        ├── fedora-vm-2.yaml    # Second Fedora VM
        └── rhel-vm.yaml        # RHEL 10 VM
```

**Important**: All scripts should be run from the `vm-workloads/scripts/` directory. Scripts automatically reference YAML files in `../vms/`.

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `create-and-stress-test.sh` | **Main**: Combined script - Creates Fedora VMs, runs stress test, creates RHEL VM |
| `create-vms-from-yaml.sh` | Create Fedora VMs from YAML files only |
| `create-rhel-vm.sh` | Create RHEL VM from YAML files only |
| `run-stress-from-yaml.sh` | Run stress test only (auto-detects best method) |
| `check-vm-ssh-internal.sh` | Check if SSH is running in VM |
| `test-ssh-connection.sh` | Test SSH connection to VM |
| `start-ssh-in-vm.sh` | Start SSH in VM via console |

## Troubleshooting

### Script Fails with "oc command not found"

**Solution**: Install OpenShift CLI
```bash
# macOS
brew install openshift-cli

# Verify
oc version
```

### Script Fails with "Not logged in to OpenShift"

**Solution**: Login to your cluster
```bash
oc login <your-cluster-url>
oc whoami  # Verify login
```

### Script Fails with "virtualmachines.kubevirt.io" not found

**Solution**: OpenShift Virtualization is not enabled on your cluster
```bash
# Check if KubeVirt is installed
oc get csv -n openshift-cnv

# Contact your cluster administrator to enable OpenShift Virtualization
```

### SSH Not Working

If SSH connection fails:

1. **Check SSH status inside VM:**
   ```bash
   ./check-vm-ssh-internal.sh fedora-vm-1
   ```

2. **Test SSH connection:**
   ```bash
   ./test-ssh-connection.sh fedora-vm-1
   ```

3. **Start SSH manually:**
   ```bash
   ./start-ssh-in-vm.sh fedora-vm-1
   ```

4. **The script automatically tries port-forwarding** if direct SSH fails

5. **Check VM console directly:**
   ```bash
   virtctl console fedora-vm-1 -n auto-vm-test
   # Login: fedora / password
   # Then manually start SSH:
   # sudo /usr/sbin/sshd
   ```

### VM Not Running

**Check VM status:**
```bash
# Check status
oc get vm fedora-vm-1 -n auto-vm-test

# Get detailed status
oc describe vm fedora-vm-1 -n auto-vm-test
```

**Start stopped VM:**
```bash
virtctl start fedora-vm-1 -n auto-vm-test
```

**Check VM events for errors:**
```bash
oc get events -n auto-vm-test --sort-by='.lastTimestamp' | grep fedora-vm-1
```

**Common issues:**
- **ImagePullBackOff**: Image cannot be pulled (check image path, network, or registry credentials)
- **CrashLoopBackOff**: VM keeps crashing (check VM logs)
- **Pending**: VM cannot be scheduled (check cluster resources)

### Credentials Issue

If you see "No credentials" message when accessing VM console:

1. **Delete and recreate VMs:**
   ```bash
   oc delete vm fedora-vm-1 fedora-vm-2 -n auto-vm-test
   ./create-vms-from-yaml.sh
   ```

2. **Verify credentials:**
   ```bash
   virtctl console fedora-vm-1 -n auto-vm-test
   # Login: fedora / password
   ```

3. **Check cloud-init completed:**
   ```bash
   # Via virtctl exec
   virtctl exec fedora-vm-1 -n auto-vm-test -- cat /etc/vm_status
   
   # Should show: "VM Ready for Stress Test"
   ```

4. **If cloud-init failed, check logs:**
   ```bash
   # Get virt-launcher pod
   POD=$(oc get pods -n auto-vm-test -l kubevirt.io/domain=fedora-vm-1 -o jsonpath='{.items[0].metadata.name}')
   
   # Check logs
   oc logs $POD -n auto-vm-test | grep -i cloud-init
   ```

### Recreate VMs

To recreate VMs with updated YAML:

```bash
# Delete existing VMs and services
oc delete vm fedora-vm-1 fedora-vm-2 rhel-vm -n auto-vm-test
oc delete svc -n auto-vm-test -l app=fedora-vm-1,app=fedora-vm-2,app=rhel-vm

# Wait for cleanup (optional)
sleep 10

# Recreate
./create-vms-from-yaml.sh
./create-rhel-vm.sh
```

### Clean Up Everything

To remove all VMs and namespace:

```bash
# Delete all VMs
oc delete vm --all -n auto-vm-test

# Delete namespace (removes everything)
oc delete namespace auto-vm-test

# Verify cleanup
oc get vm -n auto-vm-test  # Should show "NotFound"
```

### Stress Test Not Starting

**Check if VM is ready:**
```bash
# Check VM status
oc get vm fedora-vm-1 -n auto-vm-test

# Check if SSH is available
./check-vm-ssh-internal.sh fedora-vm-1

# Check VM IP
oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}'
```

**Try manual connection:**
```bash
# Get VM IP
VM_IP=$(oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}')

# Test SSH
ssh -o StrictHostKeyChecking=no fedora@$VM_IP "echo 'SSH works'"
```

**Run stress test manually via console:**
```bash
virtctl console fedora-vm-1 -n auto-vm-test
# Login: fedora / password
# Then run:
stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief
```

## Manual Commands

### Check VM Status

```bash
# List VMs
oc get vm -n auto-vm-test

# Get VM IP
oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}'

# Check VM console
virtctl console fedora-vm-1 -n auto-vm-test
```

### Run Stress Test Manually

```bash
# Via console
virtctl console fedora-vm-1 -n auto-vm-test
# Login: fedora / password
# Then run: stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief

# Via SSH (if accessible)
VM_IP=$(oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}')
ssh fedora@$VM_IP 'stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief'
```

## How It Works

### Connection Methods (Automatic)

The `run-stress-from-yaml.sh` script tries these methods in order:

1. **virtctl exec** (no SSH needed)
   - Direct command execution in VM
   - Fastest method
   - Requires virtctl with exec support

2. **Port-forwarding + SSH**
   - Sets up `oc port-forward` automatically
   - Works when VM IP is not directly accessible
   - Cleans up port-forward when done

3. **Direct SSH**
   - Connects directly to VM IP
   - Works when VM IP is accessible from your machine

### VM Creation Process

1. YAML files define VM specifications
2. `create-vms-from-yaml.sh` applies YAML files
3. Cloud-init configures:
   - User: `fedora` with password `password` (change in YAML for production)
   - SSH keys (replaces `YOUR_SSH_PUBLIC_KEY_HERE` placeholder if provided via `VM_SSH_PUBLIC_KEY`)
   - Packages: `stress-ng`, `openssh-server`
   - SSH service started via `nohup /usr/sbin/sshd`

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VM_SSH_PUBLIC_KEY` | SSH public key for key-based auth | Auto-detected from `~/.ssh/id_rsa.pub` if available |
| `VM_SSH_USER` | SSH username | `fedora` |
| `VM_SSH_PASSWORD` | SSH password | `password` (change in YAML files for production) |
| `VM_SSH_PRIVATE_KEY` | SSH private key path | `~/.ssh/id_rsa` |

**Security Note**: Default passwords are for testing only. Change passwords in YAML files (`vms/*.yaml`) before using in production environments.

## Expected Output

The stress test runs for 15 minutes and shows:

```
stress-ng: info:  [12345] dispatching hogs: 2 cpu, 1 vm
stress-ng: info:  [12345] successful run completed in 900.00s
stress-ng: info:  [12345] stressor      bogo ops real time  usr time  sys time   bogo ops/s
stress-ng: info:  [12345] cpu              12345    900.00    1800.00    0.00      13.72
stress-ng: info:  [12345] vm               12345    900.00    0.00       0.00      13.72
```

## After Script Completion

### Verify Everything Worked

```bash
# Check all VMs are running
oc get vm -n auto-vm-test

# Check VM instances
oc get vmi -n auto-vm-test

# Check stress test completed (if using combined script)
# The script output will show "✅ Stress test completed"
```

### Access VMs

**Via Console:**
```bash
virtctl console fedora-vm-1 -n auto-vm-test
# Login: fedora / password
```

**Via SSH (if IP accessible):**
```bash
VM_IP=$(oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}')
ssh fedora@$VM_IP
```

**Via Port-Forward:**
```bash
# Get virt-launcher pod
POD=$(oc get pods -n auto-vm-test -l kubevirt.io/domain=fedora-vm-1 -o jsonpath='{.items[0].metadata.name}')

# Port forward
oc port-forward $POD -n auto-vm-test 2222:22

# In another terminal
ssh -p 2222 fedora@localhost
```

### View Stress Test Results

If stress test completed, the output will show metrics. To view VM resource usage:

```bash
# Watch VM resources
watch -n 5 'oc get vm,vmi -n auto-vm-test -o wide'
```

### Next Steps

- **Monitor VMs**: Use `oc get vm -n auto-vm-test` to check status
- **Run additional tests**: SSH into VMs and run custom commands
- **Clean up**: Delete VMs when done (see Clean Up section)

## Additional Documentation

All documentation is in the `docs/` directory:
- `docs/COMPLETE-GUIDE.md` - **Complete guide for combined script** (recommended)
- `docs/SECURITY.md` - Security notice and best practices

## Support

For issues:
1. Check VM status: `oc get vm -n auto-vm-test`
2. Check SSH: `./check-vm-ssh-internal.sh fedora-vm-1`
3. Check logs: `oc logs -n auto-vm-test -l kubevirt.io/domain=fedora-vm-1`
4. Review troubleshooting section above

## License

See LICENSE file in parent directory for details.
