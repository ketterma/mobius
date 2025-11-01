# Pre-Migration Backup & Data Preservation Plan

**Date:** 2025-11-01
**Status:** ✅ Analysis Complete - Ready for Backup

---

## Critical Data Identified

### 1. Home Assistant VM (MUST PRESERVE)

**Location:** `vms/HomeAssistant` (zvol)
**Size:** 130G used, 26.6G referenced
**Type:** Block device (zvol, not filesystem)
**Current Status:** Not currently running in libvirt

**Backup Plan:**
```bash
# Create snapshot
sudo zfs snapshot vms/HomeAssistant@pre-vlan-migration-2025-11-01

# Verify snapshot
sudo zfs list -t snapshot | grep HomeAssistant
```

**Recovery if needed:**
```bash
# Rollback to snapshot
sudo zfs rollback vms/HomeAssistant@pre-vlan-migration-2025-11-01
```

---

### 2. AdGuard Home Data (MUST PRESERVE)

**Old Dataset (with data):** `vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3`
- **Created:** Wed Oct 29 23:30 2025
- **Size:** 22.1M (contains history/stats)
- **Status:** Not currently bound to cluster

**Current Dataset (NEW - can abandon):**
- `pvc-525d6de7-b456-45c2-8bd2-4f227f0b088d` (96K - conf)
- `pvc-1a070451-1157-4d8d-8b85-ba788f11fe74` (100K - work)

**Backup Plan:**
```bash
# Snapshot old AdGuard dataset with data
sudo zfs snapshot vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3@pre-vlan-migration-2025-11-01

# Export data for manual inspection/backup
sudo zfs send vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3@pre-vlan-migration-2025-11-01 | \
  gzip > /tank/backups/adguard-old-pvc-2025-11-01.zfs.gz
```

**Migration Strategy:**
After cluster rebuild, we can:
1. Create new AdGuard PVC
2. Mount old dataset temporarily and copy data over, OR
3. Rename old dataset to match new PVC name

---

### 3. Pocket-ID Data (MUST PRESERVE)

**Old Dataset (with data):** `vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe`
- **Created:** Thu Oct 30 0:53 2025
- **Size:** 808K
- **Status:** Not currently bound to cluster

**Current Dataset (NEW - can abandon):**
- `pvc-4de06aaa-aa63-4476-9a23-b13163d2d61b` (556K)

**Backup Plan:**
```bash
# Snapshot old Pocket-ID dataset
sudo zfs snapshot vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe@pre-vlan-migration-2025-11-01

# Export data for manual inspection/backup
sudo zfs send vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe@pre-vlan-migration-2025-11-01 | \
  gzip > /tank/backups/pocket-id-old-pvc-2025-11-01.zfs.gz
```

**Migration Strategy:**
Same as AdGuard - restore after cluster rebuild.

---

### 4. Traefik Certificates (Less Critical)

**Current Dataset:** `pvc-ae7e12ae-8e18-400e-bcbc-fb19b066d742` (100K)
- Created Nov 1 2:40
- Contains Let's Encrypt certificates
- Can be regenerated, but snapshot for convenience

**Backup Plan:**
```bash
sudo zfs snapshot vms/homelab/pvc-ae7e12ae-8e18-400e-bcbc-fb19b066d742@pre-vlan-migration-2025-11-01
```

---

## M1-ubuntu Considerations

