# Scenario: Kubernetes Debugging with an AI Agent

## What this scenario demonstrates

An AI coding agent (Claude Code) running inside a Docker Sandbox investigates and fixes a broken Kubernetes deployment. The agent has access to a real cluster via `kubectl`, can read and modify manifests in the workspace, and can redeploy — but cannot touch anything outside the sandbox boundary: no other repos, no other cluster contexts, no host credentials.

## sbx version verified

`v0.30.0` on macOS Apple Silicon. Agent: Claude Code v2.1.141.

## The task

The `payments-service` deployment is OOMKilling in the development cluster. On-call flagged repeated pod restarts overnight. The agent is given a task file and a set of manifests. No other context.

Full task: [`TASK.md`](./TASK.md)

## Setup

### Prerequisites

- `sbx` v0.30.0 installed and authenticated
- DevOps toolkit template: `shamsk22/sbx-devops-toolkit:v1.1.0` (built in [Lab 05](../../labs/05-devops-workloads/))
- A running Kubernetes cluster accessible from your machine
- `kubectl` working on your host: `kubectl get nodes`

### Step 1: Extract a sanitized kubeconfig

Extract only the current cluster context — not your full `~/.kube/config`:

```bash
kubectl config view --minify --flatten > scenarios/kubernetes-debugging/kubeconfig-dev.yaml
```

> ⚠️ This file contains embedded certificates. It is gitignored. Never commit it.

### Step 2: Update the kubeconfig server address

If your cluster API is on `127.0.0.1` (minikube default), the sandbox can't reach it directly — the sandbox has its own loopback. Replace with `host.docker.internal`:

```bash
# macOS (note: requires -i '' for BSD sed)
sed -i '' 's|https://127.0.0.1:<PORT>|https://host.docker.internal:<PORT>|g' \
  scenarios/kubernetes-debugging/kubeconfig-dev.yaml
```

Replace `<PORT>` with your actual API server port (`kubectl cluster-info` to find it).

Add TLS skip to the cluster entry (the cert is issued to `127.0.0.1`, not `host.docker.internal`):

```yaml
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://host.docker.internal:<PORT>
  name: <cluster-name>
```

### Step 3: Add network policy rules

The sandbox needs explicit permission to reach the host and the API server:

```bash
sbx policy allow network -g host.docker.internal
sbx policy allow network -g localhost:<PORT>   # your API server port
```

> **Why localhost?** The proxy resolves `host.docker.internal` to `localhost` internally and applies policy against `localhost:<PORT>`. Both rules are needed — adding only `host.docker.internal` is not sufficient.

> **Port changes on minikube restart:** minikube assigns a random high port at cluster creation (e.g. `57919`). If minikube restarts, the port changes. Check the current port with `kubectl cluster-info`, remove the old rule (`sbx policy remove <uuid>` — get the UUID from `sbx policy ls`), and add a new one.

> **Registry rules not needed:** `ghcr.io`, `registry-1.docker.io`, `auth.docker.io` are already covered by the default Balanced policy. Do not add them manually.

### Step 4: Run the sandbox

```bash
sbx run claude \
  --template shamsk22/sbx-devops-toolkit:v1.1.0 \
  --name kubernetes-debugging
```

### Step 5: Log in to Claude Code

Inside the Claude Code TUI (Terminal 1):

```
/login
```

Follow the device auth flow. Without login the agent accepts input but produces no output.

### Step 6: Deploy the broken manifests

In a second terminal:

```bash
sbx exec -it kubernetes-debugging bash
kubectl apply -f /Users/<user>/Source/docker-sandbox-devops/scenarios/kubernetes-debugging/manifests/ \
  --insecure-skip-tls-verify
kubectl get pods
```

Expected: pods enter `CrashLoopBackOff` within 30–60 seconds as the probe failures and resource limits take effect.

### Step 7: Give the agent the task

In Terminal 1 (Claude Code TUI):

```
Read /Users/<user>/Source/docker-sandbox-devops/scenarios/kubernetes-debugging/TASK.md
and complete the task. Use
KUBECONFIG=/Users/<user>/Source/docker-sandbox-devops/scenarios/kubernetes-debugging/kubeconfig-dev.yaml
and add --insecure-skip-tls-verify to all kubectl commands.
```

Let the agent run.

---

## What the agent did

The agent completed the task in 3 minutes 5 seconds. It identified **two bugs**, not one:

### Bug 1 — Memory limits too low (the planted bug)

