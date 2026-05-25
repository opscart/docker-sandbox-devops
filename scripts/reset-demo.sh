#!/usr/bin/env bash
# reset-demo.sh
#
# Resets the kubernetes-debugging scenario to its broken initial state.
# Run this inside the sandbox before each demo recording.
#
# What it does:
#   1. Deletes the current payments-service deployment from the cluster
#   2. Restores the broken manifests from manifests-broken/
#   3. Reapplies the broken manifests to the cluster
#   4. Watches pods enter CrashLoopBackOff to confirm demo is ready
#
# Usage:
#   export KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml
#   export NO_PROXY=${NO_PROXY},0.0.0.0
#   bash /Users/opscart/Source/docker-sandbox-devops/scripts/reset-demo.sh

set -euo pipefail

REPO="/Users/opscart/Source/docker-sandbox-devops"
MANIFESTS="${REPO}/scenarios/kubernetes-debugging/manifests"
BROKEN="${REPO}/scenarios/kubernetes-debugging/manifests-broken"

echo "=== Demo Reset: kubernetes-debugging scenario ==="
echo ""

# Step 1 — verify kubeconfig is set
if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "ERROR: KUBECONFIG is not set."
  echo "Run: export KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml"
  exit 1
fi

echo "[1/4] Removing current deployment from cluster..."
kubectl delete -f "${MANIFESTS}/" --ignore-not-found=true
echo "      Done."
echo ""

# Step 2 — restore broken manifests
echo "[2/4] Restoring broken manifests from manifests-broken/..."
cp "${BROKEN}"/* "${MANIFESTS}/"
echo "      Restored:"
for f in "${BROKEN}"/*; do
  echo "      - $(basename $f)"
done
echo ""

# Step 3 — apply broken manifests
echo "[3/4] Applying broken manifests to cluster..."
kubectl apply -f "${MANIFESTS}/"
echo ""

# Step 4 — watch pods for 90 seconds
echo "[4/4] Watching pods — waiting for CrashLoopBackOff to confirm demo is ready..."
echo "      (Ctrl+C once you see CrashLoopBackOff)"
echo ""
timeout 90 kubectl get pods -w || true

echo ""
echo "=== Reset complete. Demo is ready. ==="
echo ""
echo "Give the agent this instruction:"
echo ""
echo "  Read TASK.md in scenarios/kubernetes-debugging/ and complete the task."
echo "  Use KUBECONFIG=${KUBECONFIG}"
echo "  Add --insecure-skip-tls-verify=false (k3d cluster, no TLS issue)."