#!/bin/bash
# Script to register repo with webhook secret
ARGOCD_NAMESPACE=dip-control-infra
REPO_URL="https://github.com/gesseld/vps-cluster.git"

echo "Registering webhook secret for repository: \"
# In ArgoCD 2.4+, the webhook secret is configured via argocd-cm or repository-specific settings.
# For GitHub, we typically just need the secret in argocd-cm as we did.
echo "Webhook secret configured in argocd-cm."
