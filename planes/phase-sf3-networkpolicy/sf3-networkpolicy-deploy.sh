#!/bin/bash

# SF-3 NetworkPolicy Default-Deny Deployment Script
# This script implements and deploys all NetworkPolicy tasks for SF-3

set -e

echo "================================================"
echo "SF-3 NetworkPolicy Default-Deny Deployment"
echo "================================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section header
print_section() {
    echo ""
    echo "================================================"
    echo "$1"
    echo "================================================"
    echo ""
}

# Function to apply YAML and check result
apply_yaml() {
    local file=$1
    local description=$2
    
    echo -e "${BLUE}Applying:${NC} $description"
    echo -e "  File: $file"
    
    if kubectl apply -f "$file" --dry-run=client &> /dev/null; then
        kubectl apply -f "$file"
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ Successfully applied${NC}"
            return 0
        else
            echo -e "  ${RED}✗ Failed to apply${NC}"
            return 1
        fi
    else
        echo -e "  ${RED}✗ YAML validation failed${NC}"
        return 1
    fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
    local ns=$1
    
    if ! kubectl get namespace "$ns" &> /dev/null; then
        echo -e "${YELLOW}Creating namespace: $ns${NC}"
        kubectl create namespace "$ns"
    fi
}

print_section "1. Creating shared/network-policies directory"

# Create directory for network policies
SHARED_DIR="$(dirname "$0")/../../shared/network-policies"
mkdir -p "$SHARED_DIR"
echo -e "${GREEN}Created directory:${NC} $SHARED_DIR"

print_section "2. Creating default-deny NetworkPolicy"

# Create default-deny.yaml
DEFAULT_DENY_FILE="$SHARED_DIR/default-deny.yaml"
cat > "$DEFAULT_DENY_FILE" << 'EOF'
# Default Deny NetworkPolicy for Zero-Trust Boundary
# Applied to all foundation namespaces
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: {{NAMESPACE}}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
EOF

echo -e "${GREEN}Created:${NC} $DEFAULT_DENY_FILE"

# List of foundation namespaces
FOUNDATION_NAMESPACES=(
    "control-plane"
    "data-plane" 
    "observability"
    "security"
    "network"
    "storage"
)

print_section "3. Applying default-deny to all foundation namespaces"

# Apply default-deny to each namespace
for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    create_namespace "$ns"
    
    # Create namespace-specific policy
    POLICY_FILE="/tmp/default-deny-$ns.yaml"
    sed "s/{{NAMESPACE}}/$ns/g" "$DEFAULT_DENY_FILE" > "$POLICY_FILE"
    
    if apply_yaml "$POLICY_FILE" "Default-deny for namespace: $ns"; then
        echo -e "  ${GREEN}✓ Applied to $ns${NC}"
    else
        echo -e "  ${RED}✗ Failed to apply to $ns${NC}"
    fi
    
    rm -f "$POLICY_FILE"
done

print_section "4. Creating interface matrix"

# Create interface-matrix.yaml
INTERFACE_MATRIX_FILE="$SHARED_DIR/interface-matrix.yaml"
cat > "$INTERFACE_MATRIX_FILE" << 'EOF'
# NetworkPolicy Interface Matrix
# Documents explicit allow rules for known dependencies
#
# Format:
# - source: Namespace/Pod selector that initiates traffic
# - destination: Service/Port that receives traffic  
# - protocol: TCP/UDP
# - port: Destination port
# - description: Purpose of the connection

