# Docker Sandboxes: Engineering Overview

> **Scope:** This document reflects observations as of May 2026 against `sbx` v0.29.0. Architecture and feature details may change in subsequent releases. See [`../tested-with.md`](../tested-with.md) for current verification status.

## What it is

Docker Sandboxes provide microVM-isolated environments for running AI coding agents on a developer's local machine. Each sandbox runs in a dedicated microVM with its own Linux kernel, its own Docker daemon, its own network stack, and its own filesystem — isolated from the host and from other sandboxes.

The CLI is `sbx`, distributed separately from Docker Desktop. It's installable standalone on macOS (Homebrew), Windows (winget), and Linux (Ubuntu via deb/rpm with KVM).

The product is **Early Access** as of this writing. Free for individuals; org-level admin features (centrally managed network and filesystem policies via Docker Admin Console) require a paid subscription.

## What problem it solves

AI coding agents are increasingly run with permission-skipping flags (`--dangerously-skip-permissions`, "YOLO mode") for productivity. On a developer laptop, the agent can install packages, modify configs, delete files, execute scripts, and make arbitrary network requests with the developer's full user privileges.

Existing alternatives and their trade-offs:

- **No sandbox.** Fast. The blast radius of one wrong command is the entire developer machine.
- **Plain Docker container.** Process-level isolation; shared kernel. Coding agents routinely need to build and run Docker containers themselves, which forces socket mounting (`-v /var/run/docker.sock`) — defeating the isolation. OS mismatch with macOS-native dev workflows.
- **Full VM (UTM, Parallels, Multipass).** Strong isolation, heavy cold-start cost, resource overhead that discourages routine use.
- **OS-level sandboxing (`sandbox-exec`, Apple Containers, Linux namespaces).** Fragmented across platforms; not designed for full development environments.

Docker Sandboxes aims for VM-grade isolation with container-grade startup, working identically across macOS, Windows, and Linux.

## Architecture in one paragraph

A Docker-built virtual machine monitor (a custom VMM — **not** Firecracker, since Firecracker is Linux-only) runs one microVM per sandbox. Inside the microVM lives the agent runtime, the workspace (mounted via filesystem passthrough at the same absolute path as on the host), and a private Docker daemon. Outbound HTTP/HTTPS traffic from the sandbox routes through a proxy on the host. The proxy enforces network policies and injects credentials into outbound requests at the proxy layer — credentials never enter the microVM. Raw TCP, UDP, and ICMP are blocked at the network layer; only HTTP/HTTPS through the proxy works.

## Four isolation layers

1. **Hypervisor isolation.** Each sandbox has its own Linux kernel. A kernel exploit inside the sandbox does not reach the host kernel or other sandboxes.
2. **Network isolation.** All HTTP/HTTPS traffic is proxied through the host. Non-HTTP protocols are blocked entirely. Network policies (Open / Balanced / Locked Down) are enforced at the proxy.
3. **Docker Engine isolation.** Each sandbox has its own Docker Engine inside the microVM. No path to the host Docker daemon. The agent gets full `docker build`, `docker run`, and `docker compose` without socket mounting or host privilege escalation.
4. **Credential isolation.** API keys are stored in the host OS keychain. The host-side proxy injects them into outbound HTTP headers. Raw credential values never enter the microVM, even if the agent is fully compromised.

Inside the microVM, the agent has full privileges: sudo access, package installation, a private Docker Engine, and read-write access to the workspace.

## Key terms

| Term | Meaning |
|---|---|
| `sbx` | The CLI binary. |
| `sandboxd` | Local daemon managing microVMs. Auto-starts on `sbx login` or `sbx run`; explicit start via `sbx daemon start`. |
| Sandbox (microVM) | A single isolated VM running one agent and its workspace. |
| Template | A Docker image used as the sandbox's base. Built ahead of time, pulled at sandbox creation. |
| Kit | Declarative YAML artifact (mixin or agent) applied at sandbox creation. Adds tools, files, credentials, and network rules. |
| Branch mode (`--branch`) | Creates a Git worktree per sandbox so multiple agents can work on the same repo without conflict. Worktrees live under `.sbx/`. |
| Service domain | Kit-level mechanism mapping a hostname to a credential injection rule. |
| Workspace | The host directory mounted into the sandbox at the same absolute path. |

## Network policies

| Policy | Behavior |
|---|---|
| Open | All HTTP/HTTPS allowed. Raw TCP/UDP/ICMP still blocked. |
| Balanced (default) | Default deny; curated allowlist of common dev sites (npm, PyPI, GitHub, AI model providers, etc.). |
| Locked Down | Default deny; even model provider APIs blocked unless explicitly allowed. |

Manage rules with:

```bash
sbx policy ls                          # show active rules
sbx policy allow network -g <host>     # allow a host
sbx policy deny network -g <host>      # block a host
sbx policy reset                       # interactive default policy reset
```

## Customization: templates vs kits

**Templates** are Docker images. Build with a Dockerfile that extends `docker/sandbox-templates:<variant>`, push to a registry, reference with `sbx run --template <image>`. Use for heavy dependencies that should be baked ahead: system packages, language toolchains, large CLIs.

**Kits** are declarative YAML applied at sandbox creation. Two kinds:

- **Mixin kit** (`kind: mixin`) — extends an existing agent with extra capabilities. Stack several on the same sandbox.
- **Agent kit** (`kind: agent`) — defines a full agent from scratch: image, entrypoint, network policies.

Kits run install commands, drop files into the sandbox, declare network and credential rules. Pass them with `--kit <path-or-url>` to `sbx run` or `sbx create`.

Templates + kits compose: a heavy template bakes the base environment for fast startup; thin kits layer per-run credentials, config, or extra capabilities.

Community kits live at [`docker/sbx-kits-contrib`](https://github.com/docker/sbx-kits-contrib).

## What this overview doesn't cover

- Concrete commands and walkthroughs → [`../labs/01-install-and-first-run/`](../labs/01-install-and-first-run/)
- Security boundaries and what's *not* protected → [`./threat-model.md`](./threat-model.md) (forthcoming)
- Where it sits vs E2B, Modal, Daytona, etc. → [`./comparison-notes.md`](./comparison-notes.md) (forthcoming)
- Real-world friction → [`./friction-log.md`](./friction-log.md)