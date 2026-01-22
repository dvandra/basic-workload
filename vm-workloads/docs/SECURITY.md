# Security Notice

## Default Credentials

This repository contains **default test credentials** that are **NOT suitable for production use**.

### Default Passwords

- **Fedora VMs**: `fedora` / `password`
- **RHEL VM**: `rhel` / `password`

⚠️ **IMPORTANT**: These passwords are for **testing and development only**. 

**Before using in production:**
1. Change all passwords in YAML files (`../vms/*.yaml` from scripts directory, or `vms/*.yaml` from vm-workloads root)
2. Use SSH keys instead of passwords when possible
3. Review and harden security settings

### SSH Keys

- YAML files use placeholder `YOUR_SSH_PUBLIC_KEY_HERE`
- Scripts automatically replace this with your SSH key if `VM_SSH_PUBLIC_KEY` is set
- **Never commit your private SSH keys** to this repository

## Best Practices

1. **Never commit sensitive data**:
   - Real passwords
   - SSH private keys
   - API keys or tokens
   - Cluster credentials
   - Personal information

2. **Use environment variables** for sensitive data:
   ```bash
   export VM_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
   export VM_SSH_PASSWORD="your-secure-password"
   ```

3. **Review `.gitignore`** to ensure sensitive files are excluded

4. **Change default passwords** in YAML files (`vms/*.yaml`) before production deployment

5. **Use SSH keys** instead of passwords when possible

## Reporting Security Issues

If you discover a security vulnerability, please report it responsibly rather than opening a public issue.
