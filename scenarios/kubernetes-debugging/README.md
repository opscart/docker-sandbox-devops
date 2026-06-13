# Scenario: Kubernetes Debugging with an AI Agent

## What this scenario demonstrates

An AI coding agent (Claude Code) running inside a Docker Sandbox investigates and fixes a broken Kubernetes deployment. The agent has access to a Kubernetes cluster via `kubectl`, can read and modify manifests in the workspace, and can redeploy — but cannot touch anything outside the sandbox boundary: no other repos, no other cluster contexts, no host credentials.

## sbx version verified

`v0.30.0` on macOS Apple Silicon. Agent: Claude Code v2.1.141. k3d v5.7.4.

## The task

The `payments-service` deployment is OOMKilling in the development cluster. On-call flagged repeated pod restarts overnight. The agent is given a task file and a set of manifests. No other context.

Full task: [`TASK.md`](./TASK.md)

---

## Approach A — Self-contained (k3d inside the sandbox) ⭐ recommended for demos

The cluster runs entirely inside the sandbox using its private Docker daemon. No external cluster, no kubeconfig extraction, no host network policy rules. Destroy the sandbox and everything is gone — cluster, workloads, manifests.

### Prerequisites

- `sbx` v0.30.0 installed and authenticated
- DevOps toolkit template v1.1.0 (includes kubectl, helm, kustomize, azure-cli, k3d):
  `ghcr.io/opscart/sbx-devops-toolkit:v1.1.0`

### Step 1: Start the sandbox

```bash
sbx run claude \
  --template ghcr.io/opscart/sbx-devops-toolkit:v1.1.0 \
  --name kubernetes-debugging
```

### Step 2: Log in to Claude Code

Inside the Claude Code TUI (Terminal 1):

```
/login
```

Follow the device auth flow. Without login the agent accepts input but produces no output.

### Step 3: Create the k3d cluster

In a second terminal:

```bash
sbx exec -it kubernetes-debugging bash
bash /Users/<user>/Source/docker-sandbox-devops/scripts/k3d-create-sbx.sh
```

The script handles all sbx-specific fixes automatically. Expected output:

```
[HH:MM:SS] Creating k3d cluster 'dev-cluster' inside sbx sandbox...
INFO[0005] Cluster 'dev-cluster' created successfully!
[HH:MM:SS] Verifying cluster...
NAME                       STATUS   ROLES    AGE   VERSION
k3d-dev-cluster-server-0   Ready    <none>   3s    v1.30.4+k3s1
```

> **Why a special script?** Standard `k3d cluster create` hangs inside Docker Sandbox.
> Two kernel capability gaps must be worked around — see [`../../docs/friction-log.md`](../../docs/friction-log.md)
> for the full diagnostic trail. The script applies three fixes:
>
> 1. `--volume /dev/null:/dev/kmsg@all` — microVM does not expose `/dev/kmsg`; kubelet requires it at startup
> 2. `--k3s-arg "--flannel-backend=host-gw@server:0"` — sandbox kernel has no VXLAN support; host-gw uses static routes instead
> 3. `--env proxy@all:*` — passes sandbox proxy env vars into k3d node containers for in-container HTTP calls

### Step 4: Set environment and reset demo state

```bash
export KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml
export NO_PROXY=${NO_PROXY},0.0.0.0
bash /Users/<user>/Source/docker-sandbox-devops/scripts/reset-demo.sh
```

The reset script:
- Deletes any existing payments-service deployment
- Restores the broken manifests from `manifests-broken/`
- Applies them to the cluster
- Watches until pods start failing (confirms demo is ready)

Expected: pods enter `Running` then restart repeatedly — probe failures from the misconfigured health checks.

### Step 5: Give the agent the task

In Terminal 1 (Claude Code TUI):

```
Read /Users/<user>/Source/docker-sandbox-devops/scenarios/kubernetes-debugging/TASK.md
and complete the task.
Use KUBECONFIG=/home/agent/.config/k3d/kubeconfig-dev-cluster.yaml
No --insecure-skip-tls-verify needed (k3d cluster, no TLS issue).
```

### Step 6: Repeat the demo

For each subsequent run, just reset:

```bash
bash /Users/<user>/Source/docker-sandbox-devops/scripts/reset-demo.sh
```

No need to recreate the cluster between runs.

### Cleanup

```bash
k3d cluster delete dev-cluster
exit
sbx rm kubernetes-debugging
```

---

## Approach B — External cluster (minikube or any local cluster)

The cluster runs on the host machine. The sandbox agent connects to it via a sanitized kubeconfig. Useful for testing against a real multi-node cluster.

### Prerequisites

- `sbx` v0.30.0 installed and authenticated
- DevOps toolkit template: `ghcr.io/opscart/sbx-devops-toolkit:v1.1.0`
- A running Kubernetes cluster on your host: `kubectl get nodes`

