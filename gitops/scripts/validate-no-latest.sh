#!/bin/bash
# validate-no-latest.sh — Block commits/pipelines containing :latest image tags
FOUND=$(grep -r 'image:.*:latest' gitops/ | grep -v '.md' | wc -l)
if [ "$FOUND" -gt 0 ]; then
  echo "❌ $FOUND :latest tags found in manifests:"
  grep -r 'image:.*:latest' gitops/ | grep -v '.md'
  exit 1
fi
echo "✅ No :latest tags in manifests"
exit 0
