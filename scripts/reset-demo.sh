#!/usr/bin/env bash
# reset-demo.sh
#
# Resets the kubernetes-debugging scenario to its broken initial state.
# Run this inside the sandbox before each demo recording.
#
# Usage:
#   export KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml
#   export NO_PROXY=${NO_PROXY},0.0.0.0
#   bash /Users/opscart/Source/docker-sandbox-devops/scripts/reset-demo.sh

set -euo pipefail

REPO="/Users/opscart/Source/docker-sandbox-devops"
MANIFESTS="${REPO}/scenarios/kubernetes-debugging/manifests"
BROKEN="${REPO}/scenarios/kubernetes-debugging/manifests-broken"
FINDINGS="${REPO}/scenarios/kubernetes-debugging/FINDINGS.md"

echo "=== Demo Reset: kubernetes-debugging scenario ==="
echo ""

if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "ERROR: KUBECONFIG is not set."
  echo "Run: export KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml"
  exit 1
fi

echo "[1/4] Removing current deployment from cluster..."
kubectl delete -f "${MANIFESTS}/" --ignore-not-found=true
echo "      Done."
echo ""

echo "[2/4] Restoring broken manifests and removing previous findings..."
cp "${BROKEN}"/* "${MANIFESTS}/"
rm -f "${FINDINGS}"
echo "      Restored:"
for f in "${BROKEN}"/*; do
  echo "      - $(basename $f)"
done
echo "      Removed: FINDINGS.md"
echo ""

echo "[3/4] Applying broken manifests to cluster..."
kubectl apply -f "${MANIFESTS}/"
echo ""

echo "[4/4] Watching pods — waiting for restarts to confirm demo is ready..."
echo "      (Ctrl+C once you see restarts)"
echo ""
timeout 90 kubectl get pods -w || true

echo ""
echo "=== Reset complete. Demo is ready. ==="
echo ""
echo "Give the agent this instruction in Terminal 1:"
echo ""
echo "  Read TASK.md in scenarios/kubernetes-debugging/ and complete the task."
echo "  Use KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml"