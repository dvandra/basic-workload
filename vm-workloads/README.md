# VM Workloads - OpenShift Virtualization

This directory contains all VM-related files organized into separate folders:

## Directory Structure

```
vm-workloads/
├── docs/          # Documentation files
│   ├── README.md          # Main documentation
│   ├── COMPLETE-GUIDE.md # Complete guide
│   └── SECURITY.md        # Security notice
├── scripts/       # Executable scripts
│   ├── create-and-stress-test.sh    # Combined script (recommended)
│   ├── create-vms-from-yaml.sh      # Create Fedora VMs
│   ├── create-rhel-vm.sh            # Create RHEL VM
│   ├── run-stress-from-yaml.sh      # Run stress test
│   ├── check-vm-ssh-internal.sh     # Check SSH status
│   ├── test-ssh-connection.sh       # Test SSH connection
│   └── start-ssh-in-vm.sh           # Start SSH manually
└── vms/          # VM YAML definitions
    ├── fedora-vm-1.yaml    # Fedora VM 1 (stress test target)
    ├── fedora-vm-2.yaml    # Fedora VM 2
    └── rhel-vm.yaml        # RHEL VM
```

## Quick Start

```bash
# Navigate to scripts directory
cd vm-workloads/scripts

# Make scripts executable (first time only)
chmod +x *.sh

# Set SSH key (optional but recommended)
export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"

# Run combined script (creates VMs and runs stress test)
./create-and-stress-test.sh
```

## Documentation

- **Main Guide**: See `docs/README.md` for complete documentation
- **Complete Guide**: See `docs/COMPLETE-GUIDE.md` for detailed guide
- **Security**: See `docs/SECURITY.md` for security best practices

## Usage

All scripts must be run from the `scripts/` directory:

```bash
cd vm-workloads/scripts
./create-and-stress-test.sh
```

Scripts automatically reference YAML files in `../vms/` directory.

## Files Organization

- **docs/**: All documentation files
- **scripts/**: All executable shell scripts
- **vms/**: All VM YAML definition files

This separation makes it easy to:
- Find documentation
- Locate scripts
- Manage VM definitions
- Maintain the codebase
