# CLAUDE.md

Project context for Claude Code. Read this first.

## What this repo is

`docker-sandbox-devops` — an independent, engineering-first exploration of [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (the `sbx` CLI) for running AI coding agents in isolated microVMs on a local machine. Evaluated from a DevOps / platform engineering perspective. Maintained by Shamsher Khan (OpsCart).

This repo is also part of a longer-term goal: building a focused, Captain-grade body of work around sandboxed dev environments + AI + DevOps. Quality and honesty matter more than volume.

## Hard constraints (do not violate)

1. **No invented terminal output.** Every command output in a lab or doc must be real — captured from an actual run on this machine. If output isn't available yet, mark the section `TODO: capture real output` rather than fabricating it.
2. **Docker Sandboxes is Early Access.** Never describe it as production-ready, GA, or stable. The CLI surface may change between releases.
3. **Vendor-neutral tone.** This is an engineering evaluation, not Docker marketing. Note limitations honestly.
4. **Version pinning.** Every lab declares the `sbx` version it was verified against. Update `tested-with.md` whenever reproducibility is affected.
5. **Real-time friction log.** Add dated entries to `docs/friction-log.md` as friction occurs, not reconstructed later.
6. **Not a cloud-sandbox competitor.** Docker Sandboxes is local, for coding agents. E2B/Modal/Daytona/Cloudflare are cloud-hosted for arbitrary agent code — different problem. Don't frame them as direct competitors.

## Key decisions already made

- Repo name: `docker-sandbox-devops` (new repo, not a lab in the existing `docker-security-practical-guide`)
- The existing security repo will get a one-line "Related Work" link only — no embedded labs
- Kit is named `kubernetes-toolkit` (generic, cloud-agnostic — kubectl/helm/kustomize). NOT cloud-specific naming.
- Lab 04 stays `04-parallel-coding-agents` (technically accurate; multi-agent orchestration lives in `scenarios/`)
- Diagrams: Mermaid (inline) or Excalidraw SVG — text-versioned, not PNG blobs
- License: MIT
- Kit upstream target: `docker/sbx-kits-contrib` — upstream once tested locally end-to-end

## Environment

- Host: macOS, Apple Silicon
- `sbx` client: v0.29.0 (commit `7055fecde6b84aeb963d1680879e5620af15c119`)
- Agent in use: Claude Code (template `docker/sandbox-templates:claude-code`, runs with `--dangerously-skip-permissions` by default)
- Daemon socket: `~/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock`
- Daemon logs: same dir, `daemon.log`

## Current state

Built and verified:
- Repo scaffold: README, LICENSE, CONTRIBUTING, CHANGELOG, tested-with, .gitignore
- `docs/00-overview.md` — engineering overview
- `docs/friction-log.md` — open, one entry (2026-05-14, daemon-not-running observation)
- `labs/01-install-and-first-run/` — complete

Not yet built (marked 🚧 in tested-with.md):
- Labs 02–05, all scenarios, the kit, the template, the scripts

## Immediate next tasks

1. **Lab 01 Step 7 — daemon lifecycle.** Run `sbx daemon stop` → `sbx version` → `sbx daemon start` → `sbx version`. Capture real output. Resolve the friction-log hypothesis about why `sbx version` reported the daemon as not running. Update both `docs/friction-log.md` and Lab 01's "What's happening internally" section with the resolved behavior.
2. **Lab 02 — network policy probes.** Build a probe matrix testing what each policy (Open / Balanced / Locked Down) actually permits. Endpoints to test (default set, adjust as needed): `github.com`, `pypi.org`, `registry.npmjs.org`, `api.anthropic.com`, `hub.docker.com`, plus negatives that should fail (a raw IP over a non-HTTP port, an RFC1918 internal address, a non-HTTP protocol like raw TCP). Build `scripts/network-policy-matrix.sh` to automate it. Capture real results into a table.

## Lab structure convention

Each lab README has, in order: Objective · sbx version verified · Prerequisites · Steps (with expected real output) · Observations · What's happening internally · Why it matters · Next.

## Friction log entry format

```
## YYYY-MM-DD — Short title
**Context:** ...
**Observation:** (real terminal output)
**Workaround / Resolution:** ...
**sbx version:** ...
**Follow-up:** ...
```

## A note on dogfooding

If you (Claude Code) are running inside a Docker Sandbox while building this repo, that's worth a friction-log entry — building the sandbox documentation from inside the sandbox is exactly the kind of authentic detail the eventual write-up should capture. Note anything that breaks (missing tools, OS mismatch, lost context across sessions).