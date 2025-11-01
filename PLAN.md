# 🔄 Homelab Network VLAN Migration Plan

**Status:** 🚧 In Progress
**Started:** 2025-11-01
**Target Completion:** TBD

---

## Migration Overview

### Objective
Migrate from single-VLAN (192.168.8.0/24) to multi-VLAN architecture with proper network segmentation:

- **VLAN 4** (192.168.4.0/24): Services/NAS/SSH/k0s nodes
- **VLAN 8** (192.168.8.0/24): Infrastructure VIPs (MetalLB LoadBalancers)
- **VLAN 16** (192.168.16.0/20): Sandbox/Untrusted workloads
- **VLAN 64** (192.168.64.0/20): IoT (Home Assistant VM)

### Key Decisions
- ✅ MetalLB VIPs: **Split between VLANs** (Infra in VLAN 4, Services in VLAN 8)
- ✅ Home Assistant Bridge: **Repurpose bridge0 → bridge64** for VLAN 64 IoT
- ✅ VLAN 4 Gateway: **192.168.4.1** (UDM Pro)
- ✅ MetalLB Mode: **L2 only** (removing BGP complexity)

---

## IP Address Changes

### Host Changes
| Host | Old IP | New IP | VLAN | Status |
|------|--------|--------|------|--------|
| N5 (controller) | 192.168.8.8 | 192.168.4.5 | 4 | ⏳ Pending |
| N5 node-ip (k8s) | 192.168.8.9 | 192.168.4.5 | 4 | ⏳ Pending |
| M1-ubuntu (worker) | 192.168.8.81 | 192.168.4.81 | 4 | ⏳ Pending |
| Home Assistant VM | 192.168.8.10 | 192.168.64.2 | 64 | ⏳ Pending |

### Service LoadBalancer Changes
| Service | Old IP | New IP | VLAN | Pool | Status |
|---------|--------|--------|------|------|--------|
| AdGuard Home (DNS) | 192.168.8.53 | 192.168.4.53 | 4 | infra-pool-vlan4 | ⏳ Pending |
| Traefik (Ingress) | 192.168.8.50 | 192.168.8.50 | 8 | services-pool-vlan8 | ⏳ No change |

### MetalLB Pool Changes
| Pool Name | Old Range | New Range | VLAN | Interface | Status |
|-----------|-----------|-----------|------|-----------|--------|
| services-pool | 192.168.8.50-79 | 192.168.8.50-79 | 8 | enp197s0.8 | ⏳ Pending |
| infra-pool (BGP) | 192.168.4.53/32 | REMOVED | - | - | ⏳ Pending |
| infra-pool-vlan4 (NEW) | - | 192.168.4.50-59 | 4 | enp197s0.4 | ⏳ Pending |

---

## Migration Phases

### ☑️ Phase 0: Pre-Migration (Completed)
- [x] Backup current k0s configuration
- [x] Document current state in CLAUDE.md
- [x] Update UDM Pro DHCP reservations
- [x] Verify VLAN configuration on UDM Pro
- [x] Create migration plan document

### ⏳ Phase 1: Configuration Updates (In Progress)
- [x] Create PLAN.md migration tracker
- [ ] Update `bootstrap/homelab-k0sctl.yaml` with new IPs
- [ ] Update MetalLB configuration (remove BGP, split pools)
- [ ] Update AdGuard Home service LoadBalancer IP
- [ ] Update Home Assistant ExternalName service IP
- [ ] Create netplan configuration for VLAN interfaces
- [ ] Remove obsolete BGP configuration files

### ⏳ Phase 2: Network Interface Reconfiguration
**⚠️ This phase requires SSH access to N5 and will cause brief downtime**

- [ ] SSH to N5: `ssh jax@192.168.8.8` (old IP, still active)
- [ ] Create VLAN 4 interface: `enp197s0.4` (192.168.4.5/24)
- [ ] Create VLAN 8 interface: `enp197s0.8` (no IP, for MetalLB only)
- [ ] Create VLAN 16 interface: `enp197s0.16` (no IP, future use)
- [ ] Rename bridge0 → bridge64
- [ ] Create VLAN 64 on eno1: `eno1.64`
- [ ] Attach eno1.64 to bridge64
- [ ] Set bridge64 IP: 192.168.64.1/20
- [ ] Update default route to use 192.168.4.1 via enp197s0.4
- [ ] Apply netplan configuration for persistence
- [ ] Verify network connectivity from new VLAN 4 IP
- [ ] Test SSH access: `ssh jax@192.168.4.5` (new IP)

### ⏳ Phase 3: M1 Worker Reconfiguration
**⚠️ Requires access to M1-ubuntu worker**

- [ ] SSH to M1-ubuntu: `ssh user@192.168.8.81` (old IP)
- [ ] Update M1-ubuntu network configuration to 192.168.4.81
- [ ] Verify connectivity to N5: `ping 192.168.4.5`
- [ ] Test SSH access: `ssh user@192.168.4.81` (new IP)

