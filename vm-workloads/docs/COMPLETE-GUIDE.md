# Complete Guide - VM Creation and Stress Testing

Complete guide for creating Fedora VMs, running stress tests, and creating RHEL VMs in OpenShift Virtualization.

> **Security Note**: This project uses default passwords (`password`) for testing purposes only. **Always change passwords in YAML files (`vms/*.yaml`) before using in production environments.** SSH keys are recommended over passwords for better security.

## Quick Start

```bash
# 1. Navigate to scripts directory
cd vm-workloads/scripts

# 2. Set SSH key (optional but recommended)
# This will automatically update YAML files in ../vms/ directory
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# 3. Run the combined script
./create-and-stress-test.sh
```

That's it! The script automatically:
1. Creates Fedora VMs (fedora-vm-1, fedora-vm-2)
2. Runs stress test on fedora-vm-1
3. Creates RHEL VM (rhel-vm)

## What the Script Does

### Step 1: Create Fedora VMs
- Creates `auto-vm-test` namespace (if needed)
- Updates SSH keys in YAML files (if provided)
- Applies Fedora VM YAML files
- Waits for VMs to be running

### Step 2: Run Stress Test
- Waits 30 seconds for VMs to fully boot
- Gets VM IP address
- Tries multiple connection methods automatically:
  1. **virtctl exec** (no SSH needed) - fastest
  2. **Port-forwarding + SSH** - if VM IP not accessible
  3. **Direct SSH** - if VM IP is accessible
- Runs stress test on `fedora-vm-1` only
- Shows progress and metrics

### Step 3: Create RHEL VM
- Applies RHEL VM YAML file
- Waits for RHEL VM to be running

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
```

**Verify:**
```bash
oc version
```

#### 2. Login to OpenShift Cluster

```bash
oc login <your-cluster-url>
oc whoami  # Verify login
```

#### 3. Verify OpenShift Virtualization

```bash
oc get crd virtualmachines.kubevirt.io
```

#### 4. Install virtctl (Optional)

**macOS:**
```bash
brew install virtctl
```

**Verify:**
```bash
virtctl version
```

#### 5. Install sshpass (Optional)

**macOS:**
```bash
brew install hudochenkov/sshpass/sshpass
```

**Linux:**
```bash
sudo apt-get install sshpass  # Ubuntu/Debian
sudo yum install sshpass      # RHEL/CentOS
```

#### 6. Generate SSH Key (If needed)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### Verify All Prerequisites

```bash
oc version && echo "✅ oc installed"
oc whoami && echo "✅ Logged in"
oc get crd virtualmachines.kubevirt.io && echo "✅ Virtualization enabled"
virtctl version 2>/dev/null && echo "✅ virtctl installed" || echo "⚠️  virtctl optional"
[ -f ~/.ssh/id_rsa.pub ] && echo "✅ SSH key found" || echo "⚠️  SSH key optional"
```

## Detailed Usage

### Step 0: Navigate to Scripts Directory

**Important**: All scripts must be run from the `vm-workloads/scripts/` directory.

```bash
cd vm-workloads/scripts
chmod +x *.sh  # Make scripts executable (first time only)
```

### Step 1: Set Environment Variables (Optional)

**With SSH Key (Recommended):**
```bash
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
```

**Custom Credentials:**
```bash
export VM_SSH_USER="fedora"
export VM_SSH_PASSWORD="your-password"
export VM_SSH_PRIVATE_KEY="$HOME/.ssh/id_rsa"
```

### Step 2: Run the Script

**Basic Usage:**
```bash
./create-and-stress-test.sh
```

**With SSH Key:**
```bash
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
./create-and-stress-test.sh
```

**What happens:**
1. Script checks prerequisites (oc, login status)
2. Creates namespace if needed
3. Updates SSH keys in YAML files (if provided)
4. Creates Fedora VMs
5. Waits 30 seconds for VMs to boot
6. Runs stress test automatically
7. Creates RHEL VM
8. Shows completion status

## Expected Output

```
==========================================
VM Creation and Stress Test
==========================================

This script will:
  1. Create Fedora VMs (fedora-vm-1, fedora-vm-2)
  2. Run stress test on fedora-vm-1
  3. Create RHEL VM (rhel-vm)

✅ Prerequisites check passed

✅ Namespace 'auto-vm-test' created
✅ SSH key updated in YAML files

==========================================
Step 1: Creating Fedora VMs
==========================================

✅ Applied: fedora-vm-1.yaml
✅ Applied: fedora-vm-2.yaml
✅ VM 'fedora-vm-1' is running
✅ VM 'fedora-vm-2' is running
✅ Fedora VMs created and running

==========================================
Step 2: Running Stress Test
==========================================

ℹ️  Starting stress test on fedora-vm-1...
✅ VM IP: <VM_IP_ADDRESS>
✅ SSH is available on <VM_IP_ADDRESS>

ℹ️  Running stress test via direct SSH...
Command: stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief

--- Output ---
stress-ng: info:  [12345] dispatching hogs: 2 cpu, 1 vm
...
--- End Output ---

✅ Stress test completed

==========================================
Step 3: Creating RHEL VM
==========================================

✅ Applied: rhel-vm.yaml
✅ VM 'rhel-vm' is running
✅ RHEL VM created and running

==========================================
All Tasks Completed
==========================================

