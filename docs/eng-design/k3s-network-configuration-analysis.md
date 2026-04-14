# K3s Cluster Network Configuration - Comprehensive Analytical Report

## Executive Summary
This document provides a complete technical analysis of the k3s Kubernetes cluster network configuration deployed on Hetzner Cloud. The cluster consists of 3 nodes running Ubuntu 24.04 with Cilium CNI in VXLAN tunnel mode. This report captures all critical configuration details necessary for disaster recovery, troubleshooting, and future maintenance.

---

## 1. Cluster Infrastructure Overview

### 1.1 Server Specifications
| Server Name | Public IPv4 | Public IPv6 | Private IPv4 | Server Type | Location | Status |
|-------------|-------------|-------------|--------------|-------------|----------|---------|
| k3s-cp-1 | 49.12.37.154 | 2a01:4f8:1c17:7cd7::/64 | 10.0.0.2/32 | CPX22 (2 vCPU, 4GB RAM, 80GB SSD) | fsn1-dc14 | Running |
| k3s-w-1 | 49.12.7.192 | 2a01:4f8:c17:418e::/64 | 10.0.0.3/32 | CPX22 (2 vCPU, 4GB RAM, 80GB SSD) | fsn1-dc14 | Running |
| k3s-w-2 | 157.90.157.234 | 2a01:4f8:1c17:5d60::/64 | 10.0.0.4/32 | CPX22 (2 vCPU, 4GB RAM, 80GB SSD) | fsn1-dc14 | Running |

### 1.2 Hetzner Cloud Configuration
- **Account Token**: `oNmhESB6bgWXBdNorJ6p0iCW8ZoTz0eFkjxnz85N1bGgApJapD5Eip4L0GdlTT5V`
- **Private Network**: `k3s-private` (ID: 12097630)
- **Network CIDR**: 10.0.0.0/24
- **Location**: Falkenstein 1 DC Park 1 (fsn1)
- **Image**: Ubuntu 24.04 (ID: 161547269)

### 1.3 SSH Access Configuration
- **Private Key Path**: `C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key`
- **Public Key Path**: `C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key.pub`
- **SSH User**: `root`
- **Key Type**: RSA/ED25519 (as used by Hetzner)

---

## 2. Network Architecture Details

### 2.1 Physical Network Interfaces
**Each node has identical interface configuration:**
```
eth0:      Public interface with /32 address (DHCP)
enp7s0:    Private network interface with /32 address (Hetzner DHCP)
flannel.1: VXLAN tunnel interface (MTU: 1450)
cni0:      Bridge for pod networking
cilium_*:  Cilium internal interfaces
```

### 2.2 Interface Details by Node

#### k3s-cp-1 (10.0.0.2)
```bash
# eth0 - Public
inet 49.12.37.154/32 metric 100 scope global dynamic eth0
MAC: 92:00:07:81:7f:61

# enp7s0 - Private
inet 10.0.0.2/32 metric 100 scope global dynamic enp7s0
MAC: 86:00:00:68:e8:19

# flannel.1 - VXLAN Tunnel
vxlan id 1 local 49.12.37.154 dev eth0 srcport 0 0 dstport 8472
MAC: c2:70:1a:92:56:f7
MTU: 1450
```

#### k3s-w-1 (10.0.0.3)
```bash
# eth0 - Public
inet 49.12.7.192/32 metric 100 scope global dynamic eth0
MAC: (not captured)

# enp7s0 - Private
inet 10.0.0.3/32 metric 100 scope global dynamic enp7s0
MAC: 86:00:00:66:53:84

# flannel.1 - VXLAN Tunnel
vxlan id 1 local 49.12.7.192 dev eth0 srcport 0 0 dstport 8472
```

#### k3s-w-2 (10.0.0.4)
```bash
# eth0 - Public
inet 157.90.157.234/32 metric 100 scope global dynamic eth0
MAC: (not captured)

# enp7s0 - Private
inet 10.0.0.4/32 metric 100 scope global dynamic enp7s0
MAC: 86:00:00:66:53:48

# flannel.1 - VXLAN Tunnel
vxlan id 1 local 157.90.157.234 dev eth0 srcport 0 0 dstport 8472
```

### 2.3 Routing Tables

