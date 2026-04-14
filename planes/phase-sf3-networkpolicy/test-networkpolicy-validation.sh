#!/bin/bash

# Quick test script for SF-3 NetworkPolicy validation
# Run manual tests to verify isolation

set -e

echo "================================================"
echo "SF-3 NetworkPolicy Manual Validation Tests"
echo "================================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "1. Testing default-deny isolation..."
echo "--------------------------------"

echo "Creating test pod in control-plane namespace..."
echo "Attempting unauthorized connection to postgres.data-plane:5432"
echo ""
echo "Run this command manually:"
echo ""
echo -e "${YELLOW}kubectl run test-pod --rm -it --image=curlimages/curl --namespace=control-plane \\"
echo "  -- curl -v -m 5 http://postgres.data-plane.svc.cluster.local:5432${NC}"
echo ""
echo "Expected: Connection timeout or 'Connection refused'"
echo ""

echo "2. Testing DNS resolution (should work)..."
echo "--------------------------------"

echo "Testing DNS from control-plane namespace..."
if kubectl run dns-test --restart=Never --image=busybox -n control-plane \
  --command -- sh -c "nslookup kubernetes.default.svc.cluster.local" 2>/dev/null; then
  
  sleep 3
  echo -e "${GREEN}DNS test pod created${NC}"
  echo "Checking logs..."
  kubectl logs dns-test -n control-plane 2>/dev/null || echo "Pod not ready yet"
  kubectl delete pod dns-test -n control-plane --force --grace-period=0 2>/dev/null || true
else
  echo -e "${RED}Failed to create DNS test pod${NC}"
fi

echo ""
echo "3. Checking NetworkPolicy status..."
echo "--------------------------------"

echo "Listing all NetworkPolicies:"
kubectl get networkpolicies --all-namespaces 2>/dev/null || echo "No NetworkPolicies found"

echo ""
echo "4. Testing HTTPS egress (should work)..."
echo "--------------------------------"

echo "Testing external HTTPS from control-plane..."
echo "Note: This requires internet connectivity"
echo ""
echo "Run this command manually:"
echo ""
echo -e "${YELLOW}kubectl run https-test --rm -it --image=curlimages/curl --namespace=control-plane \\"
echo "  -- curl -I https://google.com${NC}"
echo ""
echo "Expected: HTTP/2 200 or 301 response"
echo ""

echo "5. Testing inter-namespace allowed connections..."
echo "--------------------------------"

echo "If you have PostgreSQL deployed in data-plane:"
echo ""
echo -e "${YELLOW}kubectl run pg-test --rm -it --image=curlimages/curl --namespace=control-plane \\"
echo "  -- curl -v -m 5 http://postgres.data-plane.svc.cluster.local:5432${NC}"
echo ""
echo "Note: This should work if allow-control-to-data policy is applied"
echo ""

echo "================================================"
echo "Test Summary"
echo "================================================"
echo ""
echo "Manual tests to perform:"
echo "1. ✅ Default-deny isolation test (should fail)"
echo "2. ✅ DNS resolution test (should succeed)"
echo "3. ✅ HTTPS egress test (should succeed)"
echo "4. ✅ Inter-namespace allowed test (if services exist)"
echo ""
echo "For comprehensive validation, run:"
echo -e "${GREEN}./sf3-networkpolicy-validate.sh${NC}"
echo ""
echo "This will check all deliverables and automated tests."