✅ Fedora VMs: Created
✅ Stress Test: Completed
✅ RHEL VM: Created
```

## VM Details

### Fedora VMs

- **Names**: `fedora-vm-1`, `fedora-vm-2`
- **Image**: `quay.io/containerdisks/fedora:latest`
- **Resources**: 2 CPU, 4GB RAM each
- **Credentials**: `fedora` / `password` (change in YAML files for production)
- **Purpose**: `fedora-vm-1` is used for stress testing

### RHEL VM

- **Name**: `rhel-vm`
- **Image**: `registry.redhat.io/rhel10/rhel-guest-image:latest`
- **Resources**: 2 CPU, 4GB RAM
- **Credentials**: `rhel` / `password` (change in YAML files for production)

**Note**: RHEL image may require Red Hat authentication. If you get `ImagePullBackOff`, create an image pull secret.

## Stress Test Details

The stress test runs on `fedora-vm-1` only:

```bash
stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief
```

- **Duration**: 15 minutes
- **CPU**: 2 CPUs stressed
- **Memory**: 99% memory usage
- **Method**: matrixprod (CPU-intensive)

## Connection Methods (Automatic)

The script tries these methods in order:

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

## Troubleshooting

### Stress Test Fails

If the stress test fails to connect:

1. **Check VM status:**
   ```bash
   oc get vm fedora-vm-1 -n auto-vm-test
   ```

2. **Check SSH status:**
   ```bash
   ./check-vm-ssh-internal.sh fedora-vm-1
   ```

3. **Run stress test manually:**
   ```bash
   virtctl console fedora-vm-1 -n auto-vm-test
   # Login: fedora / password
   # Then run: stress-ng --cpu 2 --cpu-method matrixprod --vm 1 --vm-bytes 99% --timeout 15m --metrics-brief
   ```

### RHEL Image Pull Error

If RHEL VM fails with `ImagePullBackOff`:

```bash
# Create image pull secret
oc create secret docker-registry redhat-registry-secret \
  --docker-server=registry.redhat.io \
  --docker-username=<your-redhat-username> \
  --docker-password=<your-redhat-password> \
  -n auto-vm-test

# Update rhel-vm.yaml to add imagePullSecrets section
```

### VM Not Running

```bash
# Check VM status
oc get vm -n auto-vm-test

# Start if stopped
virtctl start fedora-vm-1 -n auto-vm-test
virtctl start rhel-vm -n auto-vm-test
```

## Individual Scripts

If you prefer to run steps separately:

```bash
# Navigate to scripts directory first
cd vm-workloads/scripts

# 1. Create Fedora VMs only
./create-vms-from-yaml.sh

# 2. Run stress test only
./run-stress-from-yaml.sh

# 3. Create RHEL VM only
./create-rhel-vm.sh
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VM_SSH_PUBLIC_KEY` | SSH public key for key-based auth | Auto-detected from `~/.ssh/id_rsa.pub` if available |
| `VM_SSH_USER` | SSH username | `fedora` |
| `VM_SSH_PASSWORD` | SSH password | `password` (change in YAML files for production) |
| `VM_SSH_PRIVATE_KEY` | SSH private key path | `~/.ssh/id_rsa` |

**Security Note**: Default passwords are for testing only. Change passwords in YAML files (`vms/*.yaml`) before using in production environments.

## Files Structure

All files are located within the `workloads/` directory:

```
workloads/
└── vm-workloads/               # VM-related files
    ├── docs/                   # Documentation
    │   ├── README.md          # Main documentation
    │   ├── COMPLETE-GUIDE.md  # This file - complete guide
    │   └── SECURITY.md        # Security notice
    ├── scripts/                # Executable scripts
    │   ├── create-and-stress-test.sh    # Combined script (recommended)
    │   ├── create-vms-from-yaml.sh      # Fedora VMs only
    │   ├── run-stress-from-yaml.sh       # Stress test only
    │   ├── create-rhel-vm.sh            # RHEL VM only
    │   ├── check-vm-ssh-internal.sh      # Helper: Check SSH status
    │   ├── test-ssh-connection.sh        # Helper: Test SSH connection
    │   └── start-ssh-in-vm.sh            # Helper: Start SSH manually
    └── vms/                    # VM YAML definitions
        ├── fedora-vm-1.yaml    # Fedora VM 1 (stress test target)
        ├── fedora-vm-2.yaml    # Fedora VM 2
        └── rhel-vm.yaml        # RHEL VM
```

**Important**: 
- All scripts should be run from the `vm-workloads/scripts/` directory
- Scripts automatically reference YAML files in `../vms/` directory
- YAML files contain placeholder `YOUR_SSH_PUBLIC_KEY_HERE` which is automatically replaced by scripts

## After Completion

### Verify Success

```bash
# Check all VMs
oc get vm,vmi -n auto-vm-test

# All should show "Running" status
```

### Access VMs

```bash
# Console access
virtctl console fedora-vm-1 -n auto-vm-test

# SSH access (if IP available)
VM_IP=$(oc get vmi fedora-vm-1 -n auto-vm-test -o jsonpath='{.status.interfaces[0].ipAddress}')
ssh fedora@$VM_IP
```

### Clean Up

```bash
# Delete all VMs
oc delete vm --all -n auto-vm-test

# Delete namespace (removes everything)
oc delete namespace auto-vm-test
```

## Summary

**Simple usage:**
```bash
cd vm-workloads/scripts
chmod +x *.sh
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
./create-and-stress-test.sh
```

**What happens:**
1. ✅ Fedora VMs created
2. ✅ Stress test runs automatically (15 minutes)
3. ✅ RHEL VM created

**Total time**: ~20 minutes (5 min VM creation + 15 min stress test)

All in one command!
