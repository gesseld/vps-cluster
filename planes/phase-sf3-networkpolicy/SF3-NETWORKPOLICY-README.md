# SF-3: NetworkPolicy Default-Deny Applied

## Objective
Enforce zero-trust boundary before any workload can communicate by applying default-deny NetworkPolicies to all foundation namespaces.

## Sub-tasks
1. Apply default-deny policy to each foundation namespace
2. Create explicit allow rules for known dependencies (document in interface matrix)
3. Test isolation: attempt cross-namespace pod-to-pod connection (should fail)
4. Document egress restrictions per plane

## Deliverables
- `shared/network-policies/default-deny.yaml` - Template for default-deny policies
- `shared/network-policies/interface-matrix.yaml` - Reference document for allowed connections
- `shared/network-policies/allow-policies/` - Directory with explicit allow policies
- Applied NetworkPolicies in all foundation namespaces

## Foundation Namespaces
- `control-plane` - Management and control services
- `data-plane` - Application data services
- `observability` - Monitoring and logging
- `security` - Security scanning and compliance
- `network` - Network services and ingress
- `storage` - Storage services

## Scripts

### 1. Pre-deployment Check Script
**File:** `sf3-networkpolicy-precheck.sh`

**Purpose:** Ensures all prerequisites are met before deploying network policies

**Checks:**
- Kubernetes cluster connectivity
- CNI NetworkPolicy support
- Foundation namespaces exist
- Existing NetworkPolicies (potential conflicts)
- Essential services for interface matrix
- RBAC from previous phase (SF-2)

**Usage:**
```bash
./sf3-networkpolicy-precheck.sh
```

### 2. Deployment Script
**File:** `sf3-networkpolicy-deploy.sh`

**Purpose:** Implements and deploys all NetworkPolicy tasks

**Actions:**
1. Creates shared/network-policies directory
2. Creates default-deny.yaml template
3. Applies default-deny to all foundation namespaces
4. Creates interface-matrix.yaml reference
5. Creates and applies explicit allow policies:
   - DNS allow (essential for all namespaces)
   - Control plane to data plane allow
   - Data plane to storage allow
   - HTTPS egress allow
6. Tests isolation with test namespace
7. Provides deployment summary

**Usage:**
```bash
./sf3-networkpolicy-deploy.sh
```

### 3. Validation Script
**File:** `sf3-networkpolicy-validate.sh`

**Purpose:** Validates all tasks and deliverables

**Validations:**
1. Deliverables exist (files created)
2. NetworkPolicies deployed to all namespaces
3. Isolation testing (zero-trust boundary)
4. Egress restrictions per plane
5. Interface matrix completeness
6. Policy conflicts check

**Usage:**
```bash
./sf3-networkpolicy-validate.sh
```

## Manual Validation Test

To verify isolation is working, run:

```bash
kubectl run test-pod --rm -it --image=curlimages/curl --namespace=control-plane \
  -- curl -m 2 http://postgres.data-plane.svc.cluster.local:5432
```

**Expected Result:** Connection timeout/refused (policy working)

## Interface Matrix

The interface matrix (`shared/network-policies/interface-matrix.yaml`) documents:
- **allowRules**: Explicit allow rules for known dependencies
- **egressRestrictions**: Plane-specific egress restrictions

### Key Allow Rules
1. **DNS Resolution**: All pods → kube-dns (TCP/UDP 53)
2. **Control→Data**: control-plane → PostgreSQL (5432), Redis (6379)
3. **Observability**: All pods → Prometheus (9090), Grafana (3000)
4. **Data→Storage**: data-plane → storage services (9000, 9001)
5. **External HTTPS**: All pods → external HTTPS (443)
6. **NTP**: All pods → external NTP (123 UDP)

## Egress Restrictions Per Plane

| Plane | Allowed Egress | Restrictions |
|-------|----------------|--------------|
| **control-plane** | DNS, PostgreSQL, Redis, Prometheus, Grafana, HTTPS, NTP | All other traffic denied |
| **data-plane** | DNS, storage, Prometheus, HTTPS | No direct external except HTTPS |
| **observability** | DNS, HTTPS, NTP | Limited to monitoring needs |
| **security** | DNS, all services (scanning), HTTPS | Broad internal access for scanning |
| **network** | DNS, HTTPS, NTP | Limited to network services |
| **storage** | DNS, Prometheus, HTTPS | No direct app access |

## Execution Order

1. **Pre-check**: Run `./sf3-networkpolicy-precheck.sh`
2. **Deploy**: Run `./sf3-networkpolicy-deploy.sh`
3. **Validate**: Run `./sf3-networkpolicy-validate.sh`
4. **Manual Test**: Run the curl test command above

## Troubleshooting

### Common Issues

1. **NetworkPolicies not taking effect**
   - Check CNI supports NetworkPolicy (Cilium, Calico, Weave)
   - Verify policies are applied to correct namespace
   - Check policyTypes include both Ingress and Egress

2. **DNS not working**
   - Verify `allow-dns-egress` policy is applied
   - Check kube-dns service exists in kube-system
   - Test with `nslookup kubernetes.default`

3. **External connectivity blocked**
   - Verify `allow-egress-https` policy is applied
   - Check CIDR exceptions don't block needed ranges
   - Test with `curl -I https://google.com`

4. **Inter-namespace communication failing**
   - Verify explicit allow policies exist
   - Check namespaceSelector matches namespace labels
   - Verify port and protocol specifications

### Debug Commands

```bash
# List all NetworkPolicies
kubectl get networkpolicies --all-namespaces

# Describe specific policy
kubectl describe networkpolicy <name> -n <namespace>

# Check pod network status
kubectl get pods -n <namespace> -o wide

# Test connectivity from pod
kubectl exec -it <pod-name> -n <namespace> -- curl <service>
```

## Security Considerations

1. **Principle of Least Privilege**: Only allow necessary connections
2. **Default Deny**: Start with deny-all, add explicit allows
3. **Documentation**: Keep interface matrix updated
4. **Testing**: Regularly test isolation boundaries
5. **Monitoring**: Alert on unexpected connection attempts

## Dependencies

- **SF-2 RBAC**: NetworkPolicy admin roles should be created
- **CNI**: Must support NetworkPolicy API
- **Namespaces**: Foundation namespaces must exist
- **Services**: Documented services should be deployed

## Next Phase

After SF-3 completion, proceed to next security foundation phase or application deployment phases with proper network isolation in place.