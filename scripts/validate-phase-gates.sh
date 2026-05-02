#!/bin/bash
# scripts/validate-phase-gates.sh

set -e

validate_gate_0() {
  echo "🔒 Validating Phase 0: Budget Scaffolding..."
  kubectl get priorityclass foundation-critical foundation-high foundation-medium >/dev/null 2>&1 || { echo "❌ PriorityClasses missing"; exit 1; }
  kubectl get storageclass local-path -o jsonpath='{.volumeBindingMode}' | grep -q WaitForFirstConsumer || { echo "❌ StorageClass local-path misconfigured (expected WaitForFirstConsumer)"; }
  [ $(kubectl get nodes -l node-role=storage-heavy --no-headers | wc -l) -ge 2 ] || { echo "❌ Insufficient storage-heavy nodes"; exit 1; }
  echo "✅ Gate 0 passed"
}

validate_gate_1() {
  echo "🔒 Validating Phase 1: Shared Foundations..."
  echo "⚠️  Gate 1 checks deprecated (control-plane namespace removed)"
}

validate_gate_2() {
  echo "🔒 Validating Phase 2: Data Plane (HA & Resource Compliance)..."
  # Check PostgreSQL
  kubectl get pods -n data-plane -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ PostgreSQL not ready"; exit 1; }
  # Check NATS
  kubectl get pods -n data-plane -l app.kubernetes.io/name=nats -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ NATS not ready"; exit 1; }
  # Check MinIO
  kubectl get pods -n data-plane -l app.kubernetes.io/name=minio -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ MinIO not ready"; exit 1; }
  echo "✅ Gate 2 passed"
}

validate_gate_3() {
  echo "🔒 Validating Phase 3: Control Plane (Stability & GitOps)..."
  # Check Kyverno (in dip-control-infra)
  kubectl get pods -n dip-control-infra -l app.kubernetes.io/name=kyverno -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ Kyverno not ready"; exit 1; }
  # Check SPIRE
  kubectl get pods -n dip-control-infra -l app=spire-server -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ SPIRE Server not ready"; exit 1; }
  # Check ArgoCD
  kubectl get pods -n dip-control-infra -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ ArgoCD not ready"; exit 1; }
  echo "✅ Gate 3 passed"
}

validate_gate_4() {
  echo "🔒 Validating Phase 4: Observability Plane..."
  kubectl get pods -n observability-plane -l app.kubernetes.io/name=victoria-metrics -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ VictoriaMetrics not ready"; exit 1; }
  kubectl get pods -n observability-plane -l app.kubernetes.io/name=loki -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ Loki not ready"; exit 1; }
  echo "✅ Gate 4 passed"
}

validate_dip_control_data() {
  echo "🔒 Validating dip-control-data Phase..."
  local ns="dip-control-data"
  # Check PostgreSQL
  kubectl get pods -n $ns -l app=postgres -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ PostgreSQL not ready in $ns"; exit 1; }
  # Check NATS
  kubectl get pods -n $ns -l app=nats -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ NATS not ready in $ns"; exit 1; }
  # Check MinIO
  kubectl get pods -n $ns -l app=minio -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ MinIO not ready in $ns"; exit 1; }
  # Check Temporal
  kubectl get pods -n $ns -l app.kubernetes.io/name=temporal -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "❌ Temporal not ready in $ns"; exit 1; }
  # Check Redis (if used)
  kubectl get pods -n $ns -l app=redis -o jsonpath='{.items[*].status.phase}' | grep -q Running || { echo "⚠️ Redis not ready/found in $ns (optional)"; }
  echo "✅ dip-control-data validation passed"
}

case "${1:-all}" in
  0) validate_gate_0 ;;
  1) validate_gate_1 ;;
  2) validate_gate_2 ;;
  3) validate_gate_3 ;;
  4) validate_gate_4 ;;
  dip-control-data) validate_dip_control_data ;;
  all) validate_gate_0 && validate_gate_1 && validate_gate_2 && validate_gate_3 && validate_gate_4 && validate_dip_control_data ;;
  *) echo "Usage: $0 {0|1|2|3|4|dip-control-data|all}"; exit 1 ;;
esac
