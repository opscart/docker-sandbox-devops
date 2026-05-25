# Agent Task: Investigate and Fix payments-service OOMKill

## Situation

The `payments-service` in the development cluster is OOMKilling under normal traffic.
On-call flagged repeated restarts overnight. Pod restarts are increasing and the service
is affecting downstream checkout flow.

## What you have access to

- A k3d cluster running inside this sandbox (`dev-cluster`)
- The service manifests at `scenarios/kubernetes-debugging/manifests/`
- kubectl, helm, kustomize — all available

## Your task

1. Deploy the payments-service to the dev-cluster
2. Investigate the resource configuration
3. Identify why OOMKill is occurring
4. Fix the memory limits to appropriate values for a payment processing service
5. Redeploy and verify the pods are stable
6. Document what you changed and why in `scenarios/kubernetes-debugging/FINDINGS.md`

## Constraints

- Do not modify anything outside `scenarios/kubernetes-debugging/`
- Do not create new namespaces
- The fix must be in the manifest file — not a `kubectl patch` one-liner

## Expected output

- Updated `manifests/payments-deployment.yaml` with corrected resource limits
- `FINDINGS.md` explaining the root cause and the fix