#### k3s-cp-1 Routing Table:
```
default via 172.31.1.1 dev eth0 proto dhcp src 49.12.37.154 metric 100
10.0.0.0/16 via 10.0.0.1 dev enp7s0 proto dhcp src 10.0.0.2 metric 100
10.0.0.1 dev enp7s0 proto dhcp scope link src 10.0.0.2 metric 100
10.42.0.0/24 dev cni0 proto kernel scope link src 10.42.0.1
10.42.1.0/24 via 10.42.1.0 dev flannel.1 onlink
10.42.6.0/24 via 10.42.6.0 dev flannel.1 onlink
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown
172.18.0.0/16 dev br-db7f56b2c9e9 proto kernel scope link src 172.18.0.1
172.19.0.0/16 dev br-b6acbcf69c00 proto kernel scope link src 172.19.0.1
172.20.0.0/16 dev br-706e91f006d9 proto kernel scope link src 172.20.0.1
172.21.0.0/16 dev br-aa412e139f48 proto kernel scope link src 172.21.0.1
172.22.0.0/16 dev br-88149c71fd14 proto kernel scope link src 172.22.0.1 linkdown
172.31.1.1 dev eth0 proto dhcp scope link src 49.12.37.154 metric 100
185.12.64.1 via 172.31.1.1 dev eth0 proto dhcp src 49.12.37.154 metric 100
185.12.64.2 via 172.31.1.1 dev eth0 proto dhcp src 49.12.37.154 metric 100
```

#### k3s-w-1 Routing Table (partial):
```
10.42.0.0/24 via 10.42.0.0 dev flannel.1 onlink
10.42.1.0/24 dev cni0 proto kernel scope link src 10.42.1.1
10.42.6.0/24 via 10.42.6.0 dev flannel.1 onlink
```

#### k3s-w-2 Routing Table (partial):
```
10.42.0.0/24 via 10.42.0.0 dev flannel.1 onlink
10.42.1.0/24 via 10.42.1.0 dev flannel.1 onlink
10.42.6.0/24 dev cni0 proto kernel scope link src 10.42.6.1
```

### 2.4 Pod Network Allocation
- **Pod CIDR**: 10.42.0.0/16 (subdivided per node)
- **Node Pod CIDRs**:
  - k3s-cp-1: 10.42.0.0/24
  - k3s-w-1: 10.42.1.0/24
  - k3s-w-2: 10.42.6.0/24
- **Service CIDR**: 10.43.0.0/16 (k3s default)
- **Cluster DNS**: 10.43.0.10

---

## 3. Kubernetes Configuration

### 3.1 k3s Installation Details
**Control Plane (k3s-cp-1):**
```bash
# Service file: /etc/systemd/system/k3s.service
ExecStart=/usr/local/bin/k3s server \
    --cluster-init \
    --tls-san 49.12.37.154 \
    --node-ip 10.0.0.2 \
    --node-external-ip 49.12.37.154 \
    --flannel-backend=none \
    --disable-network-policy \
    --disable=traefik \
    --disable=servicelb
```

**Worker Nodes (k3s-w-1, k3s-w-2):**
```bash
# Service file: /etc/systemd/system/k3s-agent.service
ExecStart=/usr/local/bin/k3s agent \
    '--node-ip' \
    '10.0.0.3' \  # or 10.0.0.4 for w-2
    '--node-external-ip' \
    '49.12.7.192' \  # or 157.90.157.234 for w-2
    '--server' 'https://10.0.0.2:6443' \
    '--token' 'K10bc2f24b2dc33a7149833b250ae4ed2250e2da86c4fd9447e37807fcc46ad0ce9::server:b946101db3d92b2e2cf743c6a9b42b80'
```

### 3.2 Cluster Join Token
```
K10bc2f24b2dc33a7149833b250ae4ed2250e2da86c4fd9447e37807fcc46ad0ce9::server:b946101db3d92b2e2cf743c6a9b42b80
```

### 3.3 Current Cluster State
```bash
# kubectl get nodes -o wide
NAME       STATUS   ROLES                AGE    VERSION        INTERNAL-IP   EXTERNAL-IP
k3s-cp-1   Ready    control-plane,etcd   5d7h   v1.35.3+k3s1   10.0.0.2      49.12.37.154
k3s-w-1    Ready    <none>               30m    v1.35.3+k3s1   10.0.0.3      49.12.7.192
k3s-w-2    Ready    <none>               54m    v1.35.3+k3s1   10.0.0.4      157.90.157.234

# Kernel versions: 6.17.0-20-generic (all nodes)
# Container runtime: containerd://2.2.2-k3s1
```

