# Home Assistant OIDC - MetalLB Hairpin Issue

## Root Cause Analysis
BGP mode is fundamentally incompatible with same-subnet clients according to MetalLB documentation. BGP mode expects service IPs to be in a **different subnet** from nodes/clients, requiring traffic to route through the gateway. Our setup has the VM (192.168.8.10), LoadBalancer IPs (192.168.8.50-79), and bridge0 (192.168.8.246) all in the same /24 subnet, causing hairpin routing issues where ICMP works but TCP/UDP fails.

Bridge hairpin mode is already enabled (vnet1 hairpin_mode=1), br_netfilter is loaded, and rp_filter is set to loose mode (2), but these don't solve the fundamental BGP same-subnet problem.

## Solution Options

### Option 1: Switch to L2 Mode with Interface Restrictions ⭐ RECOMMENDED
**Status:** Ready to implement

Switch MetalLB from BGP to L2 mode, which is designed for same-subnet clients. Use the `interfaces` field to restrict ARP announcements to the bridge interface only.

**Implementation:**
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - homelab-pool
  interfaces:
    - eno1  # Only announce from bridge interface
  nodeSelectors:
    - matchLabels:
        kubernetes.io/hostname: n5
```

**Steps:**
1. Create L2Advertisement resource
2. Delete BGPAdvertisement and BGPPeer resources
3. Remove BGP config from UDM Pro
4. Test VM connectivity

**Pros:**
- L2 mode designed for same-subnet clients
- Uses ARP (works with bridge hairpin mode already enabled)
- No network architecture changes needed
- No router configuration required

**Cons:**
- Single-node bottleneck (all traffic to one node)
- Slower failover than BGP

### Option 2: Move VM to Different VLAN (Keep BGP Mode)
**Status:** More complex alternative

Separate the VM into a different subnet (e.g., VLAN 10 at 192.168.10.0/24) so traffic genuinely routes through UDM Pro's BGP table.

**Implementation:**
```bash
# On N5 host
ip link add link eno1 name eno1.10 type vlan id 10
ip addr add 192.168.10.246/24 dev eno1.10
brctl addbr br-vlan10
brctl addif br-vlan10 eno1.10

# Update VM to use br-vlan10
virsh edit HomeAssistant
```

**UDM Pro:**
- Create VLAN 10 network (192.168.10.0/24)
- Keep BGP peering for 192.168.8.50-79 advertisements
- VM routes 192.168.10.10 → 192.168.10.1 → 192.168.8.246 → LoadBalancer

**Pros:**
- BGP mode works as designed (different subnets)
- Proper load balancing across nodes
- Fast failover

**Cons:**
- Requires UDM Pro VLAN configuration
- More complex network architecture
- Additional bridge management

### Option 5: iptables DNAT Workaround (Last Resort)
**Status:** Manual fallback if L2 mode fails

Add explicit DNAT rules on N5 host to redirect bridge0 traffic directly to pod IPs, bypassing MetalLB entirely.

**Implementation:**
```bash
# Redirect DNS traffic from bridge0 to AdGuard pod
iptables -t nat -A PREROUTING -i bridge0 -d 192.168.8.53 -p tcp --dport 53 \
  -j DNAT --to-destination 10.244.0.83:53
iptables -t nat -A PREROUTING -i bridge0 -d 192.168.8.53 -p udp --dport 53 \
  -j DNAT --to-destination 10.244.0.83:53

# Masquerade return traffic
iptables -t nat -A POSTROUTING -s 192.168.8.0/24 -d 10.244.0.0/16 -j MASQUERADE
```

**Pros:**
- Direct kernel-level routing
- Works with any MetalLB mode

**Cons:**
- Manual iptables management (fragile)
- Pod IP changes break rules
- Conflicts with MetalLB rules
- Not persistent without additional scripting

## Current State
- Bridge hairpin: ✅ Enabled (vnet1 hairpin_mode=1)
- br_netfilter: ✅ Loaded and configured
- rp_filter: ✅ Loose mode (2)
- BGP peering: ✅ Established (N5 ASN 65100 ↔ UDM Pro ASN 65001)
- Routes advertised: ✅ 192.168.8.50/32, 192.168.8.53/32 via 192.168.8.246
- External access: ✅ Works from outside network
- Same-network access: ❌ ICMP only, TCP/UDP fails (BGP mode incompatibility)
- HA OIDC: ❌ Still broken, DNS unreachable from VM
