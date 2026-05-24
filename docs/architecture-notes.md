# Architecture Notes

Observations about how Docker Sandboxes works internally, synthesized from hands-on exploration across Labs 01–05. All claims are based on real terminal output — not documentation alone.

> **sbx version:** v0.30.0. Early Access product; architecture may change between releases.

---

## The runtime model: microVM, not container

Docker Sandboxes does not use Linux containers (namespaces + cgroups) to isolate agents. Each sandbox runs inside a dedicated microVM with its own Linux kernel. Docker built a custom VMM (virtual machine monitor) to run these microVMs cross-platform — macOS, Windows, and Linux. Unlike Firecracker, which is Linux-only, Docker's VMM runs natively on macOS without requiring Linux as the host.

Evidence: inside the sandbox, `cat /etc/os-release` returns `Ubuntu 25.10` regardless of the macOS host. `uname -m` returns `aarch64` on Apple Silicon. The guest OS is always Linux.

---

## Four isolation layers

### 1. Hypervisor isolation
Each sandbox has its own Linux kernel. A kernel exploit inside the sandbox cannot reach the host kernel or other sandboxes.

### 2. Network isolation
All outbound HTTP/HTTPS traffic routes through a host-side proxy at `gateway.docker.internal:3128`. The proxy enforces the active network policy. Non-HTTP protocols (raw TCP, UDP, ICMP) are blocked at the network layer — with one exception: HTTP CONNECT tunneling (see Proxy Behavior below).

### 3. Docker daemon isolation
Each sandbox runs a private Docker Engine (`dockerd` + `containerd`) inside the microVM. From Lab 03:

```
root  1228  dockerd
root  1240  containerd --config /var/run/docker/containerd/containerd.toml
```

The Docker socket at `/var/run/docker.sock` inside the sandbox belongs to the sandbox's own daemon (created at sandbox start time). There is no path to the host Docker daemon. Agents can run `docker build`, `docker run`, and `docker compose` without socket mounting or host privilege escalation.

### 4. Credential isolation
API keys and tokens are not injected into the sandbox environment. `env | grep -iE "api_key|anthropic|secret|token|password"` returns empty. Instead, the host-side proxy injects credentials into outbound HTTP headers at the proxy layer. The sandbox environment exposes the proxy address but not the credentials it carries:

```
https_proxy=http://gateway.docker.internal:3128
NODE_USE_ENV_PROXY=1
JAVA_TOOL_OPTIONS=-Dhttp.proxyHost=gateway.docker.internal -Dhttp.proxyPort=3128 ...
```

---

## The gateway.docker.internal bridge

`gateway.docker.internal` is the host-side bridge between the microVM and permitted host services. Two ports observed:

| Port | Purpose |
|---|---|
| 3128 | HTTP/HTTPS proxy — enforces network policy, injects credentials |
| 3129 | SSH agent forwarder — bridges `/run/ssh-agent.sock` inside the sandbox to the host SSH agent |

The SSH agent bridge runs via `socat` inside the sandbox (observed in Lab 03):

```
root  1196  socat UNIX-LISTEN:/run/ssh-agent.sock,fork,mode=666 TCP:gateway.docker.internal:3129
```

This allows agents to use SSH keys from the host keychain (for git operations over SSH, for example) without the raw key material ever entering the sandbox.

---

## Proxy behavior: what the network policy actually enforces

From Lab 02 probes against the Balanced policy:

**Blocking mechanism is HTTP 403, not TCP failure.** Every blocked request returns `exit=0, http=403`. The proxy intercepts the request and returns 403 without forwarding. From the agent's perspective, a blocked domain and a server-side 403 look identical by exit code.

**HTTP CONNECT tunneling allows raw TCP to allowed domains on any port.** When `curl telnet://github.com:22` runs inside the sandbox, it sends an HTTP CONNECT request to the proxy. The proxy evaluates the target hostname against the allowlist. Since `github.com` is allowed, the proxy permits the tunnel — on any port. Raw TCP to `github.com:22` connected successfully. The Balanced policy is hostname-scoped, not protocol+port-scoped.