### ⏳ Phase 4: k0s Cluster Reset & Rebuild
**⚠️ This phase will destroy the existing cluster - all workloads will be down**

- [ ] Stop k0s: `sudo k0s stop`
- [ ] Reset k0s: `sudo k0s reset`
- [ ] Clean state: `sudo rm -rf /var/lib/k0s /etc/k0s`
- [ ] Re-initialize cluster: `k0sctl apply --config bootstrap/homelab-k0sctl.yaml`
- [ ] Verify cluster: `kubectl get nodes -o wide`
- [ ] Check node IPs are correct (N5: 192.168.4.5, M1: 192.168.4.81)

### ⏳ Phase 5: Flux CD Redeployment
- [ ] Bootstrap Flux: `flux bootstrap github ...`
- [ ] Wait for reconciliation: `flux get kustomizations`
- [ ] Monitor pod deployment: `watch kubectl get pods -A`
- [ ] Verify all kustomizations healthy

### ⏳ Phase 6: MetalLB Verification
- [ ] Check IPAddressPools: `kubectl -n metallb-system get ipaddresspools`
- [ ] Check L2Advertisements: `kubectl -n metallb-system get l2advertisements`
- [ ] Verify LoadBalancer services: `kubectl get svc -A | grep LoadBalancer`
- [ ] Verify AdGuard Home has IP 192.168.4.53
- [ ] Verify Traefik has IP 192.168.8.50

### ⏳ Phase 7: Service Configuration & Testing
- [ ] Update AdGuard Home DNS rewrites in admin UI:
  - [ ] `home.jax-lab.dev` → `192.168.8.50` (Traefik VIP)
  - [ ] `dns.jax-lab.dev` → `192.168.8.50` (Traefik VIP)
  - [ ] `n8n.jax-lab.dev` → `192.168.8.50` (if exists)
- [ ] Test DNS resolution: `dig @192.168.4.53 google.com`
- [ ] Test internal DNS: `dig @192.168.4.53 home.jax-lab.dev`
- [ ] Test Traefik ingress: `curl -k https://dns.jax-lab.dev`

### ⏳ Phase 8: Home Assistant VM Migration
**⚠️ Requires libvirt/VM reconfiguration**

- [ ] Shutdown Home Assistant VM
- [ ] Detach vnet1 from old bridge0
- [ ] Attach vnet1 to new bridge64
- [ ] Start Home Assistant VM
- [ ] Reconfigure Home Assistant network to 192.168.64.2/20
- [ ] Set gateway to 192.168.64.1
- [ ] Test connectivity from VM: `ping 192.168.4.5`
- [ ] Test DNS from VM: `dig @192.168.4.53 google.com`
- [ ] Test Traefik access from VM: `curl -k https://home.jax-lab.dev`
- [ ] Verify Home Assistant web UI: `https://home.jax-lab.dev`

### ⏳ Phase 9: Documentation Updates
- [ ] Update CLAUDE.md with new network topology
- [ ] Update K0S_ARCHITECTURE.md with new IP allocation
- [ ] Update bootstrap/README.md with new SSH IPs
- [ ] Update k8s/README.md with new quick start guide
- [ ] Update other documentation as needed

### ⏳ Phase 10: Final Verification & Cleanup
- [ ] Test all services externally (from VPS via Twingate)
- [ ] Test all services internally (from laptop on LAN)
- [ ] Verify Let's Encrypt certificates renew correctly
- [ ] Verify monitoring (Uptime Kuma) works
- [ ] Remove old BGP configuration from UDM Pro
- [ ] Git commit all configuration changes
- [ ] Update PLAN.md status to ✅ Complete

---

## Rollback Plan

If migration fails at any phase:

1. **Before cluster reset (Phases 1-3):**
   - Revert network configuration on N5 to 192.168.8.8
   - Revert M1-ubuntu to 192.168.8.81
   - Revert configuration files to git HEAD
   - No cluster downtime

2. **After cluster reset (Phases 4+):**
   - Use backup k0sctl.yaml with old IPs
   - Re-initialize cluster with old configuration
   - Restore from backups if needed
   - Expected recovery time: 15-30 minutes

---

## Configuration Files Modified

### ✅ Completed
- [ ] `bootstrap/homelab-k0sctl.yaml` - k0s cluster node IPs
- [ ] `k8s/clusters/lab/infrastructure-config/metallb-config.yaml` - MetalLB pools and L2
- [ ] `k8s/clusters/lab/apps/adguard/service.yaml` - AdGuard LoadBalancer IP
- [ ] `k8s/clusters/lab/apps/homeassistant/service.yaml` - Home Assistant ExternalName
- [ ] `bootstrap/netplan-vlan-config.yaml` - NEW: Persistent VLAN interfaces
- [ ] `bootstrap/udm-pro-bgp.conf` - REMOVED: No longer using BGP

