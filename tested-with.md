# Tested With

Each lab and scenario in this repo is verified against a specific version of `sbx`. Docker Sandboxes is Early Access; the CLI surface may change between releases. This file is the source of truth for "does it still work."

## Currently verified

| Component | Version | Verified | Host |
|---|---|---|---|
| `sbx` (client) | v0.30.0 (`2852d3aaf659177ffb8fd9d06298ef64df6fadf7`) | 2026-05-21 | macOS, Apple Silicon |
| `sbx` (server / `sandboxd`) | v0.30.0 | 2026-05-21 | same |
| Default agent template | `docker/sandbox-templates:claude-code` | 2026-05-14 | same |

## Per-lab status

| Lab / Scenario | Status | Last verified | sbx version |
|---|---|---|---|
| `labs/01-install-and-first-run` | ✅ verified | 2026-05-21 | v0.30.0 |
| `labs/02-network-policy-probes` | ✅ verified | 2026-05-21 | v0.30.0 |
| `labs/03-isolation-verification` | ✅ verified | 2026-05-21 | v0.30.0 |
| `labs/04-parallel-coding-agents` | ✅ verified | 2026-05-23 | v0.30.0 |
| `labs/05-devops-workloads` | ✅ verified | 2026-05-23 | v0.30.0 |

## Reverification policy

When `sbx` releases a new version:

1. Re-run lab 01 against the new version on a clean machine (or fresh `sbx reset`)
2. Update the table above with the new version, commit, and verification date
3. Note any breaking changes in [`CHANGELOG.md`](./CHANGELOG.md) under `Changed`
4. If a lab no longer reproduces, mark it `[BROKEN]` in its README, open an issue, and update the per-lab status table here

## Checking your version

```bash
sbx version
```

Expected output format:

```
Client Version:  <version> <commit>
Server Version:  <version>
```

If the server reports `Unavailable (daemon not running — use 'sbx daemon start')`, run:

```bash
sbx daemon start
```

…and re-check.