# Lab 03: Isolation Verification

## Objective

Verify Docker Sandbox's isolation claims from the inside. Run adversarial probes against the filesystem, process namespace, Docker daemon, credential environment, and host network. Document what holds, what surprises, and what the actual boundaries look like — not what the documentation claims.

## sbx version verified

`v0.30.0` on macOS Apple Silicon. See [`../../tested-with.md`](../../tested-with.md).

## Prerequisites

- Labs 01 and 02 completed
- `sbx` installed and authenticated
- Two terminal windows

## Setup

Terminal 1 — start the sandbox:

```bash
sbx run claude --name 03-isolation-verification
```

Terminal 2 — open a shell inside it:

```bash
sbx exec -it 03-isolation-verification bash
```

Expected prompt:

```
agent@03-isolation-verification:~/workspace$
```

## Probe Groups

### Group 1: Filesystem — what's visible outside the workspace?

```bash
echo "--- G1: Host dirs outside workspace ---"
ls /Users/ 2>&1 | head -5
echo "---"
ls /Users/opscart/ 2>&1 | head -5
echo "---"
ls /Users/opscart/.ssh/ 2>&1 | head -3
echo "---"
cat /etc/hostname
echo "---"
ls / 2>&1
```

Real output:

```
--- G1: Host dirs outside workspace ---
opscart
---
Source
---
ls: cannot access '/Users/opscart/.ssh/': No such file or directory
---
localhost.localdomain
---
Users  bin  boot  dev  etc  home  lib  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
```

### Group 2: Process isolation

```bash
echo "--- G2: Process isolation ---"
echo "Process count: $(ps aux | wc -l)"
ps aux | head -8
echo "PID 1 cmdline:"
cat /proc/1/cmdline | tr '\0' ' ' && echo
```

Real output:

```
--- G2: Process isolation ---
Process count: 12
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
agent          1  0.0  0.0   2704  1248 ?        Ss   22:58   0:00 tini -- sh -c trap 'kill -TERM -- -1; wait' TERM; sleep infinity & wait
agent          2  0.0  0.0   2800  1664 ?        S    22:58   0:00 sh -c trap 'kill -TERM -- -1; wait' TERM; sleep infinity & wait
agent          3  0.0  0.0  14640  6512 ?        S    22:58   0:00 sleep infinity
root        1196  0.0  0.0  11904  4160 ?        S    22:58   0:00 socat UNIX-LISTEN:/run/ssh-agent.sock,fork,mode=666 TCP:gateway.docker.internal:3129
root        1228  0.7  1.0 1862400 84096 ?       Sl   22:58   0:00 dockerd
root        1240  0.8  0.5 1768048 47456 ?       Ssl  22:58   0:00 containerd --config /var/run/docker/containerd/containerd.toml
agent       1416 32.5  6.1 75346416 504336 pts/0 Ssl+ 22:58   0:09 claude --dangerously-skip-permissions
PID 1 cmdline:
tini -- sh -c trap 'kill -TERM -- -1; wait' TERM; sleep infinity & wait
```

### Group 3: Docker daemon — sandbox or host?

```bash
echo "--- G3: Docker daemon ---"
docker ps 2>&1 | head -5
docker info 2>&1 | grep -E "Server Version|Operating System|Architecture|ID"
echo "DOCKER_HOST=$DOCKER_HOST"
ls -la /var/run/docker.sock 2>&1
```

Real output:

```
--- G3: Docker daemon ---
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES

 Server Version: 29.4.3
 Operating System: Ubuntu 25.10 (containerized)
 Architecture: aarch64
 ID: d3176008-6c3c-4529-904b-cb13029fbfd4
DOCKER_HOST=
srw-rw---- 1 root docker 0 May 23 22:58 /var/run/docker.sock
```

### Group 4: Credential exposure

```bash
echo "--- G4: Credentials in env ---"
env | grep -iE "api_key|anthropic|secret|token|password" | head -10
echo "---proxy vars---"
env | grep -iE "http_proxy|https_proxy|proxy" | head -5
```

Real output:

