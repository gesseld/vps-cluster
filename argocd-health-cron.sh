#!/bin/bash
# ArgoCD Health Check Cron
NAMESPACE=dip-control-infra
LOG_FILE="/var/log/argocd-health.log"
KUBECTL_PATH=$(which kubectl || echo "/usr/local/bin/kubectl")

echo "$(date): Starting health check" >> $LOG_FILE
# Use absolute path for kubectl
$KUBECTL_PATH get applications -n $NAMESPACE -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status >> $LOG_FILE

DEGRADED=$($KUBECTL_PATH get applications -n $NAMESPACE -o jsonpath='{.items[?(@.status.health.status=="Degraded")].metadata.name}')
if [ ! -z "$DEGRADED" ]; then
  echo "ALERT: Degraded applications found: $DEGRADED" >> $LOG_FILE
fi

