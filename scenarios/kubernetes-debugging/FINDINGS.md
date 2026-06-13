# Findings: payments-service Pod Failures

**Date investigated:** 2026-06-10  
**Cluster:** k3d dev-cluster  
**Image under investigation:** nginx:alpine (placeholder for real payments-service image)

---

## Summary

Three distinct bugs caused continuous pod restarts. All were in `manifests/payments-deployment.yaml`, plus one derived issue in `manifests/payments-service.yaml`.

---

## Bug 1 — Liveness and readiness probes targeting wrong port

**Root cause:** Both probes were configured to check port `8080`, but `nginx:alpine` listens on port `80` by default. Every probe attempt resulted in `connection refused`, causing the kubelet to kill and restart the container on a ~15s cycle.

**Evidence from `kubectl describe pod`:**
```
Warning  Unhealthy  Liveness probe failed: Get "http://10.42.0.10:8080/healthz": dial tcp 10.42.0.10:8080: connect: connection refused
Warning  Unhealthy  Readiness probe failed: Get "http://10.42.0.10:8080/ready": dial tcp 10.42.0.10:8080: connect: connection refused
Normal   Killing    Container payments-service failed liveness probe, will be restarted
```

**Fix:** Changed probe port from `8080` to `80` in both `livenessProbe` and `readinessProbe`.

---

## Bug 2 — Probe paths return 404

**Root cause:** The liveness probe checked `/healthz` and the readiness probe checked `/ready`. Neither path exists in nginx:alpine — both return HTTP 404. Even if the port issue had been fixed, the probes would still fail.

**Evidence (exec into pod):**
```
$ wget -qO- http://localhost:80/healthz
wget: server returned error: HTTP/1.1 404 Not Found

$ wget -qO- http://localhost:80/ → HTTP/1.1 200 OK
```

**Fix:** Changed both probe paths to `/`, which nginx serves with HTTP 200. When the real payments-service image is introduced, the paths should be updated to match whatever health endpoints that image exposes.

---

## Bug 3 — containerPort mismatch

**Root cause:** `containerPort: 8080` was declared in the pod spec, but nginx listens on port 80. While `containerPort` is informational only (it does not control which port the container actually binds), keeping it wrong is misleading and breaks clarity about the service topology.

**Fix:** Changed `containerPort` from `8080` to `80`.

---

## Bug 4 — Memory limit too low (OOMKill risk)

**Root cause:** Memory `requests` and `limits` were both set to `64Mi`. The manifest comment stated the service needs ~150Mi at peak load. At that limit, the kernel OOM killer terminates the container, which shows as restart reason `OOMKilled`.

**Fix:** Raised `requests` to `128Mi` and `limits` to `256Mi` — providing headroom above the documented 150Mi peak.

---

## Bug 5 — Service targetPort mismatch (derived)

**Root cause:** `payments-service.yaml` had `targetPort: 8080`. After fixing the container to serve on port 80, the Service would route traffic to a port with nothing listening, making the service unreachable even when pods appeared healthy.

**Fix:** Changed `targetPort` from `8080` to `80`.

---

## Verification

After applying all fixes:

```
$ kubectl rollout status deployment/payments-service -n default
deployment "payments-service" successfully rolled out

$ kubectl get pods -n default -l app=payments-service
NAME                                READY   STATUS    RESTARTS   AGE
payments-service-76cb6b5f65-kg7cq   1/1     Running   0          15s
payments-service-76cb6b5f65-n655v   1/1     Running   0          26s
```

Both replicas are `1/1 Ready` with `0` restarts.

---

## Files changed

| File | Changes |
|------|---------|
| `manifests/payments-deployment.yaml` | `containerPort` 8080→80; probe ports 8080→80; probe paths `/healthz`→`/` and `/ready`→`/`; memory `requests` 64Mi→128Mi; memory `limits` 64Mi→256Mi |
| `manifests/payments-service.yaml` | `targetPort` 8080→80 |