---

## 4. Cilium CNI Configuration

### 4.1 Cilium ConfigMap (cilium-config)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cilium-config
  namespace: kube-system
data:
  # Core networking
  enable-ipv4: "true"
  enable-ipv6: "false"
  enable-ipv4-masquerade: "true"
  
  # Tunnel configuration
  tunnel-protocol: vxlan
  routing-mode: tunnel
  enable-tunnel-big-tcp: "false"
  tunnel-source-port-range: "0-0"
  
  # Native routing (disabled for tunnel mode)
  auto-direct-node-routes: "false"
  ipv4-native-routing-cidr: ""
  
  # BPF configuration
  bpf-lb-acceleration: disabled
  bpf-lb-mode: "snat"
  bpf-map-dynamic-size-ratio: "0.0025"
  
  # Kubernetes integration
  cni-exclusive: "true"
  custom-cni-conf: "false"
  kube-proxy-replacement: "true"
  
  # Datapath
  datapath-mode: veth
  install-no-conntrack-iptables-rules: "true"
  
  # Hubble observability
  enable-hubble: "true"
  hubble-metrics: "drop,tcp,flow,port-distribution,icmp,http"
  hubble-relay-enabled: "true"
  hubble-ui-enabled: "true"
  
  # Health checking
  enable-health-checking: "true"
  enable-health-check-nodeport: "true"
  
  # Miscellaneous
  debug: "false"
  monitor-aggregation: medium
  monitor-aggregation-interval: 5s
  monitor-aggregation-flags: all
  preallocate-bpf-maps: "false"
  sidecar-istio-proxy-image: "cilium/istio_proxy"
