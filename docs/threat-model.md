# Threat Model

What Docker Sandboxes protects against, what it partially protects, and what it does not protect — based on real probe results from Labs 02–03. No documentation claims without supporting evidence.

> **Scope:** local sandbox running on a developer laptop with an AI coding agent. Not a cloud deployment model.

---

## What is protected

### Host process namespace
The sandbox has its own PID namespace. Host processes are invisible from inside the sandbox. An agent cannot enumerate, signal, or interact with host processes.

**Evidence:** Lab 03 `ps aux` returned 12 sandbox-internal processes. No host processes visible.

### Host Docker daemon
The sandbox has a private Docker Engine. The host's Docker socket is not mounted, not accessible, not visible. An agent running `docker ps` inside the sandbox sees only the sandbox's own containers.

**Evidence:** Lab 03 `docker info` returned a unique daemon ID, Docker version 29.4.3, Ubuntu 25.10 — distinct from host. `DOCKER_HOST` is empty. Socket created at sandbox start time.

### Raw API credentials
API keys are not injected into the sandbox environment. The proxy holds credentials on the host and injects them into outbound HTTP headers. A fully compromised sandbox cannot exfiltrate raw credential values.

**Evidence:** Lab 03 `env | grep -iE "api_key|anthropic|secret|token|password"` returned empty. Proxy address (`gateway.docker.internal:3128`) is visible; credentials are not.

### Host filesystem outside workspace siblings
Only the workspace path and its minimal parent stubs are visible. Sibling directories at each level (other home directories, `Desktop`, `Downloads`, `.ssh`) are not accessible.

**Evidence:** Lab 03 — `/Users/opscart/` showed only `Source`. `/Users/opscart/.ssh/` returned `No such file or directory`.

### Host network services via localhost
`localhost` inside the sandbox resolves to the sandbox's own loopback interface. Host services (SSH on port 22, Kubernetes API on port 6443, local web servers) are not reachable via localhost.

**Evidence:** Lab 03 — `curl localhost:22` and `curl localhost:6443` both returned `exit=7` (connection refused — nothing listening in the sandbox).

---

## What has nuance

### Filesystem: workspace parent stubs are partially visible

The workspace mount creates read-only parent directory stubs up to the filesystem root. `/Users/<username>/` is visible but shows only the subdirectory in the mount path. The stubs themselves cannot be written to, and their siblings are not visible.

**Risk:** if the workspace directory is a user's home directory, the full home is visible and writable inside the sandbox. Always mount a project subdirectory, not a parent directory.

### Network: HTTP CONNECT tunneling allows non-standard ports to allowed domains

Blocked by policy: arbitrary internet access. Not blocked: raw TCP connections to Balanced-allowlist domains on non-standard ports, when routed via HTTP CONNECT through the proxy.

**Evidence:** Lab 02 — `curl telnet://github.com:22` connected. `github.com` is in the Balanced allowlist; the proxy allowed the CONNECT tunnel to port 22.

**Practical implication:** an agent on Balanced policy has SSH access to `github.com`. For most workflows this is useful. For threat modelling, the network surface is hostname-scoped, not hostname+port-scoped.

### Credentials: proxy address is visible

The proxy endpoint (`gateway.docker.internal:3128`) is in the sandbox environment as `https_proxy`. An agent knows it is being proxied. It cannot see the credentials, but it can observe that traffic is routed and theoretically craft requests to probe the proxy behavior.

### Sandbox auto-stop and session persistence (v0.30.0)

In v0.30.0, sandboxes have a configurable grace period before auto-stopping after the last session exits. During this window the microVM is still running even though no agent is attached. A sufficiently long grace period combined with the workspace mount means host files remain accessible to the still-running sandbox without an active agent session.

---

## What is not protected

### DNS resolution

DNS queries are not policy-filtered. Both allowed and blocked domains resolve successfully from inside the sandbox. The microVM has an internal stub resolver that forwards queries independently of the HTTP proxy policy.

**Evidence:** Lab 02 — `dig example.com +short` resolved to `172.66.147.243`, `104.20.23.154` even though HTTP access to `example.com` returns 403.

**Implication:** an agent can probe which domains exist (DNS resolution) regardless of HTTP policy. DNS cannot be used as a secondary enforcement layer.

### Workspace contents at the time of mounting

The workspace directory is mounted with read-write access. The agent has full read-write access to everything under the workspace path. Destructive operations (`rm -rf`, overwriting files, modifying configs) inside the workspace affect the host filesystem in real time. There is no snapshot, undo, or write barrier.

**Mitigation:** use `--branch` mode to work on a Git worktree rather than the main branch directly. Commit frequently. The sandbox does not replace version control discipline.

### Cross-agent contamination within the same sandbox

Two agents using `--branch` on the same workspace share one microVM, one Docker daemon, and one network stack. A compromised or misbehaving agent in one worktree has full access to the other worktree's filesystem. The isolation between `--branch` agents is Git-level only.

**Evidence:** Lab 04 — both agents ran inside sandbox `04-agent-a`. The Docker daemon, network proxy, and process namespace were shared.

**Mitigation:** for true agent isolation, use separate workspace directories (separate microVMs). See `scenarios/multi-agent-orchestration/`.

### Agent-initiated microVM escape

Not tested in this repo. Docker Sandboxes is Early Access and the VMM implementation has not been audited publicly. The microVM boundary provides significantly stronger isolation than containers, but microVM escape vulnerabilities exist in practice (as documented in Firecracker CVEs). Do not treat the sandbox as an absolute security boundary against a sufficiently motivated and capable adversary.

---

## Summary table

| Threat | Protected? | Notes |
|---|---|---|
| Agent reads host processes | ✅ Yes | PID namespace isolated |
| Agent reads host Docker daemon | ✅ Yes | Private daemon per sandbox |
| Agent exfiltrates raw API keys | ✅ Yes | Credentials never in sandbox env |
| Agent reads `~/.ssh` | ✅ Yes | Not in mount path |
| Agent reaches host SSH on localhost | ✅ Yes | Sandbox localhost only |
| Agent reaches arbitrary internet | ✅ Yes (Balanced/Locked) | Proxy blocks and returns 403 |
| Agent destroys workspace files | ❌ No | Full R/W to workspace mount |
| Agent resolves arbitrary DNS | ❌ No | DNS not policy-filtered |
| Agent SSHs to allowed domain | ⚠️ Partial | HTTP CONNECT tunnels any port |
| Agent sees proxy address | ⚠️ Partial | Address visible, credentials not |
| Two --branch agents isolated | ⚠️ Partial | Git-level only, shared microVM |
| Home directory exposed | ⚠️ Risk | If workspace = home dir |