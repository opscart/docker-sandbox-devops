# Friction Log

Real-time, dated capture of friction points encountered while exploring Docker Sandboxes. Entries are added as friction occurs, not reconstructed from memory after the fact.

## Format

```
## YYYY-MM-DD — Short title
**Context:** what I was trying to do
**Observation:** what happened (with real terminal output)
**Workaround / Resolution:** if any
**sbx version:** the version where this was observed
**Follow-up:** something to investigate in a later lab, if applicable
```

---

## 2026-05-14 — Daemon reported as not running by `sbx version` after successful login ✅ RESOLVED 2026-05-21

**Context:** Fresh install via `brew install docker/tap/sbx` on macOS Apple Silicon. Ran `sbx login` (successful, daemon auto-started with PID 47839), selected `Balanced` network policy, kicked off `sbx run claude` in a project directory. Sandbox image started downloading.

In a separate terminal action, ran `sbx version` to record the installed version for `tested-with.md`.

**Observation:**

```
$ sbx version
Client Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119
Server Version:  Unavailable (daemon not running — use 'sbx daemon start')
```

This contradicts the daemon clearly starting during `sbx login` minutes earlier:

```
Daemon started (PID: 47839, socket: /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock)
```

**Resolution (2026-05-21):**

Ran the full daemon lifecycle test. Real output:

```
$ sbx daemon start
Daemon is already running at /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock

$ sbx version
Client Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119
Server Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119

$ sbx daemon stop
Stopping daemon at /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock...
✓ Daemon stopped successfully

$ sbx version
Client Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119
Server Version:  Unavailable (daemon not running — use 'sbx daemon start')

$ sbx daemon start
Starting daemon at /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock (Ctrl+C to stop)...
{"time":"2026-05-21T22:43:08.160664-04:00","level":"INFO","msg":"loggingkit started"}
{"time":"2026-05-21T22:43:08.161077-04:00","level":"INFO","msg":"secretskit started"}
...
{"time":"2026-05-21T22:43:10.050874-04:00","level":"INFO","msg":"api server started successfully"}
```

**Findings:**

The daemon lifecycle has three modes:

1. **Implicit start** — `sbx run` and `sbx login` start the daemon in the background when it isn't running. The login-time start appears to be session-scoped and stops after the login flow completes. This explains the original "Unavailable" report: the daemon started by `sbx login` had stopped by the time `sbx version` was run (likely after `sbx run` completed its download and the session ended).

2. **Explicit foreground start** — `sbx daemon start` runs the daemon in the foreground, streaming JSON structured logs, and blocks the terminal until Ctrl+C. This is a debugging/inspection mode, not the normal usage path.

3. **Explicit stop** — `sbx daemon stop` stops cleanly. `sbx version` correctly reports "Unavailable" after stop.

**Practical implication:** For normal use, don't manage the daemon manually. `sbx run` handles it. Use `sbx daemon start` only when you need to watch daemon-level logs. Use `sbx version` only when the daemon is already running (i.e., right after `sbx run` or `sbx ls`); otherwise the server version will show Unavailable.

**Additional observation from daemon restart output:** When the daemon restarts, it re-injects the proxy and SSH agent forwarder for all previously running sandboxes:

```
"msg":"re-injected proxy for loaded runtime","runtime":"claude-12-docker-hardened-images"
```

This confirms sandboxes persist across daemon restarts — the microVM state is preserved in storage, not in the daemon's in-memory state.

**sbx version:** v0.29.0 (both client and server confirmed after explicit daemon start).

---

## 2026-05-21 — Upgraded to v0.30.0; three behavioral changes affect this repo

**Context:** Upgrade from v0.29.0 to v0.30.0 via `brew upgrade docker/tap/sbx` during Lab 01 closeout.

**Observation:**

```
$ sbx version
Client Version:  v0.30.0 2852d3aaf659177ffb8fd9d06298ef64df6fadf7
Server Version:  Unavailable (daemon not running — use 'sbx daemon start')
```

Server Unavailable is expected — consistent with documented daemon lifecycle behavior. Upgrade itself was clean.

**Three v0.30.0 changes that affect labs in this repo:**

1. **Grace period before sandbox auto-stop (daemon/sandbox lifecycle).** v0.29.0 auto-stopped sandboxes immediately when the last session exited. v0.30.0 adds a configurable grace period before auto-stop. This refines the daemon lifecycle documented in the 2026-05-14 entry — the auto-stop is now delayed, not immediate. Relevant to Labs 01, 04, and any scenario involving sandbox persistence.

2. **Raw TCP to `host.docker.internal` allowed when localhost is in policy (Lab 02).** In v0.30.0, if `localhost` is permitted by the active network policy, raw TCP to `host.docker.internal` is also permitted. This is a new behavior — v0.29.0 did not have this. Lab 02 will explicitly test this case and document it as a v0.30.0-specific finding.

