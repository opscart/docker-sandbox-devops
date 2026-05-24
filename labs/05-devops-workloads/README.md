# Lab 05: DevOps Workloads

## Objective

Build a custom Docker Sandbox template with a pinned DevOps toolchain (kubectl, helm, kustomize, azure-cli), run it as a sandbox, verify the tools, and configure network policy for Kubernetes cluster access. Demonstrates how custom templates give reproducible, version-pinned environments without polluting the host.

## sbx version verified

`v0.30.0` on macOS Apple Silicon. See [`../../tested-with.md`](../../tested-with.md).

## Prerequisites

- Labs 01–04 completed
- Docker Desktop running on the host (required for `docker build` and `docker push`)
- Docker Hub account (free tier works)
- `sbx` installed and authenticated

## Background: templates vs default sandbox

The default `sbx run claude` uses `docker/sandbox-templates:claude-code-docker` — a minimal base with Claude Code, curl, dig, and basic Linux tools. It has no Kubernetes or cloud CLIs.

Custom templates extend this base. You build a Docker image, push it to a registry, and pass it to `sbx run --template`. The sandbox uses your image as its root filesystem. Tools baked into the image are available immediately — no runtime installation, no network policy exceptions for package registries during agent execution.

Benefits over installing tools at runtime:
- Reproducible: pinned versions, same environment every run
- Faster startup: no apt-get or pip install on sandbox creation
- Cleaner network policy: install-time network access happens during `docker build` on the host, not inside the sandbox

## Template Dockerfile

The Dockerfile lives at [`../../templates/dev-environment/Dockerfile`](../../templates/dev-environment/Dockerfile). Key design decisions:

- Extends `docker/sandbox-templates:claude-code-docker` — inherits the base OS, agent user, and proxy configuration
- Build ARGs pin tool versions for reproducibility
- Architecture is auto-detected at build time (`uname -m`) — image works on both arm64 and amd64
- kustomize uses direct GitHub release download — the official install script fails silently on ARM64 (see [`../../docs/friction-log.md`](../../docs/friction-log.md))
- Smoke test in the final RUN layer confirms all four tools are on PATH before the image is pushed

## Steps

### Step 1: Build the template image

From the repo root, with Docker Desktop running:

```bash
docker build \
  --platform linux/arm64 \
  -t shamsk22/sbx-devops-toolkit:v1.0.0 \
  templates/dev-environment/
```

Expected build time: ~2 minutes. azure-cli is the slow step (~51 seconds).

Build output confirms each layer:

```
[2/7] RUN apt-get update ...                                   10.3s
[3/7] RUN ... kubectl ...                                      11.9s
[4/7] RUN ... helm ...                                          4.1s
[5/7] RUN ... kustomize ...                                     1.6s
[6/7] RUN ... azure-cli ...                                    51.2s
[7/7] RUN kubectl version ... helm version ... kustomize ...    3.6s
```

Layer 7 is the smoke test — if any tool is missing from PATH the build fails here, not at runtime.

### Step 2: Push to Docker Hub

```bash
docker login   # authenticates with your Docker Hub credentials
docker push shamsk22/sbx-devops-toolkit:v1.0.0
```

> **Image naming:** tag must match your Docker Hub username, not your GitHub org handle. `opscart/sbx-devops-toolkit` fails if `opscart` is not a Docker Hub org you own. To use the `opscart` namespace, create the org at hub.docker.com first.

### Step 3: Run the sandbox with the custom template

```bash
sbx run claude \
  --template shamsk22/sbx-devops-toolkit:v1.0.0 \
  --name 05-devops-workloads
```

Real output:

```
Creating new sandbox '05-devops-workloads'...
723fcd1034df: Download complete
...
Status: Downloaded newer image for shamsk22/sbx-devops-toolkit:v1.0.0
INFO: Configuring Docker
✓ Created sandbox '05-devops-workloads'
  Workspace: /Users/opscart/Source/docker-sandbox-devops (direct mount)
  Agent: claude
INFO: Started Docker daemon in 1.1s
Starting claude agent in sandbox '05-devops-workloads'...
```

### Step 4: Verify the toolchain

Open a shell inside the sandbox:

```bash
sbx exec -it 05-devops-workloads bash
```

Run verification:

```bash
echo "=== TOOL VERSIONS ==="
kubectl version --client --output=json | python3 -c "import sys,json; d=json.load(sys.stdin); print('kubectl:', d['clientVersion']['gitVersion'])"
helm version --short
kustomize version
az version --output table 2>/dev/null | head -6

echo "=== BINARIES ==="
which kubectl && which helm && which kustomize && which az

echo "=== ENVIRONMENT ==="
uname -m
cat /etc/os-release | grep PRETTY_NAME
```

Real output:

```
=== TOOL VERSIONS ===
kubectl: v1.31.4
v3.16.4+g7877b45
v5.4.3
Azure-cli    Azure-cli-core    Azure-cli-telemetry
-----------  ----------------  ---------------------
2.86.0       2.86.0            1.1.0

=== BINARIES ===
/usr/local/bin/kubectl
/usr/local/bin/helm
/usr/local/bin/kustomize
/usr/bin/az

=== ENVIRONMENT ===
aarch64
PRETTY_NAME="Ubuntu 25.10"
```

All four tools confirmed. `az` installs to `/usr/bin/` (Microsoft's install location); the others go to `/usr/local/bin/`.

## Tool versions: sandbox vs host

| Tool | Sandbox (pinned) | Notes |
|---|---|---|
| kubectl | v1.31.4 | Pinned via `ARG KUBECTL_VERSION` |
| helm | v3.16.4 | Pinned via `ARG HELM_VERSION` |
| kustomize | v5.4.3 | Pinned via `ARG KUSTOMIZE_VERSION` |
| azure-cli | 2.86.0 | Latest at build time (Microsoft's script) |
| OS | Ubuntu 25.10 (aarch64) | Always Linux regardless of macOS host |

The sandbox always runs Linux/ARM64 on Apple Silicon — even though your host is macOS. Any tools installed at build time must be Linux binaries. macOS binaries will not work inside the sandbox.

## Network policy for Kubernetes cluster access

The Balanced policy blocks arbitrary internet traffic. To use `kubectl` against a real cluster, the cluster's API server FQDN must be explicitly allowed.

From the **host** (not inside the sandbox):

```bash
# Get your cluster API server address first
# AKS example:
sbx policy allow network -g <cluster-name>.hcp.<region>.azmk8s.io

# Verify the rule was added
sbx policy ls
```

Then inside the sandbox:

```bash
# Authenticate to Azure
az login --use-device-code

# Pull kubeconfig
az aks get-credentials \
  --resource-group <resource-group> \
  --name <cluster-name>

# Verify cluster access
kubectl get nodes
kubectl get namespaces
```

> **Note:** `az login --use-device-code` works inside the sandbox because `login.microsoftonline.com` is in the Balanced allowlist. The device code flow opens a browser on the host for authentication — the sandbox does not need direct browser access.

## Observations

### 1. The template is the reproducibility unit

A custom template pins the exact toolchain. Every engineer who runs `sbx run --template shamsk22/sbx-devops-toolkit:v1.0.0` gets kubectl v1.31.4, helm v3.16.4, kustomize v5.4.3 — regardless of what's installed on their host. No "works on my machine" for the DevOps toolchain.

### 2. Build on host, run in sandbox

`docker build` runs on the host Docker Engine with unrestricted network access. Install scripts, apt packages, and GitHub release downloads all work without sandbox network policy exceptions. The sandbox only pulls the finished image from a registry.

This is the correct mental model: the template build is a CI-like step; the sandbox run is the execution environment.

### 3. azure-cli dominates build time

51 of 131 seconds in the build are azure-cli. If iteration speed on the Dockerfile matters, comment out the azure-cli step while developing, add it back for the final image. Alternatively, pin azure-cli to a specific version in the Microsoft install script to enable layer caching.

### 4. kustomize official install script fails on ARM64

The script at `raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh` fails inside a Docker build on ARM64 — it downloads a tarball but the glob pattern fails to find it. Direct download from GitHub releases with a pinned version is reliable. See [`../../docs/friction-log.md`](../../docs/friction-log.md).

### 5. Network policy is additive per session

`sbx policy allow` adds rules that apply to all sandboxes for the current user. Adding a cluster FQDN to the allowlist means all subsequent sandboxes can reach it — not just the one you're working in. Audit your policy rules with `sbx policy ls` and remove rules that are no longer needed with `sbx policy deny`.

## Upgrading the toolchain

To update tool versions, change the ARG values in the Dockerfile and rebuild:

```bash
# Edit Dockerfile — bump KUBECTL_VERSION, HELM_VERSION, KUSTOMIZE_VERSION
docker build \
  --platform linux/arm64 \
  --no-cache \
  -t shamsk22/sbx-devops-toolkit:v1.1.0 \
  templates/dev-environment/
docker push shamsk22/sbx-devops-toolkit:v1.1.0
```

Use `--no-cache` when upgrading to force all layers to rebuild. Tag with a new version — don't overwrite `:v1.0.0` in place, so existing sandboxes remain reproducible.

## Cleanup

```bash
exit   # exit sandbox shell
sbx rm 05-devops-workloads
```

## What's next

With five labs complete, the next layer is scenarios — integrated workflows that combine what the labs demonstrated individually. Start with [`../../scenarios/multi-agent-orchestration/`](../../scenarios/multi-agent-orchestration/) for true VM-level agent isolation using separate workspace directories.