#!/bin/bash
# Helper script to cleanly remove all workshop resources (including untracked runtime builds) and optionally redeploy.

set -e

echo "=== Cleaning Up Workshop POC Resources ==="

# 1. Uninstall Helm release
if helm status workshop-poc >/dev/null 2>&1; then
    echo "Uninstalling Helm release 'workshop-poc'..."
    helm uninstall workshop-poc
else
    echo "Helm release 'workshop-poc' is not installed. Skipping uninstall."
fi

# 2. Delete untracked runtime builds and build pods
echo "Deleting dynamically created build history and pods..."
oc delete builds -l app.kubernetes.io/name=workshop --ignore-not-found=true
oc delete pods -l openshift.io/build.name --ignore-not-found=true

# 3. Verify deletion
echo "Verifying namespace status..."
oc get all -l app.kubernetes.io/name=workshop

echo "=== Cleanup Complete ==="
echo "To stand the environment back up, run:"
echo "  helm install workshop-poc charts/workshop"