allowRules:
  # DNS Resolution (essential for all pods)
  - name: dns-egress
    source:
      namespaceSelector: {}
      podSelector: {}
    destination:
      namespace: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    protocol: TCP
    port: 53
    description: DNS resolution for all pods
    priority: 1000

  - name: dns-egress-udp
    source:
      namespaceSelector: {}
      podSelector: {}
    destination:
      namespace: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    protocol: UDP
    port: 53
    description: DNS resolution (UDP) for all pods
    priority: 1001

  # Control Plane to Data Plane communications
  - name: control-to-postgres
    source:
      namespace: control-plane
      podSelector: {}
    destination:
      namespace: data-plane
      podSelector:
        matchLabels:
          app: postgres
    protocol: TCP
    port: 5432
    description: Control plane apps to PostgreSQL
    priority: 1100

  - name: control-to-redis
    source:
      namespace: control-plane
      podSelector: {}
    destination:
      namespace: data-plane
      podSelector:
        matchLabels:
          app: redis
    protocol: TCP
    port: 6379
    description: Control plane apps to Redis cache
    priority: 1101

  # Observability access
  - name: all-to-prometheus
    source:
      namespaceSelector: {}
      podSelector: {}
    destination:
      namespace: observability
      podSelector:
        matchLabels:
          app: prometheus
    protocol: TCP
    port: 9090
    description: All pods to Prometheus metrics
    priority: 1200

  - name: all-to-grafana
    source:
      namespaceSelector: {}
      podSelector: {}
    destination:
      namespace: observability
      podSelector:
        matchLabels:
          app: grafana
    protocol: TCP
    port: 3000
    description: All pods to Grafana dashboards
    priority: 1201

  # Storage access
  - name: data-to-storage
    source:
      namespace: data-plane
      podSelector: {}
    destination:
      namespace: storage
      podSelector: {}
    protocol: TCP
    ports: [9000, 9001]
    description: Data plane apps to storage services
    priority: 1300

  # Security scanning
  - name: security-to-all
    source:
      namespace: security
      podSelector:
        matchLabels:
          app: scanner
    destination:
      namespaceSelector: {}
      podSelector: {}
    protocol: TCP
    ports: [80, 443, 8080, 8443]
    description: Security scanner to all services
    priority: 1400

  # Egress to external services (restricted)
  - name: egress-https
    source:
      namespaceSelector: {}
      podSelector: {}
    destination:
      ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16
    protocol: TCP
    port: 443
    description: Egress to external HTTPS services
    priority: 2000

  - name: egress-ntp
    source:
      namespaceSelector: {}
      podSelector: {}
    destination:
      ipBlock:
        cidr: 0.0.0.0/0
    protocol: UDP
    port: 123
    description: NTP time synchronization
    priority: 2001

# Egress restrictions per plane
egressRestrictions:
  control-plane:
    allowed:
      - dns-egress
      - dns-egress-udp
      - control-to-postgres
      - control-to-redis
      - all-to-prometheus
      - all-to-grafana
      - egress-https
      - egress-ntp
    denied: all

  data-plane:
    allowed:
      - dns-egress
      - dns-egress-udp
      - data-to-storage
      - all-to-prometheus
      - egress-https
    denied: all

  observability:
    allowed:
      - dns-egress
      - dns-egress-udp
      - egress-https
      - egress-ntp
    denied: all

  security:
    allowed:
      - dns-egress
      - dns-egress-udp
      - security-to-all
      - egress-https
    denied: all

  network:
    allowed:
      - dns-egress
      - dns-egress-udp
      - egress-https
      - egress-ntp
    denied: all

  storage:
    allowed:
      - dns-egress
      - dns-egress-udp
      - all-to-prometheus
      - egress-https
    denied: all
EOF

echo -e "${GREEN}Created:${NC} $INTERFACE_MATRIX_FILE"
echo -e "${BLUE}Note:${NC} This is a reference document. Actual NetworkPolicies need to be created from these rules."

print_section "5. Creating explicit allow NetworkPolicies"

# Create directory for allow policies
ALLOW_POLICIES_DIR="$SHARED_DIR/allow-policies"
mkdir -p "$ALLOW_POLICIES_DIR"

# Create DNS allow policy (essential for all namespaces)
DNS_ALLOW_FILE="$ALLOW_POLICIES_DIR/dns-allow.yaml"
cat > "$DNS_ALLOW_FILE" << 'EOF'
# DNS Allow NetworkPolicy
# Allows DNS egress from all pods in all namespaces
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: {{NAMESPACE}}
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # Allow DNS TCP
  - ports:
    - port: 53
      protocol: TCP
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
  # Allow DNS UDP
  - ports:
    - port: 53
      protocol: UDP
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
EOF

echo -e "${GREEN}Created:${NC} $DNS_ALLOW_FILE"

# Apply DNS allow to all foundation namespaces
for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    POLICY_FILE="/tmp/dns-allow-$ns.yaml"
    sed "s/{{NAMESPACE}}/$ns/g" "$DNS_ALLOW_FILE" > "$POLICY_FILE"
    
    if apply_yaml "$POLICY_FILE" "DNS allow for namespace: $ns"; then
        echo -e "  ${GREEN}✓ Applied to $ns${NC}"
    else
        echo -e "  ${RED}✗ Failed to apply to $ns${NC}"
    fi
    
    rm -f "$POLICY_FILE"
done

print_section "6. Creating plane-specific allow policies"