```

### 4.2 Cilium Status Output
```bash
KVStore:                Disabled
Kubernetes:             Ok         1.35 (v1.35.3+k3s1) [linux/amd64]
KubeProxyReplacement:   True
Host firewall:          Disabled
Cilium:                 Ok   1.19.2 (v1.19.2-3977f6a1)
IPAM:                   IPv4: 2/254 allocated from 10.42.6.0/24
Routing:                Network: Tunnel [vxlan]   Host: Legacy
Masquerading:           IPTables [IPv4: Enabled, IPv6: Disabled]
Controller Status:      11/12 healthy
Cluster health:         Warning   cilium-health daemon unreachable
```

### 4.3 Cilium Pod Distribution
```bash
# kubectl get pods -n kube-system -l k8s-app=cilium -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP         NODE
cilium-5m2j2   1/1     Running   3          89m   10.0.0.2   k3s-cp-1
cilium-7dvkd   1/1     Running   2          55m   10.0.0.4   k3s-w-2
cilium-flztc   1/1     Running   4          63m   10.0.0.3   k3s-w-1
```

### 4.4 CNI Configuration Files
**Active CNI config (/etc/cni/net.d/05-cilium.conflist):**
```json
{
  "cniVersion": "0.4.0",
  "name": "cilium",
  "plugins": [
    {
      "type": "cilium-cni",
      "enable-debug": false
    }
  ]
}
```

**Removed files (cleaned up):**
- `/etc/cni/net.d/10-flannel.conflist.cilium_bak` (backup from migration)

---

## 5. VXLAN Tunnel Implementation

### 5.1 Tunnel Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    VXLAN Tunnel Details                      │
├─────────────────────────────────────────────────────────────┤
│ Protocol:        VXLAN (Virtual Extensible LAN)             │
│ Tunnel ID:       1                                          │
│ UDP Port:        8472                                       │
│ Underlay:        Public IP over eth0                        │
│ Overlay MTU:     1450                                       │
│ Learning:        Disabled (nolearning)                      │
│ TTL:             Auto                                       │
│ Ageing Time:     300 seconds                                │
│ Checksum:        UDP checksum enabled                       │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Tunnel Endpoints
| Node | VXLAN Local Endpoint | Underlay Interface | Remote Endpoints |
|------|----------------------|-------------------|------------------|
| k3s-cp-1 | 49.12.37.154 | eth0 | 49.12.7.192, 157.90.157.234 |
| k3s-w-1 | 49.12.7.192 | eth0 | 49.12.37.154, 157.90.157.234 |
| k3s-w-2 | 157.90.157.234 | eth0 | 49.12.37.154, 49.12.7.192 |

### 5.3 Traffic Statistics (Sample)
```
flannel.1 interface statistics:
- RX: 2,087,725 bytes, 12,821 packets, 0 errors, 0 dropped
- TX: 3,991,458 bytes, 10,938 packets, 0 errors, 5 dropped
```

---

## 6. Application Deployment Status

### 6.1 Running Applications
```bash
# Key running pods across namespaces:
NAMESPACE          NAME                                                  READY   STATUS
argocd             argocd-applicationset-controller-b97bd9744-lwtnc      1/1     Running
argocd             argocd-dex-server-66b5b9f656-rgfj5                    1/1     Running
argocd             argocd-notifications-controller-85f79d7d68-4vq8w      1/1     Running
argocd             argocd-server-57766c8bcc-jrvwr                        1/1     Running
caddy-system       caddy-669449d6cc-lsw4r                                1/1     Running
cert-manager       cert-manager-7b6c5dbccd-fdxrk                         1/1     Running
cert-manager       cert-manager-cainjector-798668947-vjpdt               1/1     Running
cert-manager       cert-manager-webhook-57d775bfd9-2cv9x                 1/1     Running
control-plane      nats-stateless-7cf6cf9f5d-8cd57                       1/1     Running
control-plane      nats-stateless-7cf6cf9f5d-hm6lp                       1/1     Running
control-plane      temporal-prod-admintools-5cc75dd467-67ccq             1/1     Running
control-plane      temporal-prod-web-59f85598f9-c76rk                    1/1     Running
```

### 6.2 Known Issues
1. **Temporal Components**: Multiple pods in CrashLoopBackOff (pre-existing issue)
2. **Cilium Health**: Warning about cilium-health daemon unreachable
3. **Pod Security**: Strict PodSecurity policies blocking some test pods

---

## 7. Critical Recovery Information

### 7.1 Disaster Recovery Procedures

#### Network Restoration (if flannel.1 interface is deleted):
```bash
# 1. Restore network connectivity via Hetzner Console
# 2. Or reboot nodes to let Cilium recreate interfaces
# 3. Verify VXLAN interface recreation:
ip link add flannel.1 type vxlan id 1 dev eth0 dstport 8472
ip link set flannel.1 up
```

#### Node Recovery:
```bash
# Worker node re-join command:
curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.2:6443 \
  K3S_TOKEN=K10bc2f24b2dc33a7149833b250ae4ed2250e2da86c4fd9447e37807fcc46ad0ce9::server:b946101db3d92b2e2cf743c6a9b42b80 \
  sh -s - agent --node-ip <PRIVATE_IP> --node-external-ip <PUBLIC_IP>
```

### 7.2 Diagnostic Commands
```bash
# Network connectivity tests:
ping -c 4 10.0.0.2  # Test cp-1
ping -c 4 10.0.0.3  # Test w-1
ping -c 4 10.0.0.4  # Test w-2

# VXLAN verification:
ip -d link show flannel.1
nc -zv <node_ip> 8472  # Test VXLAN port

# Cilium diagnostics:
kubectl exec -n kube-system ds/cilium -- cilium status
kubectl get cm cilium-config -n kube-system -o yaml

