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

# 2. Delete untracked runtime builds, build pods, and hook jobs
echo "Deleting dynamically created build history, pods, and jobs..."
oc delete builds -l app.kubernetes.io/name=workshop --ignore-not-found=true
oc delete pods -l openshift.io/build.name --ignore-not-found=true
oc delete jobs -l app.kubernetes.io/name=workshop --ignore-not-found=true

# 3. Verify deletion (avoiding 'oc get all' which is restricted in Developer Sandbox)
echo "Verifying namespace status..."
oc get pods,svc,route,deployment,bc,builds,job,pvc,secret -l app.kubernetes.io/name=workshop --ignore-not-found=true

echo "=== Cleanup Complete ==="
echo "To stand the environment back up, run:"
echo "  helm install workshop-poc charts/workshop \\"
echo "    --set openshift.apiServer=\$(oc whoami --show-server) \\"
echo "    --set openshift.token=\$(oc whoami -t)"