### Step 1: Extract a sanitized kubeconfig

```bash
kubectl config view --minify --flatten > scenarios/kubernetes-debugging/kubeconfig-dev.yaml
```

> ⚠️ This file contains embedded certificates. It is gitignored. Never commit it.

### Step 2: Update the kubeconfig server address

If your cluster API is on `127.0.0.1` (minikube default), replace with `host.docker.internal`:

```bash
# macOS requires -i '' for BSD sed
sed -i '' 's|https://127.0.0.1:<PORT>|https://host.docker.internal:<PORT>|g' \
  scenarios/kubernetes-debugging/kubeconfig-dev.yaml
```

Add TLS skip (cert is issued to `127.0.0.1`, not `host.docker.internal`):

```yaml
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://host.docker.internal:<PORT>
  name: <cluster-name>
```

### Step 3: Add network policy rules

```bash
sbx policy allow network -g host.docker.internal
sbx policy allow network -g localhost:<PORT>
```

> **Why localhost?** The proxy resolves `host.docker.internal` to `localhost` internally and applies policy against `localhost:<PORT>`. Both rules are needed — adding only `host.docker.internal` is not sufficient.

> **Port changes on minikube restart:** minikube assigns a random high port at cluster creation. Check the current port with `kubectl cluster-info`. Remove old rules with `sbx policy rm network -g --resource <host>` and add new ones.

> **Registry rules not needed:** `ghcr.io`, `registry-1.docker.io`, `auth.docker.io` are already in the default Balanced policy. Do not add them manually.

### Step 4: Run the sandbox and test

```bash
sbx run claude \
  --template ghcr.io/opscart/sbx-devops-toolkit:v1.1.0 \
  --name kubernetes-debugging
```

Inside the sandbox:

```bash
export KUBECONFIG=/Users/<user>/Source/docker-sandbox-devops/scenarios/kubernetes-debugging/kubeconfig-dev.yaml
kubectl get nodes --insecure-skip-tls-verify
```

### Cleanup

```bash
sbx rm kubernetes-debugging
rm scenarios/kubernetes-debugging/kubeconfig-dev.yaml
sbx policy rm network -g --resource host.docker.internal
sbx policy rm network -g --resource localhost:<PORT>
```

---

## What the agent did (verified output)

The agent completed the task in ~3 minutes. It identified **two bugs**, not one:

### Bug 1 — Memory limits too low (the planted bug)

```yaml
# Before
resources:
  requests:
    memory: "64Mi"
  limits:
    memory: "64Mi"   # OOMKill at peak load (~150Mi)

# After
resources:
  requests:
    memory: "128Mi"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

### Bug 2 — Probe misconfiguration (found independently by the agent)

```yaml
# Before — wrong port and paths for nginx:alpine
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080

# After
livenessProbe:
  httpGet:
    path: /
    port: 80
```

### Cluster state after fix

```
NAME                                READY   STATUS    RESTARTS   AGE
payments-service-857cbdd94d-6hgnc   1/1     Running   0          40s
payments-service-857cbdd94d-7lt2g   1/1     Running   0          26s
```

Full findings in [`FINDINGS.md`](./FINDINGS.md) (written by the agent).

---

## What the isolation actually prevented

The agent had:
- ✅ Full access to `scenarios/kubernetes-debugging/` — read manifests, wrote FINDINGS.md
- ✅ `kubectl` access to the explicitly allowed cluster
- ✅ Ability to deploy, redeploy, describe pods, watch rollouts

The agent could NOT access:
- ❌ Other directories in the workspace
- ❌ Other kubeconfig contexts
- ❌ `~/.aws`, `~/.ssh`, host credentials
- ❌ Other clusters not in the policy allowlist
- ❌ Arbitrary internet

An agent running directly on the developer's machine would have had access to all of these.

---

## Friction encountered

Full diagnostic trail in [`../../docs/friction-log.md`](../../docs/friction-log.md). Summary:

- **k3d standard cluster create hangs** — `/dev/kmsg` missing in microVM, flannel VXLAN unsupported by sandbox kernel. Fixed with two `--volume` and `--k3s-arg` flags.
- **kubectl routes API calls through proxy** — `0.0.0.0` not in `NO_PROXY`, kubectl sends API calls to the sandbox proxy which rejects them. Fixed by adding `0.0.0.0` to `NO_PROXY`.
- **Policy rule removal syntax** — `sbx policy deny` does not remove allow rules. Correct command: `sbx policy rm network -g --resource <host>`.
- **macOS sed syntax** — requires `-i ''`. `sed -i 's/...'` fails with "unescaped newline".
- **Claude Code login** — agent produces no output if not logged in. Run `/login` before giving any task.