# Route verification:
ip route show | grep -E "(10.42|flannel)"
```

### 7.3 Configuration Backup Locations
1. **k3s config**: `/etc/rancher/k3s/k3s.yaml`
2. **Cilium config**: ConfigMap `cilium-config` in `kube-system`
3. **Service files**: `/etc/systemd/system/k3s*.service`
4. **CNI config**: `/etc/cni/net.d/05-cilium.conflist`

---

## 8. Security Configuration

### 8.1 Network Policies
- **Flannel backend**: Disabled (`--flannel-backend=none`)
- **NetworkPolicy**: Disabled (`--disable-network-policy`)
- **Cilium Network Policies**: Enabled via Cilium CNI
- **PodSecurity**: Restricted policy enforced

### 8.2 Firewall Requirements
**Required open ports:**
- TCP 6443: Kubernetes API (control plane)
- TCP 10250: Kubelet API
- UDP 8472: Cilium VXLAN (VXLAN over UDP)
- TCP 4240: Cilium health check
- TCP 9090: Hubble metrics (if enabled)

### 8.3 Authentication & Access
- **k3s join token**: Securely stored (see section 3.2)
- **Hetzner API token**: Used for infrastructure management
- **SSH keys**: RSA/ED25519 key pair for node access
- **kubeconfig**: Located at `/etc/rancher/k3s/k3s.yaml` on control plane

---

## 9. Performance Considerations

### 9.1 Network Performance
- **MTU**: 1450 for VXLAN (accounting for 50-byte VXLAN header)
- **Tunnel overhead**: ~50 bytes per packet
- **Throughput impact**: Estimated 3-5% for VXLAN encapsulation
- **Latency**: Additional ~0.1ms for encapsulation/decapsulation

### 9.2 Resource Utilization
- **Cilium memory**: ~100-200MB per node
- **BPF maps**: Dynamically sized based on `bpf-map-dynamic-size-ratio`
- **CPU overhead**: Minimal for dataplane, moderate for control plane

### 9.3 Scaling Considerations
- **Current pod capacity**: ~110 pods per node (theoretical)
- **IPAM limits**: 254 IPs per node pod CIDR (/24)
- **VXLAN scaling**: Supports up to 16M tunnels (VXLAN ID space)

---

## 10. Maintenance Procedures

### 10.1 Regular Maintenance
```bash
# 1. Check cluster health:
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running

# 2. Check Cilium status:
kubectl exec -n kube-system ds/cilium -- cilium status

# 3. Verify network connectivity:
for node in 10.0.0.{2,3,4}; do ping -c 2 $node; done

# 4. Check VXLAN interface:
ip -s link show flannel.1
```

### 10.2 Troubleshooting Flowchart
```
Network Issue Detected
        ↓
1. Verify node status: kubectl get nodes -o wide
        ↓
2. Check pod connectivity: ping between node IPs
        ↓
3. Verify VXLAN interface: ip -d link show flannel.1
        ↓
4. Check Cilium pods: kubectl get pods -n kube-system -l k8s-app=cilium
        ↓
5. Examine Cilium logs: kubectl logs -n kube-system ds/cilium --tail=50
        ↓
6. Verify routes: ip route show | grep -E "(10.42|flannel)"
```

### 10.3 Upgrade Procedures
1. **Cilium upgrade**: Follow Cilium's upgrade guide with Helm
2. **k3s upgrade**: Use `k3s upgrade` command on each node
3. **Kernel upgrade**: Reboot required for kernel updates
4. **Ubuntu upgrade**: LTS to LTS upgrades supported

---

## 11. Environmental Variables & Secrets

### 11.1 Critical Environment Variables
```bash
# k3s installation
export K3S_TOKEN="K10bc2f24b2dc33a7149833b250ae4ed2250e2da86c4fd9447e37807fcc46ad0ce9::server:b946101db3d92b2e2cf743c6a9b42b80"
export K3S_URL="https://10.0.0.2:6443"

# Hetzner CLI
export HCLOUD_TOKEN="oNmhESB6bgWXBdNorJ6p0iCW8ZoTz0eFkjxnz85N1bGgApJapD5Eip4L0GdlTT5V"

# SSH access
export SSH_KEY_PATH="~/hetzner-cli-key"
```

### 11.2 Kubernetes Secrets
- **Service account tokens**: Automatically managed by k3s
- **Docker registry credentials**: Stored in `imagePullSecrets`
- **TLS certificates**: Automatically generated by k3s
- **Let's Encrypt certificates**: Managed by cert-manager

---

## 12. Monitoring & Observability

### 12.1 Built-in Monitoring
- **Cilium Hubble**: Enabled for network flow visibility
- **Kubernetes metrics**: Available via metrics-server
- **Node metrics**: Available via kubelet

### 12.2 Key Metrics to Monitor
1. **VXLAN packet drops**: `ip -s link show flannel.1`
2. **Cilium health**: `cilium status --verbose`
3. **Pod network latency**: Between pods on different nodes
4. **DNS resolution times**: CoreDNS performance

### 12.3 Alerting Thresholds
- **Node NotReady**: > 5 minutes
- **VXLAN packet loss**: > 1%
- **Cilium controller failures**: > 2 unhealthy controllers
- **Pod startup failures**: > 3 consecutive restarts

---

## 13. Backup & Restore Procedures

### 13.1 Critical Data to Backup
1. **k3s configuration**: `/etc/rancher/k3s/`
2. **Cilium ConfigMap**: `kubectl get cm cilium-config -n kube-system -o yaml`
3. **Custom resources**: All CRDs managed by applications
4. **Persistent volumes**: Application data volumes

### 13.2 Backup Commands
```bash
# Backup k3s config
cp -r /etc/rancher/k3s/ /backup/k3s-config-$(date +%Y%m%d)

