# Twingate ICMP (Ping) Support Configuration

## Problem

When running Twingate connectors in Kubernetes with restricted security contexts, ICMP ping fails even though TCP/UDP services work correctly. This occurs because Linux restricts ICMP socket creation based on group ID permissions.

**Symptoms:**
- `ping` to resources returns "100% packet loss"
- TCP/UDP services (HTTP, DNS, etc.) work perfectly
- Error in logs: "Operation not permitted" (if ping attempted in container)

## Root Cause

Linux distributions restrict ICMP Echo socket creation using the `net.ipv4.ping_group_range` sysctl. The default value `1 0` means **no groups** are allowed to create ICMP sockets.

This affects:
- Twingate connectors running with dropped capabilities (`capabilities.drop: ALL`)
- Containers without `CAP_NET_RAW` capability
- Non-root users attempting to ping

## Solution

Configure the kernel's `ping_group_range` sysctl to allow all groups to create ICMP sockets. This is Twingate's officially recommended approach.

### Configuration Steps

**On N5 (Homelab Connector Node):**

```bash
# Check current setting (should show "1 0")
sysctl net.ipv4.ping_group_range

# Configure to allow all groups (0 to max GID)
echo 'net.ipv4.ping_group_range = 0 2147483647' | sudo tee /etc/sysctl.d/99-twingate-icmp.conf

# Apply immediately
sudo sysctl -p /etc/sysctl.d/99-twingate-icmp.conf

# Verify
sysctl net.ipv4.ping_group_range
```

**Expected output:**
```
net.ipv4.ping_group_range = 0 2147483647
```

### Testing

From the PHX cluster (or any Twingate client):

```bash
# Should now succeed
ping -c 3 192.168.4.5

# Expected output:
# 64 bytes from 192.168.4.5: icmp_seq=1 ttl=255 time=X ms
# 3 packets transmitted, 3 received, 0% packet loss
```

## Alternative Solutions (NOT Recommended)

### Option 1: NET_RAW Capability
Add `CAP_NET_RAW` to the connector container:

```yaml
securityContext:
  capabilities:
    add:
    - NET_RAW
```

**Why not recommended:**
- More privileged than necessary
- Violates principle of least privilege
- `ping_group_range` sysctl is the official Twingate recommendation

### Option 2: Privileged Container
Run the connector as privileged:

```yaml
securityContext:
  privileged: true
```

**Why not recommended:**
- Grants excessive permissions
- Security risk
- Not necessary when sysctl solution works

## Technical Details

**How it works:**
- Modern kernels support unprivileged ICMP Echo sockets via `SOCK_DGRAM` + `IPPROTO_ICMP`
- The `ping_group_range` sysctl controls which GIDs can use this feature
- Range `0 2147483647` allows all groups (GID 0 through max 32-bit signed int)
- This feature has been available since Linux 3.0 (2011)

**Kubernetes Support:**
- `net.ipv4.ping_group_range` is a "safe" sysctl since Kubernetes v1.18
- Can be set at node level (as we did) or via pod securityContext.sysctls

**Why TCP/UDP still worked:**
- TCP/UDP sockets use `SOCK_STREAM`/`SOCK_DGRAM` with standard ports
- Don't require raw socket access or special capabilities
- Standard socket API works for unprivileged users

## Persistence

The configuration file `/etc/sysctl.d/99-twingate-icmp.conf` ensures the setting persists across reboots.

## References

- [Twingate: Unable to ping a Resource](https://help.twingate.com/hc/en-us/articles/9131363309469)
- [Linux man page: icmp(7)](https://man7.org/linux/man-pages/man7/icmp.7.html)
- [Kubernetes Safe Sysctls](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/)

## Applied To

- **Node:** N5 (`192.168.4.5`)
- **Date:** 2025-11-08
- **Twingate Connector:** `twingate-connector` deployment in `twingate` namespace (homelab cluster)
- **Configuration File:** `/etc/sysctl.d/99-twingate-icmp.conf`

## Verification Checklist

- [x] Sysctl configured on N5
- [x] Ping from PHX to N5 works (192.168.4.5)
- [x] Configuration persists across reboots (via sysctl.d file)
- [x] Twingate connector maintains restricted security context (no additional capabilities needed)
