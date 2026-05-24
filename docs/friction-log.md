# Friction Log

Real-time, dated capture of friction points encountered while exploring Docker Sandboxes. Entries are added as friction occurs, not reconstructed from memory after the fact.

## Format

```
## YYYY-MM-DD — Short title
**Context:** what I was trying to do
**Observation:** what happened (with real terminal output)
**Workaround / Resolution:** if any
**sbx version:** the version where this was observed
**Follow-up:** something to investigate in a later lab, if applicable
```

---

## 2026-05-14 — Daemon reported as not running by `sbx version` after successful login ✅ RESOLVED 2026-05-21

**Context:** Fresh install via `brew install docker/tap/sbx` on macOS Apple Silicon. Ran `sbx login` (successful, daemon auto-started with PID 47839), selected `Balanced` network policy, kicked off `sbx run claude` in a project directory. Sandbox image started downloading.

In a separate terminal action, ran `sbx version` to record the installed version for `tested-with.md`.

**Observation:**

```
$ sbx version
Client Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119
Server Version:  Unavailable (daemon not running — use 'sbx daemon start')
```

This contradicts the daemon clearly starting during `sbx login` minutes earlier:

```
Daemon started (PID: 47839, socket: /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock)
```

**Resolution (2026-05-21):**

Ran the full daemon lifecycle test. Real output:

```
$ sbx daemon start
Daemon is already running at /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock

$ sbx version
Client Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119
Server Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119

$ sbx daemon stop
Stopping daemon at /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock...
✓ Daemon stopped successfully

$ sbx version
Client Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119
Server Version:  Unavailable (daemon not running — use 'sbx daemon start')

$ sbx daemon start
Starting daemon at /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock (Ctrl+C to stop)...
{"time":"2026-05-21T22:43:08.160664-04:00","level":"INFO","msg":"loggingkit started"}
{"time":"2026-05-21T22:43:08.161077-04:00","level":"INFO","msg":"secretskit started"}
...
{"time":"2026-05-21T22:43:10.050874-04:00","level":"INFO","msg":"api server started successfully"}
```

**Findings:**

The daemon lifecycle has three modes:

1. **Implicit start** — `sbx run` and `sbx login` start the daemon in the background when it isn't running. The login-time start appears to be session-scoped and stops after the login flow completes. This explains the original "Unavailable" report: the daemon started by `sbx login` had stopped by the time `sbx version` was run (likely after `sbx run` completed its download and the session ended).

2. **Explicit foreground start** — `sbx daemon start` runs the daemon in the foreground, streaming JSON structured logs, and blocks the terminal until Ctrl+C. This is a debugging/inspection mode, not the normal usage path.

3. **Explicit stop** — `sbx daemon stop` stops cleanly. `sbx version` correctly reports "Unavailable" after stop.

**Practical implication:** For normal use, don't manage the daemon manually. `sbx run` handles it. Use `sbx daemon start` only when you need to watch daemon-level logs. Use `sbx version` only when the daemon is already running (i.e., right after `sbx run` or `sbx ls`); otherwise the server version will show Unavailable.

**Additional observation from daemon restart output:** When the daemon restarts, it re-injects the proxy and SSH agent forwarder for all previously running sandboxes:

```
"msg":"re-injected proxy for loaded runtime","runtime":"claude-12-docker-hardened-images"
```

This confirms sandboxes persist across daemon restarts — the microVM state is preserved in storage, not in the daemon's in-memory state.

**sbx version:** v0.29.0 (both client and server confirmed after explicit daemon start).

---

## 2026-05-21 — Upgraded to v0.30.0; three behavioral changes affect this repo

**Context:** Upgrade from v0.29.0 to v0.30.0 via `brew upgrade docker/tap/sbx` during Lab 01 closeout.

**Observation:**

```
$ sbx version
Client Version:  v0.30.0 2852d3aaf659177ffb8fd9d06298ef64df6fadf7
Server Version:  Unavailable (daemon not running — use 'sbx daemon start')
```

Server Unavailable is expected — consistent with documented daemon lifecycle behavior. Upgrade itself was clean.

**Three v0.30.0 changes that affect labs in this repo:**

1. **Grace period before sandbox auto-stop (daemon/sandbox lifecycle).** v0.29.0 auto-stopped sandboxes immediately when the last session exited. v0.30.0 adds a configurable grace period before auto-stop. This refines the daemon lifecycle documented in the 2026-05-14 entry — the auto-stop is now delayed, not immediate. Relevant to Labs 01, 04, and any scenario involving sandbox persistence.

2. **Raw TCP to `host.docker.internal` allowed when localhost is in policy (Lab 02).** In v0.30.0, if `localhost` is permitted by the active network policy, raw TCP to `host.docker.internal` is also permitted. This is a new behavior — v0.29.0 did not have this. Lab 02 will explicitly test this case and document it as a v0.30.0-specific finding.

3. **macOS `/private` path compatibility for worktrees (Lab 04).** On macOS, paths under `/private/var` vs `/var` caused worktree failures in v0.29.0. Fixed in v0.30.0. Lab 04 uses `--branch` mode; this fix means `--branch` is reliable on Apple Silicon macOS from this version forward.

**sbx version:** v0.30.0 (`2852d3aaf659177ffb8fd9d06298ef64df6fadf7`)