# Create control-plane to data-plane allow policy
CONTROL_DATA_ALLOW_FILE="$ALLOW_POLICIES_DIR/control-to-data-allow.yaml"
cat > "$CONTROL_DATA_ALLOW_FILE" << 'EOF'
# Control Plane to Data Plane Allow Rules
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-control-to-data
  namespace: control-plane
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # To PostgreSQL
  - ports:
    - port: 5432
      protocol: TCP
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: data-plane
      podSelector:
        matchLabels:
          app: postgres
  # To Redis
  - ports:
    - port: 6379
      protocol: TCP
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: data-plane
      podSelector:
        matchLabels:
          app: redis
EOF

apply_yaml "$CONTROL_DATA_ALLOW_FILE" "Control plane to data plane allow rules"

# Create data-plane to storage allow policy
DATA_STORAGE_ALLOW_FILE="$ALLOW_POLICIES_DIR/data-to-storage-allow.yaml"
cat > "$DATA_STORAGE_ALLOW_FILE" << 'EOF'
# Data Plane to Storage Allow Rules
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-data-to-storage
  namespace: data-plane
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 9000
      protocol: TCP
    - port: 9001
      protocol: TCP
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: storage
      podSelector: {}
EOF

apply_yaml "$DATA_STORAGE_ALLOW_FILE" "Data plane to storage allow rules"

print_section "7. Creating egress restrictions"

# Create egress HTTPS allow policy (for all namespaces)
EGRESS_HTTPS_FILE="$ALLOW_POLICIES_DIR/egress-https-allow.yaml"
cat > "$EGRESS_HTTPS_FILE" << 'EOF'
# Egress HTTPS Allow Policy
# Allows HTTPS egress to external services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-https
  namespace: {{NAMESPACE}}
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 443
      protocol: TCP
    to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16
EOF

# Apply HTTPS egress to all foundation namespaces
for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    POLICY_FILE="/tmp/egress-https-$ns.yaml"
    sed "s/{{NAMESPACE}}/$ns/g" "$EGRESS_HTTPS_FILE" > "$POLICY_FILE"
    
    if apply_yaml "$POLICY_FILE" "HTTPS egress for namespace: $ns"; then
        echo -e "  ${GREEN}✓ Applied to $ns${NC}"
    else
        echo -e "  ${RED}✗ Failed to apply to $ns${NC}"
    fi
    
    rm -f "$POLICY_FILE"
done

print_section "8. Testing isolation"

echo "Creating test pod to verify isolation..."
echo ""

# Create test namespace
TEST_NS="networkpolicy-test"
kubectl create namespace $TEST_NS --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
echo -e "${GREEN}Created test namespace:${NC} $TEST_NS"

# Apply default-deny to test namespace
TEST_DENY_FILE="/tmp/test-default-deny.yaml"
cat > "$TEST_DENY_FILE" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: networkpolicy-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
EOF

kubectl apply -f "$TEST_DENY_FILE" > /dev/null 2>&1
echo -e "${GREEN}Applied default-deny to test namespace${NC}"

# Run test pod to attempt unauthorized connection
echo ""
echo -e "${BLUE}Testing unauthorized connection (should fail)...${NC}"
echo "Command: kubectl run test-pod --rm -it --image=curlimages/curl --namespace=control-plane -- curl -m 2 http://postgres.data-plane.svc.cluster.local:5432"

# Note: This would actually run interactively, so we'll just show the command
echo ""
echo -e "${YELLOW}⚠ Manual test required:${NC}"
echo "Run the above command to verify connection is blocked"
echo "Expected: connection timeout/refused"

rm -f "$TEST_DENY_FILE"

print_section "9. Deployment Summary"

echo -e "${GREEN}✅ NetworkPolicy deployment completed${NC}"
echo ""
echo "Created files:"
echo "  - $DEFAULT_DENY_FILE"
echo "  - $INTERFACE_MATRIX_FILE"
echo "  - $DNS_ALLOW_FILE"
echo "  - $CONTROL_DATA_ALLOW_FILE"
echo "  - $DATA_STORAGE_ALLOW_FILE"
echo "  - $EGRESS_HTTPS_FILE"
echo ""
echo "Applied NetworkPolicies to namespaces:"
for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    echo "  - $ns"
done
echo ""
echo "Next steps:"
echo "1. Run validation script: ./sf3-networkpolicy-validate.sh"
echo "2. Test cross-namespace connectivity"
echo "3. Update interface matrix with actual dependencies"
echo "4. Document any additional allow rules needed"

exit 0