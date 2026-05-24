# Lab 01: Install and First Run

## Objective

Install the `sbx` CLI, sign in with Docker, select a default network policy, run a first sandbox, verify the result, and document the daemon lifecycle.

## sbx version verified

`v0.29.0` on macOS Apple Silicon. See [`../../tested-with.md`](../../tested-with.md).

## Prerequisites

- macOS (Apple Silicon or Intel), Windows, or Linux (Ubuntu with KVM)
- A Docker account (free tier works)
- One of:
  - A Claude subscription (Max, Team, or Enterprise) — uses OAuth from inside the sandbox, no upfront key needed
  - An API key for your model provider (Anthropic, OpenAI, Google) — set with `sbx secret set` before running
- Homebrew (macOS), `winget` (Windows), or `apt` + KVM (Linux)

## Steps

### 1. Install the CLI

**macOS:**

```bash
brew install docker/tap/sbx
```

**Windows:**

```powershell
winget install -h Docker.sbx
```

**Linux (Ubuntu):**

```bash
curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
sudo apt-get install docker-sbx
sudo usermod -aG kvm $USER
newgrp kvm
```

### 2. Confirm the install

```bash
sbx version
```

Expected output before first login (commit hash will differ):

```
Client Version:  v0.29.0 7055fecde6b84aeb963d1680879e5620af15c119
Server Version:  Unavailable (daemon not running — use 'sbx daemon start')
```

> **Observation.** The daemon isn't running yet. It auto-starts on `sbx login` or `sbx run`. See [`../../docs/friction-log.md`](../../docs/friction-log.md) entry for 2026-05-14.

### 3. Log in

```bash
sbx login
```

A device confirmation code is printed:

```
Your one-time device confirmation code is: XXXX-XXXX
Open this URL to sign in: https://login.docker.com/activate?user_code=XXXX-XXXX

By logging in, you agree to our Subscription Service Agreement.

Waiting for authentication...
```

Open the URL, sign in to your Docker account, confirm the code. Expected post-auth output:

```
Signed in as <your-username>.
Daemon started (PID: <pid>, socket: /Users/<user>/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock)
Logs: /Users/<user>/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/daemon.log
```

### 4. Select a default network policy

The CLI prompts:

```
Select a default network policy for your sandboxes:

     1. Open         — All network traffic allowed, no restrictions.
  ❯  2. Balanced     — Default deny, with common dev sites allowed.
     3. Locked Down  — All network traffic blocked unless you allow it.

  Use ↑/↓ or 1–3 to navigate, Enter to confirm, Esc to cancel.
```

For a first run, select **Balanced** (option 2). It allows common dev sites (npm, PyPI, GitHub, AI model providers) by default and blocks everything else.

Expected confirmation:

```
Network policy set to "Balanced". Default deny, with common dev sites allowed.

  To change this anytime, run:
    sbx policy reset

  To configure additional policies, run:
    sbx policy allow network -g <host>
    sbx policy deny network -g <host>
```

### 5. Run your first sandbox

> ⚠️ **Important.** The sandbox is named after the current working directory and mounts that directory at the same absolute path inside the microVM. Don't run this in a directory with in-progress work unless you're prepared for the agent to edit files there. Use a scratch directory for first exploration.

```bash
mkdir -p ~/sbx-scratch && cd ~/sbx-scratch
sbx run claude
```

Expected output on first run:

```
Creating new sandbox 'claude-sbx-scratch'...
<image-layer-id>: Download complete
<image-layer-id>: Download complete
<image-layer-id>: Download complete
```

The first run pulls `docker/sandbox-templates:claude-code`, which takes longer than subsequent runs. After the image is cached, sandbox creation completes in seconds.

Once the agent attaches, you're in Claude Code's prompt inside the microVM. Exit with `Ctrl+C` or the agent's own exit command.

### 6. Verify

In another terminal (or after exiting the agent):

```bash
sbx ls
```

Expected output:

```
SANDBOX                  AGENT    STATUS    PORTS    WORKSPACE
claude-sbx-scratch       claude   running            /Users/<user>/sbx-scratch
```

### 7. Test daemon lifecycle (Follow-up from friction log)

```bash
sbx daemon stop
sbx version       # server should report unavailable
sbx daemon start
sbx version       # server should report v0.29.0
```

Record the output. This nails down the daemon state machine.

### 8. Cleanup

Stop without deleting (preserves installed packages and Docker images inside the sandbox):

```bash
sbx stop claude-sbx-scratch
```

Or remove entirely:

```bash
sbx rm claude-sbx-scratch
```

Removing deletes everything inside the sandbox. Files in the host workspace directory are unaffected.

## Observations

- The daemon socket on macOS lives at `~/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock`.
- Daemon logs are at the same directory, in `daemon.log`. Useful for the friction-log follow-up.
- Sandbox naming defaults to `<agent>-<working-directory-basename>`. Override with `--name <custom>`.
- The agent image is pulled lazily on first run, not on install.
- The default `--dangerously-skip-permissions` flag is applied to Claude Code by the template, by design.

## What's happening internally

When you run `sbx run claude`:

1. `sbx` CLI talks to the `sandboxd` daemon over its Unix socket.
2. The daemon pulls (or uses a cached copy of) the `claude-code` template image.
3. A new microVM is created with that image as its root filesystem.
4. The current working directory is mounted into the microVM at the same absolute path via filesystem passthrough.
5. A private Docker daemon starts inside the microVM.
6. The host-side HTTP/HTTPS proxy is wired up to enforce the active network policy and inject credentials into outbound API requests.
7. The Claude Code agent starts inside the microVM with `--dangerously-skip-permissions` set.

## Why it matters

This lab establishes the baseline. Without confirming the install, login, and first run reproduce cleanly, no subsequent lab is meaningful. It also surfaces:

- The daemon lifecycle (start, implicit start, stop, version reporting)
- The default network policy and how to change it
- The workspace mount path convention (same absolute path on both sides)
- The sandbox naming convention (working-directory-derived)
- The persistence model (sandboxes survive agent exit; `sbx rm` to fully delete)

## Next

- **Lab 02 — Network policy probes:** verify what each policy (Open, Balanced, Locked Down) actually permits using a defined endpoint matrix.
- **Lab 03 — Isolation verification:** attempt to break out of the sandbox and document which attempts fail.