# Backup Cilium configuration
kubectl get cm cilium-config -n kube-system -o yaml > /backup/cilium-config-$(date +%Y%m%d).yaml

# Backup etcd (if using embedded etcd)
k3s etcd-snapshot save --snapshot-compress
```

### 13.3 Restore Procedures
```bash
# Restore from etcd snapshot
k3s server \
  --cluster-init \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-name>

# Restore Cilium config
kubectl apply -f /backup/cilium-config.yaml
```

---

## 14. Known Limitations & Workarounds

### 14.1 Current Limitations
1. **Hetzner private network**: L3-only, no L2 adjacency
2. **VXLAN overhead**: Additional encapsulation overhead
3. **MTU considerations**: Must account for VXLAN header
4. **IPv6**: Disabled in current configuration

### 14.2 Workarounds Implemented
1. **VXLAN tunnel mode**: Required due to Hetzner's L3-only network
2. **Public IP endpoints**: VXLAN uses public IPs for tunnel endpoints
3. **Reduced MTU**: 1450 to accommodate VXLAN headers
4. **Static node IPs**: Configured via k3s agent arguments

### 14.3 Future Improvements
1. **Native routing**: Possible with Hetzner Floating IP + Route API
2. **IPv6 enablement**: When application support improves
3. **Network policies**: Enable Cilium network policies
4. **Service mesh**: Consider Linkerd or Istio integration

---

## 15. Contact Information & Escalation

### 15.1 Primary Contacts
- **Infrastructure Owner**: Daniel (SSH key holder)
- **Hetzner Support**: https://console.hetzner.cloud
- **k3s Community**: https://github.com/k3s-io/k3s
- **Cilium Community**: https://cilium.io/slack

### 15.2 Documentation References
1. **k3s documentation**: https://docs.k3s.io/
2. **Cilium documentation**: https://docs.cilium.io/
3. **Hetzner Cloud docs**: https://docs.hetzner.com/
4. **Ubuntu 24.04 docs**: https://ubuntu.com/server/docs

### 15.3 Emergency Access
1. **Hetzner Console**: Web-based KVM access
2. **Rescue mode**: Available via Hetzner API
3. **Serial console**: Available for debugging
4. **VNC access**: Via Hetzner web console

---

## 16. Appendices

### 16.1 Command Reference Cheat Sheet
```bash
# Cluster management
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running

# Network diagnostics
ip -d link show flannel.1
ip route show | grep -E "(10.42|flannel)"
nc -zv <ip> 8472

# Cilium operations
kubectl exec -n kube-system ds/cilium -- cilium status
kubectl logs -n kube-system ds/cilium --tail=100

# Service management
systemctl status k3s
systemctl status k3s-agent
journalctl -u k3s -f
```

### 16.2 Configuration File Templates
**k3s agent service template:**
```ini
[Unit]
Description=Lightweight Kubernetes
After=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
ExecStart=/usr/local/bin/k3s agent \
    '--node-ip' 'PRIVATE_IP' \
    '--node-external-ip' 'PUBLIC_IP' \
    '--server' 'https://10.0.0.2:6443' \
    '--token' 'K3S_JOIN_TOKEN'
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

### 16.3 IP Address Reference Table
| Resource | k3s-cp-1 | k3s-w-1 | k3s-w-2 |
|----------|----------|----------|----------|
| Public IP | 49.12.37.154 | 49.12.7.192 | 157.90.157.234 |
| Private IP | 10.0.0.2 | 10.0.0.3 | 10.0.0.4 |
| Pod CIDR | 10.42.0.0/24 | 10.42.1.0/24 | 10.42.6.0/24 |
| VXLAN Local | 49.12.37.154 | 49.12.7.192 | 157.90.157.234 |

---

**Document Version**: 1.0  
**Last Updated**: 2026-04-13  
**Author**: Infrastructure Team  
**Status**: Current Production Configuration  

*This document should be updated whenever network configuration changes are made. Store securely as it contains sensitive authentication information.*