3. **macOS `/private` path compatibility for worktrees (Lab 04).** On macOS, paths under `/private/var` vs `/var` caused worktree failures in v0.29.0. Fixed in v0.30.0. Lab 04 uses `--branch` mode; this fix means `--branch` is reliable on Apple Silicon macOS from this version forward.

**sbx version:** v0.30.0 (`2852d3aaf659177ffb8fd9d06298ef64df6fadf7`)


---

## 2026-05-23 — kustomize official install script fails on ARM64 in Docker build context

**Context:** Building `templates/dev-environment/Dockerfile` with `--platform linux/arm64`. Used the official kustomize install script from `raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh`.

**Observation:**

```
=> ERROR [5/7] RUN curl -fsSL "https://raw.githubusercontent.com/.../install_kustomize.sh" | bash
1.023 tar (child): ./kustomize_v*_linux_arm64.tar.gz: Cannot open: No such file or directory
1.023 tar (child): Error is not recoverable: exiting now
1.024 tar: Child returned status 2
1.024 tar: Error is not recoverable: exiting now
ERROR: failed to build: exit code: 2
```

The script downloads a tarball then uses a glob (`./kustomize_v*_linux_arm64.tar.gz`) to find it. The download silently fails or the glob doesn't match, leaving nothing for tar to extract.

**Resolution:** Replace the install script with a direct GitHub release download using a pinned version:

```dockerfile
ARG KUSTOMIZE_VERSION=5.4.3

RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" \
    -o kustomize.tar.gz && \
    tar xzf kustomize.tar.gz && \
    mv kustomize /usr/local/bin/kustomize && \
    rm kustomize.tar.gz
```

Build succeeded after this change.

**sbx version:** v0.30.0 (host Docker build — not a sandbox-specific issue, but relevant to anyone building DevOps templates for ARM64)

---

## 2026-05-25 — `sbx policy deny` does not remove an allow rule

**Context:** Cleaning up network policy rules added during the kubernetes-debugging scenario.

**Observation:**

```
$ sbx policy deny network -g host.docker.internal
ERROR: deny network rule: deny:
  "host.docker.internal" conflicts with existing allow rule "50403dcf-..."
```

**Explanation:** `sbx policy deny` adds a new deny rule. It does not remove an existing allow rule. When an allow rule already exists for the same resource, the deny conflicts and errors.

**Resolution:** Use `sbx policy rm network` with `--resource` or `--id`:

```bash
# Remove by resource (simpler)
sbx policy rm network -g --resource host.docker.internal

# Remove by UUID (use when resource has port, e.g. localhost:57919)
sbx policy rm network -g --id <uuid>   # get UUID from sbx policy ls
```

**sbx version:** v0.30.0

---

## 2026-05-25 — k3d cluster creation hangs indefinitely inside sbx sandbox

**Context:** Running a k3d Kubernetes cluster inside a Docker Sandbox (sbx) with its own private Docker daemon. Goal: `k3d cluster create` should complete and `kubectl get nodes` should return a Ready node.

Previous attempt failed — k3d hung indefinitely at "Starting node k3d-dev-cluster-server-0". Initial hypothesis was that k3s containers could not reach external endpoints due to missing proxy configuration.

**Observation (first attempt — proxy-only hypothesis):**

```
$ k3d cluster create dev-cluster \
    --env "HTTP_PROXY=http://gateway.docker.internal:3128@server:*" \
    ...
INFO[0006] Starting node 'k3d-dev-cluster-server-0'
ERRO[0246] Failed Cluster Start: error during post-start cluster preparation:
  error waiting for log line `cluster dns configmap` from node
  'k3d-dev-cluster-server-0': stopped returning log lines: context deadline exceeded
FATA[0246] Cluster creation FAILED, all changes have been rolled back!
```

Adding `--env` proxy flags didn't help. Streaming the k3s container logs during startup revealed the actual errors.

**Root cause 1 — `/dev/kmsg` does not exist in the sbx sandbox:**

The sandbox kernel does not expose `/dev/kmsg` to nested Docker containers. The k3s kubelet requires this device at startup:

```
Error: failed to run Kubelet: failed to create kubelet: open /dev/kmsg: no such file or directory
time="..." level=error msg="kubelet exited: failed to run Kubelet: failed to create kubelet: open /dev/kmsg: no such file or directory"
```

Verification:
```
$ ls -la /dev/kmsg
ls: cannot access '/dev/kmsg': No such file or directory
```

**Root cause 2 — Flannel VXLAN backend unsupported by the sbx kernel:**