```
--- G4: Credentials in env ---
(no output)
---proxy vars---
no_proxy=localhost,127.0.0.1,::1,gateway.docker.internal
NODE_USE_ENV_PROXY=1
https_proxy=http://gateway.docker.internal:3128
JAVA_TOOL_OPTIONS=-Dhttp.proxyHost=gateway.docker.internal -Dhttp.proxyPort=3128 -Dhttps.proxyHost=gateway.docker.internal -Dhttps.proxyPort=3128 -Dhttp.nonProxyHosts=localhost|127.*|[::1]|gateway.docker.internal
NO_PROXY=localhost,127.0.0.1,::1,gateway.docker.internal
```

### Group 5: Host network access

```bash
echo "--- G5: Host network access ---"
curl -s -o /dev/null -w "host.docker.internal: http=%{http_code}\n" --max-time 3 http://host.docker.internal/ || echo "exit=$?"
curl -s -o /dev/null -w "localhost:22: http=%{http_code}\n" --max-time 3 http://localhost:22 || echo "exit=$?"
curl -s -o /dev/null -w "localhost:6443 (k8s api): http=%{http_code}\n" --max-time 3 https://localhost:6443 || echo "exit=$?"
```

Real output:

```
--- G5: Host network access ---
host.docker.internal: http=403
localhost:22: http=000
exit=7
localhost:6443 (k8s api): http=000
exit=7
```

## Results Summary

| Probe | Claim | Result | Holds? |
|---|---|---|---|
| `/Users/opscart/.ssh/` | Host home not exposed | No such file or directory | ✅ |
| `/Users/opscart/` siblings | Only workspace path visible | Shows `Source` only (not Desktop, Downloads, etc.) | ✅ |
| `/etc/hostname` | Sandbox has own identity | `localhost.localdomain` (not host hostname) | ✅ |
| Process count | PID namespace isolated | 12 processes (sandbox only) | ✅ |
| Host processes visible | No host processes in PID ns | None visible | ✅ |
| Docker daemon | Sandbox-private daemon | Unique ID, Ubuntu 25.10, version 29.4.3 | ✅ |
| Host Docker socket | No access to host daemon | Sandbox socket only, created at sandbox start | ✅ |
| API keys in env | Credentials not injected as env vars | Empty — no keys found | ✅ |
| `localhost:22` | Sandbox localhost, not host | `exit=7` connection refused — nothing listening | ✅ |
| `localhost:6443` | Sandbox localhost, not host | `exit=7` connection refused — nothing listening | ✅ |

## Observations

### 1. Filesystem mount is path-scoped, not home-scoped

The workspace mount (`/Users/opscart/Source/docker-sandbox-devops`) creates a minimal parent directory stub hierarchy: `/Users/` exists, `/Users/opscart/` exists, `/Users/opscart/Source/` exists. But each parent shows only the child in the mount path — not its siblings. `/Users/opscart/` shows `Source` and nothing else. No `Desktop`, no `Downloads`, no `.ssh`, no hidden directories.

The boundary is the workspace directory itself. Everything above it in the path is a read-only stub that exposes no sibling content. Everything below it is the mounted workspace.

Practical implication: if your workspace directory is your home directory (`~/`), you expose your entire home to the sandbox. Always mount a project subdirectory, not a parent.

### 2. PID namespace is fully isolated — 12 processes, no host visibility

A macOS host runs hundreds of processes. The sandbox shows 12 — all sandbox-internal. The host PID namespace is completely invisible.

The process list reveals the sandbox's internal stack:

- `tini` as PID 1 — a minimal init system that handles signal forwarding and zombie reaping. A standard container pattern.
- `socat` bridging `/run/ssh-agent.sock` to `TCP:gateway.docker.internal:3129` — this is how SSH agent forwarding reaches the host. The gateway host is the bridge between the sandbox and permitted host services.
- `dockerd` and `containerd` running as root inside the sandbox — the private Docker Engine.
- `claude --dangerously-skip-permissions` running as `agent` — the coding agent itself, a regular user process.

### 3. Private Docker Engine — completely isolated from host

`docker info` returns a unique daemon ID (`d3176008-6c3c-4529-904b-cb13029fbfd4`), Docker Engine 29.4.3, and Ubuntu 25.10. This is the sandbox's own Docker Engine, not the host's.

`DOCKER_HOST` is empty — the `docker` CLI inside the sandbox talks to `/var/run/docker.sock`, which is the sandbox's own socket (created at sandbox start time). There is no path to the host Docker daemon.

`docker ps` returns empty — the Claude Code agent runs as a native process, not as a Docker container. The sandbox's Docker Engine is available for the agent to use (`docker build`, `docker run`, `docker compose`) without requiring any socket mounting or privilege escalation.

This is the core advantage over container-based sandboxes: each sandbox has full Docker capabilities without touching the host daemon.

### 4. No credentials in environment — but proxy address is visible

`env | grep -iE "api_key|anthropic|secret|token|password"` returned nothing. Credential isolation holds: raw API keys and tokens are not present in the sandbox environment.

However the proxy configuration IS visible:

```
https_proxy=http://gateway.docker.internal:3128
```

An agent running inside the sandbox can see that traffic is routed through `gateway.docker.internal:3128`. It cannot see the credentials that the proxy injects into outbound requests. The proxy holds the secrets on the host side.

The sandbox pre-configures multiple runtimes to use this proxy automatically:

- `https_proxy` / `no_proxy` — standard env vars, picked up by curl, wget, most HTTP clients
- `NODE_USE_ENV_PROXY=1` — enables proxy support in Node.js (disabled by default in Node)
- `JAVA_TOOL_OPTIONS` — pre-sets JVM proxy flags for any Java process

An agent using npm, pip, the Anthropic SDK, or any standard HTTP client gets credential injection without any configuration. No secrets ever appear in the sandbox environment.

### 5. `localhost` is the sandbox's localhost — not the host's

`curl localhost:22` and `curl localhost:6443` both returned `exit=7` (connection refused). Exit=7 means curl reached the socket but nothing was listening — the ports aren't open inside the sandbox. This is different from exit=28 (timeout), which would indicate the connection was blocked.

The host's SSH daemon on port 22 and any Kubernetes API server on port 6443 are not reachable via localhost from inside the sandbox. The sandbox has its own loopback interface.

## What's happening internally

```
macOS host
├── sandboxd (manages microVMs)
├── Proxy (gateway.docker.internal:3128) — holds credentials, enforces policy
├── SSH bridge (gateway.docker.internal:3129) — forwards SSH agent
│
└── microVM: 03-isolation-verification
    ├── /Users/opscart/Source/docker-sandbox-devops  (workspace mount, R/W)
    ├── /Users/opscart/  (stub — shows Source only)
    ├── /Users/  (stub — shows opscart only)
    ├── PID namespace (isolated — 12 processes)
    ├── dockerd + containerd (sandbox-private Docker Engine)
    ├── socat (bridges /run/ssh-agent.sock → gateway:3129)
    └── claude --dangerously-skip-permissions (agent process, user: agent)
```

## Why it matters

This lab confirms which isolation claims hold under direct adversarial probing:

The private Docker Engine per sandbox is the most operationally significant finding. Coding agents routinely need to build and run containers. Giving each sandbox its own Docker Engine — without socket mounting — eliminates the primary reason developers previously had to choose between agent productivity and host isolation.

The credential isolation pattern (proxy holds keys, env has proxy address only) means a fully compromised sandbox cannot exfiltrate raw API keys. The agent can make authenticated API calls but never sees the credential value.

The filesystem mount boundary requires care from the user: the workspace parent hierarchy is partially visible. Mount project directories, not home directories.

## Cleanup

```bash
# exit sandbox shell (Terminal 2)
exit

# remove sandbox (Terminal 1)
sbx rm 03-isolation-verification
```

## Next

- **Lab 04 — Parallel coding agents:** run two sandboxes side by side using `--branch` mode on the same repository. Verify they operate independently with no shared filesystem or network state.