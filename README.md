# docker-sandbox-devops

A practical engineering exploration of [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) for running AI coding agents in isolated microVMs on a developer's laptop.

> **Status:** Exploration-grade. Docker Sandboxes is itself an Early Access product as of May 2026 — features and APIs may change between releases. Pinned versions are tracked in [`tested-with.md`](./tested-with.md). This repo is independent and not affiliated with Docker, Inc.

## Why this repo exists

AI coding agents like Claude Code, Codex, Gemini CLI, Copilot CLI, Kiro, and OpenCode are increasingly run with permission-skipping flags on developer machines. On a laptop, that means the agent can install packages, modify configs, delete files, and execute arbitrary commands with full user privileges. The blast radius of one mistake is the entire developer environment.

Existing alternatives have trade-offs:

- **No sandbox** — fast, dangerous.
- **Plain Docker container** — shared kernel; running Docker inside requires socket mounting, which defeats isolation.
- **Full VM** — strong isolation, heavy cold-start, discourages routine use.
- **OS-level sandboxing** — fragmented across platforms.

Docker Sandboxes targets this gap with cross-platform microVMs and a per-sandbox Docker daemon. This repo evaluates it from a DevOps and platform engineering perspective — what works, what breaks, and what patterns emerge in real use.

## What's in scope

- Reproducible labs walking through install, network policy verification, isolation probes, parallel coding-agent workflows, and custom DevOps environments
- Scenarios demonstrating integrated workflows (multi-agent orchestration, Kubernetes debugging, CI/CD experimentation)
- A reusable Kubernetes kit and a DevOps template
- Architecture notes, threat model, and a live friction log
- Vendor-neutral comparison with adjacent tools

## What's not in scope

- A replacement for cloud-hosted sandboxes (E2B, Modal, Daytona, Cloudflare Sandboxes) — those solve a different problem
- Production deployment patterns — the product is Early Access; nothing here should be treated as stable
- Marketing claims about Docker Sandboxes

## Who this is for

- DevOps and platform engineers evaluating local sandboxing for AI coding agents
- Engineers running coding agents unattended and looking for guardrails
- Researchers comparing microVM-based isolation to alternatives

## Repo layout

```
docker-sandbox-devops/
├── docs/
│   ├── 00-overview.md         # what Docker Sandboxes is, at engineering depth
│   ├── architecture-notes.md  # microVM, proxy, credential flow observations
│   ├── threat-model.md        # what's protected, what isn't
│   ├── comparison-notes.md    # honest comparison with adjacent tools
│   └── friction-log.md        # dated, real-time capture of what broke
├── labs/
│   ├── 01-install-and-first-run/
│   ├── 02-network-policy-probes/
│   ├── 03-isolation-verification/
│   ├── 04-parallel-coding-agents/
│   └── 05-devops-workloads/
├── scenarios/
│   ├── multi-agent-orchestration/
│   ├── kubernetes-debugging/
│   └── ci-cd-safe-testing/
├── kits/
│   └── kubernetes-toolkit/    # kubectl, helm, kustomize, K8s API allowlist
├── templates/
│   └── dev-environment/       # Dockerfile-based reusable sandbox base
└── scripts/
    ├── verify-isolation.sh
    └── network-policy-matrix.sh
```

Only files that exist today are committed. Empty directories will be added as labs and scenarios are completed and verified.

## Quick start

Start with [`labs/01-install-and-first-run/`](./labs/01-install-and-first-run/). It walks through installing `sbx`, signing in, selecting a network policy, running a first sandbox, and verifying with `sbx ls`.

## Tested with

See [`tested-with.md`](./tested-with.md) for current `sbx` versions and host configurations under which each lab has been verified.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). Issues, kit contributions, scenario PRs, and friction-log entries all welcome.

## License

MIT. See [`LICENSE`](./LICENSE).

## Maintainer

[Shamsher Khan](https://opscart.com) — Senior DevOps Engineer, IEEE Senior Member, DZone Core Member.