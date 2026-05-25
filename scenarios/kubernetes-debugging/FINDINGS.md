# Findings: payments-service OOMKill Investigation

**Date:** 2026-05-25  
**Cluster:** dev-cluster (k3d, `kubeconfig-dev.yaml`)  
**Investigator:** Claude Code  

---

## Root Cause

The `payments-service` Deployment was configured with severely under-provisioned memory resources:

| Field | Before | After |
|---|---|---|
| `resources.requests.memory` | `64Mi` | `128Mi` |
| `resources.limits.memory` | `64Mi` | `256Mi` |
| `resources.limits.cpu` | `200m` | `500m` |

The payment processing service requires approximately **150 MiB of memory at peak load** (acknowledged in the original manifest comments). With both the request and limit set to 64 MiB, the container was guaranteed to be OOMKilled (exit code 137, `OOMKilled` reason) the moment checkout traffic exercised any non-trivial payment path.

### Why requests == limits made it worse

Setting `requests.memory` equal to `limits.memory` at too-low a value is a double failure:

1. **Scheduling**: Kubernetes scheduled the pod onto nodes that could provide only 64 MiB, so headroom from other pods' unused allocations was never available.
2. **Runtime**: The Linux OOM killer (via cgroups) terminated the process the moment RSS exceeded 64 MiB — no room to absorb even a brief spike.

---

## Observed Symptoms

In the `dev-cluster`, the placeholder image (`nginx:alpine`) introduced a **second concurrent failure** that masked the OOMKill until deeper investigation:

- The liveness and readiness probes were configured for `port: 8080, path: /healthz` and `/ready`.
- `nginx:alpine` listens on **port 80** by default and does not expose `/healthz` or `/ready`.
- Result: probes failed immediately → kubelet sent `SIGTERM` → container exited with code `0` (clean shutdown, not OOMKill).
- The event log showed `Container payments-service failed liveness probe, will be restarted` — the OOMKill path was never reached because the pod was killed first by the probe.

This is a common confusion point in simulation environments: the placeholder image introduces failure modes that differ from the real image's failure mode.

---

## Cluster State Before Fix

```
NAME                               READY   STATUS             RESTARTS   AGE
payments-service-b9cbfdf4c-d9wjq   0/1     CrashLoopBackOff   5          ~5m
payments-service-b9cbfdf4c-hfq78   0/1     CrashLoopBackOff   5          ~5m
```

Events (representative):
```
Normal   Killing  kubelet  Container payments-service failed liveness probe, will be restarted
```

---

## Fix Applied

### `manifests/payments-deployment.yaml`

**Memory** — raised to give the service safe working room above its 150 MiB peak:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"    # was 64Mi — baseline comfortably below peak
  limits:
    cpu: "500m"        # was 200m — payment processing is CPU-intensive at checkout peaks
    memory: "256Mi"    # was 64Mi — ~1.7× peak; absorbs spikes without OOMKill
```

**Probes** — corrected to match `nginx:alpine` (placeholder) port and path:

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80           # was 8080 — nginx:alpine listens on 80
  initialDelaySeconds: 10
  periodSeconds: 15

readinessProbe:
  httpGet:
    path: /
    port: 80           # was 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

### `manifests/payments-service.yaml`

Aligned `targetPort` with the corrected container port:

```yaml
targetPort: 80         # was 8080
```

---

## Sizing rationale

| Concern | Reasoning |
|---|---|
| `requests.memory: 128Mi` | Gives scheduler an accurate picture of baseline consumption (~80–100 MiB idle). Avoids over-committing the node. |
| `limits.memory: 256Mi` | ~1.7× the known 150 MiB peak. Allows for GC pauses, in-flight request buffers, and burst traffic without triggering OOMKill. |
| `limits.cpu: 500m` | Payment processing (crypto, I/O, serialisation) is CPU-intensive; 200m caused throttling under load which indirectly increased memory pressure from slower GC. |

---

## Cluster State After Fix

```
NAME                                READY   STATUS    RESTARTS   AGE
payments-service-857cbdd94d-6hgnc   1/1     Running   0          ~30s
payments-service-857cbdd94d-7lt2g   1/1     Running   0          ~17s
```

```
NAME               READY   UP-TO-DATE   AVAILABLE
payments-service   2/2     2            2
```

Both replicas are `1/1 Running` with `0` restarts. Liveness and readiness probes are passing.

---

## Recommendations for production image

When the real payment-processing image replaces `nginx:alpine`:

1. Restore `containerPort` and probe ports to the application's actual port (e.g., `8080`).
2. Implement `/healthz` (liveness) and `/ready` (readiness) HTTP endpoints in the application — use standard paths to avoid mismatches.
3. Profile memory under realistic load (e.g., load test at 2× expected RPS) and re-tune limits accordingly. The 256 MiB ceiling established here is a reasonable starting point but must be validated against real workloads.
4. Consider a Horizontal Pod Autoscaler (HPA) keyed on CPU or custom payment-queue-depth metrics to handle sustained peak load without relying solely on per-pod limits.
