# Comparison Notes

## `docker run` vs `sbx run` — verified from lab findings

This comparison is based entirely on observations from Labs 01–05 and the kubernetes-debugging scenario. No claims are made that weren't directly tested.

---

### Isolation model

| | `docker run` | `sbx run` |
|---|---|---|
| Isolation boundary | Linux namespaces + cgroups — shared host kernel | microVM — separate kernel per sandbox |
| Docker inside | Requires host socket mount (`-v /var/run/docker.sock`) or DinD workaround — defeats isolation | Private Docker Engine per sandbox, no socket mount needed (confirmed Lab 03) |
| Host processes visible | Depends on PID namespace flags | Not visible — 12 sandbox-internal processes only (confirmed Lab 03) |
| Host filesystem | Controlled via volume mounts | Workspace mounted at same absolute path; parent stubs only — siblings not exposed (confirmed Lab 03) |

### Credential handling

| | `docker run` | `sbx run` |
|---|---|---|
| API keys | Passed via `-e` env vars or `.env` file — visible inside container | Injected at proxy layer — never in sandbox environment (confirmed Lab 03) |
| Proxy address | Not provided | Visible as `https_proxy=http://gateway.docker.internal:3128` — address exposed, credentials not |
| SSH agent | Manual socket mount | Bridged via `socat` to `gateway.docker.internal:3129` (confirmed Lab 03 process list) |

### Network policy

| | `docker run` | `sbx run` |
|---|---|---|
| Default outbound | All traffic allowed unless iptables rules added manually | Default deny with curated dev allowlist (Balanced) |
| Blocking mechanism | iptables DROP — connection times out | HTTP 403 from proxy — instant response (confirmed Lab 02) |
| DNS | Unfiltered | Unfiltered — DNS not policy-controlled (confirmed Lab 02) |
| Raw TCP to allowed hosts | Allowed | Allowed via HTTP CONNECT tunneling on any port (confirmed Lab 02: github.com:22 connected) |

### Developer experience

| | `docker run` | `sbx run` |
|---|---|---|
| Coding agent support | Generic — no agent-specific tooling | Claude Code, Copilot, Gemini CLI templates built-in |
| Permission flags | Manual | Template applies `--dangerously-skip-permissions` automatically (confirmed Lab 03) |
| Cross-platform | Linux native; macOS via Docker Desktop VM layer | Native microVM on macOS, Windows, Linux |
| Custom toolchain | Standard Dockerfile | Standard Dockerfile extending `docker/sandbox-templates:claude-code-docker` (built Lab 05) |
| Parallel workspaces | Separate containers manually managed | `--branch` mode creates Git worktrees within one sandbox (confirmed Lab 04) |

### What `docker run` does better

- No additional product to install — Docker is already present in most dev environments
- No subscription requirement
- More flexible runtime configuration — full Docker flags available
- Wider ecosystem familiarity

### What `sbx run` does better

- Private Docker Engine per sandbox — agents can run `docker build` without host socket mount
- Credential injection at proxy layer — API keys never enter the sandbox environment
- Network policy out of the box — no manual iptables configuration
- Purpose-built for coding agents — templates, kits, `--branch` mode

### The core difference in practice

`docker run` gives process-level isolation. For most workloads that is sufficient. For AI coding agents specifically, the gap matters: agents routinely need to build and run Docker containers themselves. With `docker run`, that forces a host socket mount — which grants the agent full control of the host Docker daemon. The isolation is gone.

`sbx run` gives each sandbox its own Docker Engine. The agent gets full Docker capabilities without any path to the host daemon. This is the architecturally significant difference for the coding agent use case.

---

> **Scope note:** This comparison covers `docker run` for local agent execution only.
> Cloud-hosted sandbox platforms (E2B, Modal, Daytona, Cloudflare Sandboxes) solve
> a different problem — agent code execution on remote infrastructure — and are
> out of scope for this comparison.