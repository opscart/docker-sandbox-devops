#!/usr/bin/env bash
# k3d-create-sbx.sh
#
# Creates a k3d cluster inside a Docker Sandbox (sbx).
# Three fixes are required vs a standard k3d cluster create:
#
#   1. --volume /dev/null:/dev/kmsg@all
#      The sbx microVM does not expose /dev/kmsg to nested containers.
#      Kubelet requires this device at startup. Mapping /dev/null silences
#      the failure without affecting cluster operation.
#
#   2. --k3s-arg "--flannel-backend=host-gw@server:0"
#      The sbx kernel does not support VXLAN (flannel's default backend).
#      host-gw uses static host routes instead — works because all k3d nodes
#      share the same Docker bridge network (L2 adjacent).
#
#   3. --env "...@all:*"
#      Passes sandbox proxy env vars into k3d node containers so in-container
#      HTTP/HTTPS calls (helm chart fetches etc.) route through the proxy.
#      Note: Docker daemon inside sbx already has proxy configured for image
#      pulls — this covers in-container workload traffic only.
#
# Verified against: sbx v0.30.0, k3d v5.7.4, k3s v1.30.4+k3s1
# Host: macOS Apple Silicon
#
# Usage:
#   ./scripts/k3d-create-sbx.sh [cluster-name]
#   Default cluster name: dev-cluster

set -euo pipefail

CLUSTER_NAME="${1:-dev-cluster}"
PROXY="http://gateway.docker.internal:3128"
NO_PROXY_LIST="localhost,127.0.0.1,::1,gateway.docker.internal,0.0.0.0"

echo "[$(date -u +%T)] Creating k3d cluster '${CLUSTER_NAME}' inside sbx sandbox..."

k3d cluster create "${CLUSTER_NAME}" \
  --no-lb \
  --volume /dev/null:/dev/kmsg@all \
  --k3s-arg "--flannel-backend=host-gw@server:0" \
  --env "HTTP_PROXY=${PROXY}@all:*" \
  --env "HTTPS_PROXY=${PROXY}@all:*" \
  --env "NO_PROXY=${NO_PROXY_LIST}@all:*" \
  --wait \
  --timeout 5m0s

echo "[$(date -u +%T)] Cluster created. Configuring kubeconfig..."

# Merge kubeconfig and exclude 0.0.0.0 from proxy to prevent kubectl
# routing API server calls through the sandbox proxy.
k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-switch-context

export KUBECONFIG="${HOME}/.config/k3d/kubeconfig-${CLUSTER_NAME}.yaml"
export no_proxy="${no_proxy:-},0.0.0.0"
export NO_PROXY="${NO_PROXY:-},0.0.0.0"

echo "[$(date -u +%T)] Verifying cluster..."
kubectl get nodes -o wide
echo ""
kubectl get pods -A

echo ""
echo "[$(date -u +%T)] Done. To use this cluster:"
echo "  export KUBECONFIG=${HOME}/.config/k3d/kubeconfig-${CLUSTER_NAME}.yaml"
echo "  export NO_PROXY=\${NO_PROXY},0.0.0.0"
echo "  kubectl get nodes"