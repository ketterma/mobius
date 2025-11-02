# Home Assistant OS Virtual Machine

**Last Updated:** 2025-11-01

## VM Configuration

### Hardware Resources
- **vCPU:** 4 cores (host-passthrough)
- **RAM:** 16GB
- **Storage:** ZFS zvol `/dev/zvol/vms/HomeAssistant`
  - Pool: `vms/HomeAssistant`
  - Allocated: 157GB
  - Used: ~26.6GB
  - Snapshots:
    - `pre-vlan-migration-2025-11-01` (378MB)
    - `pre-bridge64-migration-2025-11-01-1558` (0B)

### Platform Details
- **Hypervisor:** KVM/QEMU via libvirt
- **Host:** N5 (192.168.4.5)
- **Machine Type:** pc-q35-8.2
- **Firmware:** UEFI (OVMF)
- **CPU Mode:** host-passthrough (no restrictions)

### Network Configuration
- **Bridge:** `bridge64` (IoT VLAN 64)
- **Interface:** virtio-net-pci
- **MAC Address:** `00:a0:98:5a:52:07`
- **Host Interface:** `vnet1` → `bridge64`

### Network Settings (In-VM)
- **Interface:** `enp1s0`
- **IP Address:** `192.168.64.2/20`
- **Gateway:** `192.168.64.1` (N5 bridge64)
- **DNS:** `192.168.4.53` (AdGuard Home)
- **Method:** Static (configured via Home Assistant CLI)

### USB Passthrough
Two USB devices are passed through to the VM:
1. **Device 1:** Vendor `0x303a`, Product `0x4001` (Bus 3, Device 2)
2. **Device 2:** Vendor `0x10c4`, Product `0xea60` (Bus 3, Device 3)

These are likely Zigbee/Z-Wave coordinators for smart home control.

## Home Assistant Configuration

### HTTP/Proxy Settings
File: `/config/configuration.yaml`

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.64.0/20     # IoT VLAN (local network)
    - 10.244.0.0/16       # Kubernetes pod network (Traefik)
    - 192.168.64.1        # N5 bridge64 gateway
```

**Why these proxies are trusted:**
- **192.168.64.0/20** - Local IoT VLAN for direct access
- **10.244.0.0/16** - Kubernetes pods (Traefik runs in this network)
- **192.168.64.1** - N5's bridge64 interface routes traffic from Traefik to the VM

### Access Methods

#### 1. Direct HTTP Access
- **URL:** `http://192.168.64.2:8123`
- **Use Case:** Local IoT VLAN access, troubleshooting
- **Certificate:** None (plain HTTP)

#### 2. HTTPS via Traefik (Recommended)
- **URL:** `https://home.jax-lab.dev`
- **Path:** Client → DNS (192.168.4.53) → Traefik (192.168.8.50:443) → ExternalName Service → VM (192.168.64.2:8123)
- **Certificate:** Let's Encrypt (DNS-01 challenge via Cloudflare)
- **Internal/External:** Split-horizon DNS routes internal clients to 192.168.8.50

#### 3. SSH Access (Root)
- **Command:** `ssh root@192.168.64.2`
- **Purpose:** Home Assistant CLI, configuration editing
- **Available Commands:**
  - `ha core restart` - Restart Home Assistant Core
  - `ha core logs` - View logs
  - `ha network info` - View network configuration
  - `ha network update` - Modify network settings

## Kubernetes Integration

### ExternalName Service
**Namespace:** `traefik`
**Service:** `homeassistant`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: homeassistant
  namespace: traefik
spec:
  type: ExternalName
  externalName: 192.168.64.2
  ports:
  - port: 8123
    targetPort: 8123
    protocol: TCP
```

This allows Kubernetes Traefik to route HTTPS traffic to the VM on VLAN 64.

### Traefik IngressRoute
The IngressRoute in the `traefik` namespace forwards `https://home.jax-lab.dev` to the ExternalName service, which resolves to `192.168.64.2:8123`.

## Management Tasks

### Restart Home Assistant
```bash
ssh root@192.168.64.2 "ha core restart"
```

### Update Network Configuration
```bash
ssh root@192.168.64.2
ha network update enp1s0 --ipv4-method static --ipv4-address 192.168.64.2/20 --ipv4-gateway 192.168.64.1 --ipv4-nameserver 192.168.4.53
```

### Create ZFS Snapshot
```bash
ssh jax@192.168.4.5
sudo zfs snapshot vms/HomeAssistant@description-$(date +%Y-%m-%d)
```

### Rollback to Snapshot
```bash
ssh jax@192.168.4.5
sudo virsh destroy HomeAssistant
sudo zfs rollback vms/HomeAssistant@snapshot-name
sudo virsh start HomeAssistant
```

### View VM Console (VNC)
1. **On local machine:**
   ```bash
   ssh -L 5901:localhost:5900 jax@192.168.4.5
   ```
2. **Connect VNC client to:** `vnc://localhost:5901`
3. **Password:** `homelab` (set in VM XML)

### VM Definition Files
- **Backup XML:** `bootstrap/homeassistant-vm-config-backup.xml` (before bridge64 migration)
- **Current XML:** `bootstrap/homeassistant-vm.xml` (active configuration)

## Network Routing Path

### Internal Access (LAN → Home Assistant)
```
User Device (192.168.x.x)
  ↓ DNS Query: home.jax-lab.dev
AdGuard Home (192.168.4.53)
  ↓ DNS Rewrite: 192.168.8.50
Traefik LoadBalancer (192.168.8.50:443)
  ↓ HTTPS/TLS termination, IngressRoute lookup
Traefik Pod (10.244.0.x:8443)
  ↓ ExternalName Service resolution
N5 Routing (192.168.64.1)
  ↓ bridge64 → vnet1
Home Assistant VM (192.168.64.2:8123)
```

### Why Traffic Appears from 192.168.64.1
When Traefik (running in pod network 10.244.0.0/16) sends traffic to an external IP (192.168.64.2), the Linux kernel routes it through the appropriate interface. Since the destination is on bridge64, the traffic is **source-NAT'd** to the bridge's IP (192.168.64.1) before reaching the VM. This is why Home Assistant sees requests from 192.168.64.1 instead of the pod IP.

## Security Considerations

### Trusted Proxy Configuration
The `trusted_proxies` setting is critical for security:
- Home Assistant checks the `X-Forwarded-For` header to determine the real client IP
- Only proxies in the trusted list can set this header
- This prevents IP spoofing attacks where malicious clients claim to be from trusted IPs

### Network Isolation
- VM is on VLAN 64 (IoT), isolated from infrastructure VLAN (VLAN 1)
- Only accessible via:
  1. Direct connection from VLAN 64 devices
  2. Routed connection through N5 (gateway at 192.168.64.1)
  3. Kubernetes ExternalName service (for Traefik routing)

## Troubleshooting

### VM Not Accessible
1. Check VM is running: `ssh jax@192.168.4.5 "sudo virsh list"`
2. Check network interface: `ssh jax@192.168.4.5 "bridge link show master bridge64 | grep vnet"`
3. Check VM IP: `ping 192.168.64.2`
4. Check from N5: `ssh jax@192.168.4.5 "curl -s http://192.168.64.2:8123 | head"`

### HTTPS 400 Error
Check Home Assistant logs for "untrusted proxy" errors:
```bash
ssh root@192.168.64.2 "ha core logs | grep -i proxy"
```

If you see errors about untrusted proxy from a specific IP, add it to `trusted_proxies` in `/config/configuration.yaml`.

### VNC Connection Issues
If VNC password authentication fails:
1. Check VNC is configured: `ssh jax@192.168.4.5 "sudo virsh vncdisplay HomeAssistant"`
2. Verify password in XML: `bootstrap/homeassistant-vm.xml` (look for `passwd` attribute)
3. Reconnect SSH tunnel: `ssh -L 5901:localhost:5900 jax@192.168.4.5`
