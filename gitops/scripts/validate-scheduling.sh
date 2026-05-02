#!/bin/bash
# validate-scheduling.sh — Block manifests that allow stateless workloads on CP
# Flags manifests with node-role.kubernetes.io/control-plane tolerations on non-stateful workloads
echo "🔍 Checking scheduling policy compliance..."
VIOLATIONS=0
# Check for CP tolerations on deployments without stateful justification
for f in $(find gitops/ -name '*.yaml'); do
  if grep -q 'node-role.kubernetes.io/control-plane' "$f"; then
    if ! grep -q -i 'stateful\|postgres\|redis\|temporal\|spire\|nats' "$f"; then
      echo "⚠️  Possible violation: $f allows CP scheduling"
      VIOLATIONS=$((VIOLATIONS+1))
    fi
  fi
done
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "❌ $VIOLATIONS scheduling policy violations found"
  exit 1
fi
echo "✅ All manifests comply with scheduling policy"
exit 0