**DNS is not policy-filtered.** The microVM has an internal stub resolver that forwards DNS queries independently of the HTTP proxy. Both allowed and blocked domains resolve successfully. DNS cannot serve as an enforcement layer.

**Network policy tiers:**

| Policy | HTTP/HTTPS | DNS | Raw TCP to allowed host |
|---|---|---|---|
| Open | All allowed | Unfiltered | Allowed via CONNECT |
| Balanced | Allowlist only — 403 for others | Unfiltered | Allowed via CONNECT (if host in allowlist) |
| Locked Down | Blocked unless explicitly allowed | Unfiltered | Blocked (host not in allowlist) |

---

## Filesystem mount: path-scoped, not home-scoped

The workspace directory is mounted into the sandbox at the same absolute path as on the host. From Lab 03, the workspace was `/Users/opscart/Source/docker-sandbox-devops`. Inside the sandbox:

```
/Users/opscart/Source/docker-sandbox-devops  → full read-write access (workspace)
/Users/opscart/                              → stub, shows only "Source"
/Users/                                      → stub, shows only "opscart"
/Users/opscart/.ssh/                         → No such file or directory
```

The mount creates minimal parent directory stubs along the workspace path. Siblings at each level are not exposed. The host home directory, SSH keys, and other user directories are not accessible.

**Important:** if the workspace is set to the home directory (`~/`), all home directory contents are visible inside the sandbox. Always mount a project subdirectory.

---

## Process namespace

The sandbox has its own PID namespace. Only sandbox-internal processes are visible (12 total in Lab 03). The process table reveals the internal stack:

| Process | Role |
|---|---|
| `tini` (PID 1) | Minimal init — signal forwarding, zombie reaping |
| `dockerd` | Sandbox-private Docker Engine |
| `containerd` | Sandbox container runtime |
| `socat` | SSH agent bridge to host |
| `claude --dangerously-skip-permissions` | Coding agent |

The agent runs as user `agent` (non-root). `--dangerously-skip-permissions` is applied by the default template automatically.

---

## Sandbox lifecycle

From Labs 01 and 02, confirmed behavior:

```
sbx run claude        → starts daemon if not running, creates sandbox, attaches agent
sbx rm <name>         → removes sandbox, microVM, and all associated worktrees
sbx daemon start      → foreground mode, streams JSON logs, blocks terminal (debug use only)
sbx daemon stop       → clean stop; subsequent sbx version reports server as Unavailable
sbx version           → server shows Unavailable when daemon is not running (expected, not an error)
```

The daemon persists sandbox state across restarts. On daemon restart, it re-injects the proxy and SSH agent forwarder for all previously running sandboxes:

```json
{"msg":"re-injected proxy for loaded runtime","runtime":"claude-12-docker-hardened-images"}
```

From v0.30.0: a configurable grace period delays auto-stop when the last agent session exits. In v0.29.0, stop was immediate.

---

## Branch mode and worktrees (Lab 04)

`--branch` creates Git worktrees — it does not create a separate microVM. Both agents share the same sandbox (one microVM, one Docker daemon, one network stack). Isolation is Git-level: separate branches, separate filesystem trees.

Worktree path convention:
```
.sbx/<sandbox-name>-worktrees/<branch-name>/
```

One sandbox per workspace directory. A second `sbx run --name <new>` in the same directory fails — `sbx` enforces one sandbox per workspace. Additional branches attach to the existing sandbox.

`sbx rm` on the parent sandbox removes all worktrees.

---

## Custom templates (Lab 05)

Templates are Docker images extending `docker/sandbox-templates:claude-code-docker`. Build on the host with standard `docker build` (unrestricted network, standard Docker Engine). Push to a registry. Run with `--template <image>`.

The sandbox always runs as Linux/ARM64 on Apple Silicon — macOS binaries do not work inside. Build with `--platform linux/arm64` explicitly.

Build time is dominated by heavy dependencies (azure-cli: ~51 seconds in a 131-second total build). Pin versions via ARG for reproducibility. Use direct GitHub release downloads for tools whose install scripts are unreliable on ARM64 (kustomize is a confirmed case — see `docs/friction-log.md`).