### ✅ Documentation
- [ ] `CLAUDE.md` - Network topology and IP references
- [ ] `K0S_ARCHITECTURE.md` - IP allocation table
- [ ] `bootstrap/README.md` - SSH access instructions
- [ ] `k8s/README.md` - Quick start guide
- [x] `PLAN.md` - This file (migration tracker)

---

## Network Topology Reference

### Before Migration
```
enp197s0 (10G) ─── 192.168.8.8 ─┬─ N5 Host (SSH)
                                 └─ k0s node traffic

eno1 (5G) ───────────────────────┬─ bridge0 (192.168.8.9)
                                 ├─ vnet1 → Home Assistant (192.168.8.10)
                                 └─ k0s pod network binding

MetalLB (192.168.8.50-79) ───────── All services on VLAN 8
BGP Peer (192.168.8.1) ──────────── UDM Pro
```

### After Migration
```
enp197s0.4 (VLAN 4) ─── 192.168.4.5 ─┬─ N5 Host (SSH, default route)
                                      └─ k0s node traffic

enp197s0.8 (VLAN 8) ─── (no IP) ─────── MetalLB services pool
enp197s0.16 (VLAN 16) ── (no IP) ─────── Future sandbox workloads

eno1.64 (VLAN 64) ───┬─ bridge64 (192.168.64.1)
                     └─ vnet1 → Home Assistant (192.168.64.2)

MetalLB Pools:
├─ infra-pool-vlan4 (192.168.4.50-59) → L2 on enp197s0.4
└─ services-pool-vlan8 (192.168.8.50-79) → L2 on enp197s0.8

No BGP (removed)
```

---

## Important Notes

### ⚠️ Downtime Expectations
- **Phase 2-3** (Network reconfig): 5-10 minutes (host connectivity changes)
- **Phase 4** (k0s reset): 10-15 minutes (cluster rebuild)
- **Phase 5** (Flux sync): 5-10 minutes (workload deployment)
- **Phase 8** (HAOS migration): 5-10 minutes (VM reconfiguration)
- **Total estimated downtime:** 30-45 minutes

### ⚠️ Critical Prerequisites
1. UDM Pro VLANs 4, 8, 16, 64 must exist and be trunked to N5 switch port
2. DHCP static reservations must be configured for new IPs
3. Access to UDM Pro admin UI (for BGP removal and verification)
4. Backup of AdGuard Home configuration (in case of data loss)
5. Out-of-band access to N5 (in case SSH breaks during network reconfig)

### ⚠️ Things That Will Break During Migration
- All k8s services will be down during cluster reset
- SSH access will change from 192.168.8.x to 192.168.4.x
- DNS (AdGuard Home) will be unavailable during cluster rebuild
- Home Assistant will be offline during VM network migration
- External access via VPS will be down until services recover

### ✅ Things That Should Continue Working
- Internet access from LAN clients (via UDM Pro default gateway)
- VPS services (Dokploy, Uptime Kuma) - independent of homelab
- Twingate connectivity (no configuration changes needed)

---

## Troubleshooting

### SSH Connection Issues
**Problem:** Cannot SSH to N5 after network reconfig
**Solution:**
- Try old IP: `ssh jax@192.168.8.8`
- Try new IP: `ssh jax@192.168.4.5`
- Check DHCP lease on UDM Pro
- Use out-of-band access (physical console, iDRAC, etc.)

### k0s Won't Start
**Problem:** k0s fails to start after reset
**Solution:**
- Check logs: `sudo journalctl -u k0s -f`
- Verify network connectivity: `ping 192.168.4.1`
- Verify node IP is correct: `ip addr show enp197s0.4`
- Check k0sctl.yaml for syntax errors

### MetalLB Not Assigning IPs
**Problem:** LoadBalancer services stuck in "Pending"
**Solution:**
- Check MetalLB pods: `kubectl -n metallb-system get pods`
- Check IPAddressPools: `kubectl -n metallb-system get ipaddresspools -o yaml`
- Check L2Advertisements: `kubectl -n metallb-system get l2advertisements -o yaml`
- Verify VLAN interfaces exist: `ip link show enp197s0.4 enp197s0.8`

### DNS Not Working
**Problem:** DNS queries to 192.168.4.53 fail
**Solution:**
- Check AdGuard pod: `kubectl -n adguard get pods`
- Check service: `kubectl -n adguard get svc`
- Verify LoadBalancer IP assigned: `kubectl -n adguard get svc adguard-home-dns`
- Test from host: `dig @192.168.4.53 google.com`

### Home Assistant Unreachable
**Problem:** Cannot access Home Assistant after VM migration
**Solution:**
- Check VM is running: `virsh list --all`
- Check VM network: `virsh domiflist home-assistant`
- Verify bridge64 exists: `brctl show`
- Check VM IP: Login to VM console and verify 192.168.64.2
- Test connectivity: `ping 192.168.64.2` from N5 host

---

**Last Updated:** 2025-11-01
**Next Action:** Begin Phase 1 - Configuration Updates