**Network Layout:**
- Single interface: `enp0s1` (virtio network)
- Simple DHCP-assigned IP: 192.168.8.81 → 192.168.4.81
- No VLAN configuration needed (it's a VM, host handles VLANs)
- Has kube-router bridge0 (10.244.1.0/24) for pod network

**MetalLB Consideration:**
M1-ubuntu does NOT have the VLAN sub-interfaces like N5 does. This means:
- MetalLB L2 advertisements should ONLY happen on N5
- M1-ubuntu should NOT be selected for L2 advertisements
- Current config already has `nodeSelectors: kubernetes.io/hostname=n5` ✅

**Migration Plan:**
```bash
# On M1-ubuntu (via SSH to 192.168.8.81)
# Simple netplan update - just change IP address

sudo nano /etc/netplan/50-cloud-init.yaml
# Change: 192.168.8.81 → 192.168.4.81
# Change gateway: 192.168.8.1 → 192.168.4.1

sudo netplan apply
```

---

## Backup Execution Script

Create `/tank/backups/` directory and run:

```bash
#!/bin/bash
# File: backup-pre-migration.sh

set -e

BACKUP_DIR="/tank/backups"
DATE="2025-11-01"

echo "Creating backup directory..."
sudo mkdir -p $BACKUP_DIR

echo ""
echo "=== 1. Snapshot Home Assistant VM ==="
sudo zfs snapshot vms/HomeAssistant@pre-vlan-migration-$DATE
sudo zfs list -t snapshot | grep HomeAssistant | grep $DATE

echo ""
echo "=== 2. Snapshot AdGuard Old Dataset ==="
sudo zfs snapshot vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3@pre-vlan-migration-$DATE
echo "Exporting to $BACKUP_DIR/adguard-old-pvc-$DATE.zfs.gz ..."
sudo zfs send vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3@pre-vlan-migration-$DATE | \
  gzip > $BACKUP_DIR/adguard-old-pvc-$DATE.zfs.gz

echo ""
echo "=== 3. Snapshot Pocket-ID Old Dataset ==="
sudo zfs snapshot vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe@pre-vlan-migration-$DATE
echo "Exporting to $BACKUP_DIR/pocket-id-old-pvc-$DATE.zfs.gz ..."
sudo zfs send vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe@pre-vlan-migration-$DATE | \
  gzip > $BACKUP_DIR/pocket-id-old-pvc-$DATE.zfs.gz

echo ""
echo "=== 4. Snapshot Traefik Certs ==="
sudo zfs snapshot vms/homelab/pvc-ae7e12ae-8e18-400e-bcbc-fb19b066d742@pre-vlan-migration-$DATE

echo ""
echo "=== Backup Summary ==="
ls -lh $BACKUP_DIR/*$DATE*
sudo zfs list -t snapshot | grep $DATE

echo ""
echo "✅ All backups complete!"
echo ""
echo "Next steps:"
echo "1. Verify backups exist: ls -lh $BACKUP_DIR/"
echo "2. Test snapshot list: sudo zfs list -t snapshot"
echo "3. Proceed with network migration"
```

---

## Network Migration Order

### Phase 1: Create Backups (This Script)
Run the backup script above on N5.

### Phase 2: Network Reconfiguration

**N5 Network Migration:**
```bash
# On N5 (still at 192.168.8.8)

# 1. Copy netplan config
sudo cp /Users/jax/Documents/homelab/bootstrap/netplan-vlan-config.yaml /etc/netplan/01-netcfg.yaml

# 2. Remove old netplan config (if exists)
sudo rm -f /etc/netplan/50-cloud-init.yaml

# 3. Apply new config
sudo netplan apply

# 4. Verify new IP
ip addr show enp197s0.4 | grep 192.168.4.5

# 5. Test connectivity
ping -c 3 192.168.4.1

# Connection will drop here - reconnect via new IP:
# ssh jax@192.168.4.5
```

**M1-ubuntu Network Migration:**
```bash
# On M1-ubuntu (still at 192.168.8.81)

# Create new netplan config
sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s1:
      dhcp4: no
      addresses:
        - 192.168.4.81/24
      routes:
        - to: default
          via: 192.168.4.1
      nameservers:
        addresses:
          - 192.168.4.53  # AdGuard Home (after migration)
          - 1.1.1.1       # Cloudflare fallback
EOF

# Remove old config
sudo rm -f /etc/netplan/50-cloud-init.yaml

# Apply
sudo netplan apply

# Verify
ip addr show enp0s1 | grep 192.168.4.81

# Connection will drop - reconnect via:
# ssh jax@192.168.4.81
```

### Phase 3: Reset k0s Cluster

**On N5 (via 192.168.4.5):**
```bash
# Stop k0s
sudo systemctl stop k0scontroller k0sworker || true
sudo k0s stop || true

# Reset k0s
sudo k0s reset

# Clean state
sudo rm -rf /var/lib/k0s /etc/k0s
```

**On M1-ubuntu (via 192.168.4.81):**
```bash
# Stop k0s worker
sudo systemctl stop k0sworker || true
sudo k0s stop || true

# Reset
sudo k0s reset

# Clean state
sudo rm -rf /var/lib/k0s /etc/k0s
```

### Phase 4: Deploy New Cluster

**From your laptop:**
```bash
cd /Users/jax/Documents/homelab

# Deploy new k0s cluster with new IPs
k0sctl apply --config bootstrap/homelab-k0sctl.yaml

# Get kubeconfig
k0sctl kubeconfig --config bootstrap/homelab-k0sctl.yaml > ~/.kube/homelab-new.yaml

# Merge into main config
KUBECONFIG=~/.kube/config:~/.kube/homelab-new.yaml kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config

# Switch context
kubectl config use-context homelab

# Verify
kubectl get nodes -o wide
```

---

## Data Restoration After Migration

After the cluster is rebuilt and Flux has deployed all services:

### Restore AdGuard Data
```bash
# Option 1: Rename old dataset to match new PVC
NEW_PVC=$(kubectl -n adguard-home get pvc adguard-work -o jsonpath='{.spec.volumeName}' | sed 's/pvc-//')
sudo zfs rename vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3 vms/homelab/pvc-$NEW_PVC

# Restart AdGuard pod to pick up data
kubectl -n adguard-home delete pod -l app=adguard-home

# Option 2: Copy data from backup
# (mount both datasets and rsync)
```

### Restore Pocket-ID Data
```bash
# Same approach as AdGuard
NEW_PVC=$(kubectl -n pocket-id get pvc pocket-id-data -o jsonpath='{.spec.volumeName}' | sed 's/pvc-//')
sudo zfs rename vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe vms/homelab/pvc-$NEW_PVC

kubectl -n pocket-id delete pod -l app=pocket-id
```

### Restore Home Assistant VM
Home Assistant zvol is already in the right place - just needs libvirt VM definition via KubeVirt after migration.

---

## Verification Checklist

After migration:
- [ ] N5 accessible at 192.168.4.5
- [ ] M1-ubuntu accessible at 192.168.4.81
- [ ] kubectl get nodes shows both nodes
- [ ] MetalLB assigns 192.168.4.53 to AdGuard
- [ ] MetalLB assigns 192.168.8.50 to Traefik
- [ ] AdGuard data restored (history visible)
- [ ] Pocket-ID data restored (users/config intact)
- [ ] Home Assistant VM can be started
- [ ] All snapshots still exist for rollback

---

## Rollback Plan

If migration fails:

### Network Rollback
```bash
# On N5
sudo rm /etc/netplan/01-netcfg.yaml
# Recreate old single-interface config with 192.168.8.8
sudo netplan apply

# On M1-ubuntu
# Revert to 192.168.8.81
```

### Data Rollback
```bash
# Home Assistant
sudo zfs rollback vms/HomeAssistant@pre-vlan-migration-2025-11-01

# AdGuard
sudo zfs rollback vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3@pre-vlan-migration-2025-11-01

# Pocket-ID
sudo zfs rollback vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe@pre-vlan-migration-2025-11-01
```

### Cluster Rollback
Use old k0sctl config with old IPs to rebuild if needed.

---

**Status:** Ready to execute backup script ✅
