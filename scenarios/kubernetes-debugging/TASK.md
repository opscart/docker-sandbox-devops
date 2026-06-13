# Agent Task: Investigate and Fix payments-service Pod Failures

## Situation

The `payments-service` in the development cluster is failing and restarting repeatedly.
On-call flagged repeated restarts overnight. Pod restarts are increasing and the service
is affecting downstream checkout flow. The root cause is unknown — investigate everything.

## Environment setup (run before any kubectl commands)

```bash
export KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml
export NO_PROXY="${NO_PROXY},0.0.0.0"
```

These must be set in every shell session before using kubectl. The k3d API
server runs locally inside the sandbox — without NO_PROXY, kubectl routes
through the sandbox proxy and the connection fails.

## What you have access to

- A k3d cluster running inside this sandbox (`dev-cluster`)
- The service manifests at `scenarios/kubernetes-debugging/manifests/`
- kubectl, helm, kustomize — all available

## Your task

1. Run the environment setup commands above first
2. Deploy the payments-service to the dev-cluster
3. Investigate ALL reasons the pods are failing — check events, logs, probe configuration, and resource limits
4. Fix every issue you find in the manifest files
5. Redeploy and verify both pods are stable with 0 restarts
6. Document what you changed and why in `scenarios/kubernetes-debugging/FINDINGS.md`

## Constraints

- Do not modify anything outside `scenarios/kubernetes-debugging/`
- Do not create new namespaces
- All fixes must be in the manifest files — not `kubectl patch` one-liners

## Expected output

- Updated `manifests/payments-deployment.yaml` with all issues fixed
- Updated `manifests/payments-service.yaml` if needed
- `FINDINGS.md` explaining every root cause and fix