Even after fixing the `/dev/kmsg` issue, k3s entered a crash loop because flannel (k3s's default CNI, which uses VXLAN by default) failed with:

```
time="..." level=error msg="flannel exited: failed to register flannel network: operation not supported"
```

The sandbox kernel does not have VXLAN support. Earlier in startup, modprobe also reported:

```
time="..." level=warning msg="Failed to load kernel module br_netfilter with modprobe"
time="..." level=warning msg="Failed to load kernel module iptable_nat with modprobe"
```

These crash loops brought down the API server, causing k3d to hang indefinitely waiting for the cluster to become ready.

**Secondary observation — HTTPS_PROXY intercepts kubectl API server calls:**

The sandbox sets `HTTPS_PROXY=http://gateway.docker.internal:3128`. The k3d-generated kubeconfig points to `https://0.0.0.0:<port>`. Because `0.0.0.0` is not in `no_proxy`, kubectl routes the API server connection through the proxy, which fails. This is a separate issue from cluster creation but affects subsequent `kubectl` usage.

**Resolution — three-part fix:**

```bash
k3d cluster create dev-cluster \
  --no-lb \
  --volume /dev/null:/dev/kmsg@all \
  --k3s-arg "--flannel-backend=host-gw@server:0" \
  --env "HTTP_PROXY=http://gateway.docker.internal:3128@all:*" \
  --env "HTTPS_PROXY=http://gateway.docker.internal:3128@all:*" \
  --env "NO_PROXY=localhost,127.0.0.1,::1,gateway.docker.internal@all:*" \
  --wait \
  --timeout 5m0s
```

Fix 1 — `--volume /dev/null:/dev/kmsg@all`: Bind-mounts `/dev/null` as `/dev/kmsg` in every k3d node container. Kubelet opens the device successfully (reads EOF), prevents the startup crash. No kernel log monitoring, but the cluster functions normally.

Fix 2 — `--k3s-arg "--flannel-backend=host-gw@server:0"`: Switches flannel from VXLAN (requires `vxlan` kernel module) to `host-gw` (uses static host routes). In k3d, all nodes share the same Docker bridge network, so L2 adjacency is guaranteed and `host-gw` works correctly.

Fix 3 — `--env "...@all:*"`: Passes sandbox proxy env vars into the k3d node containers. Belt-and-suspenders: the Docker daemon already has proxy configured (visible in `docker info | grep -i proxy`) so image pulls work without this, but any in-container HTTP/HTTPS calls (e.g., helm chart fetches) need it too.

For `kubectl` after cluster creation — add `0.0.0.0` to `NO_PROXY` to prevent the kubeconfig server address from being proxied:

```bash
k3d kubeconfig get dev-cluster > /tmp/kube.yaml
no_proxy="${no_proxy},0.0.0.0" NO_PROXY="${NO_PROXY},0.0.0.0" \
  KUBECONFIG=/tmp/kube.yaml kubectl get nodes
```

**Verified output:**

```
$ kubectl get nodes -o wide
NAME                       STATUS   ROLES                  AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE           KERNEL-VERSION   CONTAINER-RUNTIME
k3d-dev-cluster-server-0   Ready    control-plane,master   24s   v1.30.4+k3s1   172.19.0.2    <none>        K3s v1.30.4+k3s1   7.0.3            containerd://1.7.20-k3s1

$ kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   coredns-576bfc4dc7-xzrp5                  1/1     Running     0          10s
kube-system   helm-install-traefik-crd-sjm4d            0/1     Completed   0          10s
kube-system   helm-install-traefik-tl4bv                0/1     Completed   1          10s
kube-system   local-path-provisioner-6795b5f9d8-jwnhw   1/1     Running     0          10s
kube-system   metrics-server-557ff575fb-75qds           0/1     Running     0          10s
kube-system   svclb-traefik-0f108599-thlp9              0/2     ContainerCreating   0   1s
kube-system   traefik-5fb479b77-cjnsp                   0/1     ContainerCreating   0   1s
```

**Why the initial proxy hypothesis was wrong:** The Docker daemon inside the sandbox already had `HTTP Proxy: http://gateway.docker.internal:3128` configured (visible via `docker info`). Image pulls (rancher/k3s, ghcr.io/k3d-io/k3d-tools) worked fine on the first attempt. The actual blockers were kernel capability gaps, not proxy propagation.

**sbx version:** v0.30.0

**Follow-up:** Investigate whether a minimal k3d config (single-node, `--flannel-backend=host-gw`, `--volume /dev/null:/dev/kmsg@all`) should be codified as the canonical sbx-compatible cluster spec in `scenarios/kubernetes-debugging/`. Also investigate whether using k3d's `--registry-create` flag inside sbx requires additional kernel capabilities.