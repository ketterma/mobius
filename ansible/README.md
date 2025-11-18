# Homelab Ansible Configuration

Ansible playbooks for managing bare-metal infrastructure that lives outside Kubernetes.

## Quick Start

```bash
cd ansible

# Install required collections
ansible-galaxy collection install -r requirements.yml

# Dry-run to see what would change
ansible-playbook playbooks/site.yml --check --diff

# Apply changes
ansible-playbook playbooks/site.yml
```

## Structure

```
ansible/
├── ansible.cfg           # Ansible configuration
├── requirements.yml      # Required collections
├── inventory/
│   └── hosts.yml         # Host inventory
├── playbooks/
│   ├── site.yml          # Main playbook
│   └── n5.yml            # N5-specific playbook
└── roles/
    └── sanoid/           # ZFS snapshot management
        ├── defaults/     # Default variables
        ├── tasks/        # Tasks
        ├── templates/    # Config templates
        └── handlers/     # Handlers
```

## Roles

### sanoid

Installs and configures Sanoid for ZFS snapshot management.

**Features:**
- Automated ZFS snapshots with retention policies
- Pre/post snapshot scripts for VM fs-freeze
- Creates backup datasets

**Variables:** See `roles/sanoid/defaults/main.yml`

## Common Commands

```bash
# Run specific role
ansible-playbook playbooks/site.yml --tags sanoid

# Run on specific host
ansible-playbook playbooks/site.yml --limit n5

# Check what would change
ansible-playbook playbooks/site.yml --check --diff

# Verbose output
ansible-playbook playbooks/site.yml -vvv
```

## Adding New Roles

1. Create role structure: `mkdir -p roles/newrole/{tasks,templates,defaults,handlers}`
2. Add tasks in `roles/newrole/tasks/main.yml`
3. Add role to appropriate playbook
4. Test with `--check --diff`
