# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project tracks Docker Sandboxes (`sbx`) versions in [`tested-with.md`](./tested-with.md).

## [Unreleased]

### Added

- Initial repo scaffold: README, LICENSE (MIT), CONTRIBUTING, CHANGELOG, tested-with, .gitignore, CLAUDE.md
- `docs/00-overview.md` — engineering overview of Docker Sandboxes
- `docs/friction-log.md` — live log, four entries (daemon lifecycle, v0.30.0 upgrade, kustomize ARM64 failure)
- `docs/architecture-notes.md` — microVM architecture, isolation layers, gateway bridge, proxy mechanism
- `docs/threat-model.md` — what is protected, what has nuance, what is not protected
- `docs/comparison-notes.md` — vendor-neutral positioning vs alternatives
- `labs/01-install-and-first-run/` — install, login, network policy, daemon lifecycle, first sandbox run
- `labs/02-network-policy-probes/` — Balanced policy probe matrix, HTTP 403 blocking mechanism, CONNECT tunneling, DNS behavior
- `labs/03-isolation-verification/` — filesystem mount boundary, PID namespace, Docker daemon isolation, credential env, host network
- `labs/04-parallel-coding-agents/` — branch mode, Git worktrees, one sandbox per workspace, cleanup behavior
- `labs/05-devops-workloads/` — custom template build, DevOps toolchain (kubectl/helm/kustomize/azure-cli), network policy for cluster access
- `templates/dev-environment/Dockerfile` — DevOps toolkit image, published as `shamsk22/sbx-devops-toolkit:v1.0.0`
- All labs verified against `sbx` v0.30.0 on macOS Apple Silicon