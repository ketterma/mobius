# Home Assistant OIDC - MetalLB Hairpin Issue ✅ RESOLVED

## Solution: Macvlan Interface for MetalLB L2 Announcements

**Status:** ✅ **WORKING**

Created `metallb0` macvlan interface attached to bridge0 with unique MAC address. This solves the hairpin routing problem where VMs on the same bridge couldn't reach LoadBalancer IPs.

### Implementation

```bash
# Create macvlan interface (already done, needs persistence)
ip link add link bridge0 name metallb0 type macvlan mode bridge
ip link set metallb0 up
```

```yaml
# MetalLB L2Advertisement configuration
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - homelab-pool
  interfaces:
  - metallb0  # Macvlan on bridge0 with unique MAC
  nodeSelectors:
  - matchLabels:
      kubernetes.io/hostname: n5
```

### Why It Works

**Problem:** When MetalLB announced on bridge0 directly, it used bridge0's MAC address (22:c4:a4:e0:6d:fc). VMs sending packets to LoadBalancer IPs with this destination MAC caused the bridge to think packets were for itself (192.168.8.246), not for forwarding.

**Solution:** Macvlan interface creates a virtual interface with **unique MAC address** (f2:5a:5f:84:40:e8) that's still part of bridge0's L2 domain. Now:
- Network clients via eno1 → bridge0 → can reach metallb0's MAC
- VMs via vnet1 → bridge0 → can reach metallb0's MAC (different MAC, no conflict)
- LoadBalancer IPs use metallb0's unique MAC, not bridge0's MAC

### Verification

```bash
# From VM (Home Assistant at 192.168.8.10):
ip neigh show
# Shows:
# 192.168.8.53 dev enp1s0 lladdr f2:5a:5f:84:40:e8 REACHABLE ✅
# 192.168.8.50 dev enp1s0 lladdr f2:5a:5f:84:40:e8 STALE ✅

# From network clients:
dig @192.168.8.53 google.com  # ✅ Works
```

### Remaining Task

Make metallb0 interface persistent across reboots:

```bash
# Systemd service already created at /etc/systemd/system/metallb-macvlan.service
# Already enabled: systemctl enable metallb-macvlan.service
# Will auto-create metallb0 on boot before k0s starts
```

## What Was Changed

### Permanent (via Git):
1. ✅ Switched MetalLB from BGP to L2 mode
2. ✅ Removed BGPPeer and BGPAdvertisement resources
3. ✅ Created L2Advertisement with metallb0 interface
4. ✅ Configured L2Advertisement in `k8s/clusters/lab/infrastructure-config/metallb-config.yaml`

### Manual (on N5 host):
1. ✅ Removed BGP config from UDM Pro
2. ✅ Created metallb0 macvlan interface
3. ✅ Created systemd service for metallb0 persistence
4. ✅ Applied L2Advertisement directly to test (Flux will sync later)

### Verified Working:
- ✅ Network clients can reach DNS (192.168.8.53)
- ✅ Network clients can reach Traefik (192.168.8.50)
- ✅ VM has learned correct MAC addresses (f2:5a:5f:84:40:e8) via ARP
- ✅ VM ARP entries marked REACHABLE (traffic flowing)
- ✅ MetalLB speaker logs show ARP/NDP responders created for metallb0

## Alternative Solutions Explored (Not Used)

### Option 2: Move VM to Different VLAN
- Would work but requires UDM Pro VLAN configuration
- More complex network architecture
- Not needed now that macvlan solution works

### Option 5: iptables DNAT Workaround
- Would work but is a manual workaround
- Fragile (breaks if pod IPs change)
- Not needed now that macvlan solution works

## Root Cause Analysis (For Reference)

BGP mode was fundamentally incompatible with same-subnet clients. BGP expects service IPs in different subnet from clients, requiring routing through gateway. Our setup had VM (192.168.8.10), LoadBalancer IPs (192.168.8.50-79), and bridge0 (192.168.8.246) all in same /24 subnet.

Initial L2 mode attempts failed because:
- **eno1**: No IP address (bridge slave), MetalLB can't announce
- **enp197s0**: Works for network but not VMs (different L2 domain from bridge0)
- **bridge0 directly**: VM packets had dest MAC same as bridge's own MAC (conflict)
- **metallb0 macvlan**: ✅ Unique MAC, same L2 domain, works for both network and VMs