```yaml
# Before
resources:
  requests:
    memory: "64Mi"
  limits:
    memory: "64Mi"   # OOMKill at peak load (~150Mi)
```

```yaml
# After
resources:
  requests:
    memory: "128Mi"
  limits:
    memory: "256Mi"
    cpu: "500m"
```

### Bug 2 — Probe misconfiguration (found independently)

```yaml
# Before — probes targeting wrong port and paths
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080      # nginx:alpine listens on 80, not 8080
readinessProbe:
  httpGet:
    path: /ready    # nginx:alpine only serves /
    port: 8080
```

```yaml
# After
livenessProbe:
  httpGet:
    path: /
    port: 80
readinessProbe:
  httpGet:
    path: /
    port: 80
```

The probe misconfiguration was causing `CrashLoopBackOff` before any memory pressure could develop. The agent caught it independently — it was not in the task description.

### Service fix

```yaml
# Before
targetPort: 8080

# After
targetPort: 80     # matched to corrected container port
```

### Cluster state after fix

```
NAME                                READY   STATUS    RESTARTS   AGE
payments-service-857cbdd94d-6hgnc   1/1     Running   0          40s
payments-service-857cbdd94d-7lt2g   1/1     Running   0          26s
```

Both pods stable, 0 restarts. Full findings in [`FINDINGS.md`](./FINDINGS.md) (written by the agent).

---

## What the isolation actually prevented

The agent had:
- ✅ Full access to `scenarios/kubernetes-debugging/` — read manifests, wrote FINDINGS.md
- ✅ `kubectl` access to the explicitly allowed cluster
- ✅ Ability to deploy, redeploy, describe pods, watch rollouts

The agent could NOT access:
- ❌ Other directories in the workspace outside the mounted path siblings
- ❌ Other kubeconfig contexts (only the one kubeconfig was in the workspace)
- ❌ `~/.aws`, `~/.ssh`, host credentials
- ❌ Other clusters not in the policy allowlist
- ❌ Arbitrary internet — only explicitly allowed domains

An agent running directly on the developer's machine would have had access to all of these.

---

## Friction log: what didn't work

This scenario required significant troubleshooting. The full log is in [`../../docs/friction-log.md`](../../docs/friction-log.md). Summary of what failed before the working setup was found:

**k3d inside the sandbox:** attempted first. The cluster creation hangs indefinitely. The k3s containers started by the sandbox's private Docker daemon have no proxy configuration — they cannot reach external endpoints during initialization. Not viable without significant additional configuration.

**`host.docker.internal` network policy:** needed explicitly. Even though `host.docker.internal` appears in Docker networking documentation, it is not in the Balanced allowlist by default. Must be added manually.

**`localhost:<PORT>` network policy:** the proxy resolves `host.docker.internal` to `localhost` and applies policy against the resolved address. Adding only `host.docker.internal` is insufficient — the port-specific `localhost:<PORT>` rule is also required.

**TLS verification:** minikube's certificate is issued to `127.0.0.1`. When connecting via `host.docker.internal`, TLS verification fails. `--insecure-skip-tls-verify` or `insecure-skip-tls-verify: true` in the kubeconfig is required.

**macOS `sed` syntax:** macOS BSD `sed` requires `-i ''` (empty string argument). `sed -i 's/...'` without the empty string fails with "unescaped newline inside substitute pattern".

**Claude Code login:** the agent TUI accepts input while not logged in but produces no output. `/login` must be run before giving the agent any task.

**Policy rule removal syntax:** `sbx policy deny` does NOT remove an existing allow rule — it adds a conflicting deny rule and errors. `sbx policy rm network -g --resource <host>` or `sbx policy rm network -g --id <uuid>` is the correct removal command. `sbx policy ls` shows UUIDs. This is not obvious from the CLI help.

---

## Cleanup

```bash
# Remove the deployment from the cluster
kubectl delete -f /Users/<user>/Source/docker-sandbox-devops/scenarios/kubernetes-debugging/manifests/ \
  --insecure-skip-tls-verify

# Remove the sandbox
sbx rm kubernetes-debugging

# Remove the kubeconfig (gitignored but clean up anyway)
rm scenarios/kubernetes-debugging/kubeconfig-dev.yaml

# Remove the network policy rules added for this scenario
sbx policy rm network -g --resource host.docker.internal
sbx policy rm network -g --resource localhost:<PORT>

# Verify rules removed
sbx policy ls
```