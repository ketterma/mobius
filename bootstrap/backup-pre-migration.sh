#!/bin/bash
# Pre-Migration Backup Script
# Creates ZFS snapshots and exports of critical data before VLAN migration

set -e

BACKUP_DIR="/tank/backups"
DATE="2025-11-01"

echo "=================================================="
echo "Pre-Migration Backup Script"
echo "Date: $DATE"
echo "=================================================="
echo ""

echo "Creating backup directory..."
sudo mkdir -p $BACKUP_DIR

echo ""
echo "=== 1. Snapshot Home Assistant VM ==="
echo "Creating snapshot: vms/HomeAssistant@pre-vlan-migration-$DATE"
sudo zfs snapshot vms/HomeAssistant@pre-vlan-migration-$DATE
echo "✓ Snapshot created"
sudo zfs list -t snapshot | grep HomeAssistant | grep $DATE

echo ""
echo "=== 2. Snapshot AdGuard Old Dataset ==="
echo "Dataset: pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3 (22.1M - has data)"
sudo zfs snapshot vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3@pre-vlan-migration-$DATE
echo "✓ Snapshot created"
echo "Exporting to $BACKUP_DIR/adguard-old-pvc-$DATE.zfs.gz ..."
sudo zfs send vms/homelab/pvc-5d323c8c-1dcd-4129-89a1-3e1352fcc3c3@pre-vlan-migration-$DATE | \
  gzip > $BACKUP_DIR/adguard-old-pvc-$DATE.zfs.gz
echo "✓ Export complete"

echo ""
echo "=== 3. Snapshot Pocket-ID Old Dataset ==="
echo "Dataset: pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe (808K - has data)"
sudo zfs snapshot vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe@pre-vlan-migration-$DATE
echo "✓ Snapshot created"
echo "Exporting to $BACKUP_DIR/pocket-id-old-pvc-$DATE.zfs.gz ..."
sudo zfs send vms/homelab/pvc-6f746e14-fd9b-426d-b84a-4545e2bdfbfe@pre-vlan-migration-$DATE | \
  gzip > $BACKUP_DIR/pocket-id-old-pvc-$DATE.zfs.gz
echo "✓ Export complete"

echo ""
echo "=== 4. Snapshot Traefik Certs ==="
echo "Dataset: pvc-ae7e12ae-8e18-400e-bcbc-fb19b066d742 (certificates)"
sudo zfs snapshot vms/homelab/pvc-ae7e12ae-8e18-400e-bcbc-fb19b066d742@pre-vlan-migration-$DATE
echo "✓ Snapshot created"

echo ""
echo "=================================================="
echo "=== Backup Summary ==="
echo "=================================================="
echo ""
echo "Backup files:"
ls -lh $BACKUP_DIR/*$DATE* 2>/dev/null || echo "No exported files yet"
echo ""
echo "ZFS Snapshots:"
sudo zfs list -t snapshot | grep $DATE
echo ""
echo "=================================================="
echo "✅ All backups complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Verify backups exist: ls -lh $BACKUP_DIR/"
echo "2. Test snapshot list: sudo zfs list -t snapshot | grep $DATE"
echo "3. Review PRE_MIGRATION_BACKUP.md for migration steps"
echo "4. Proceed with network migration when ready"
echo ""
