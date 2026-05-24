# Lab 02: Network Policy Probes

## Objective

Map exactly what Docker Sandboxes' Balanced network policy permits and blocks. Understand the blocking mechanism, the DNS behavior, and the raw TCP behavior — from real probe results, not documentation claims.

## sbx version verified

`v0.30.0` on macOS Apple Silicon. See [`../../tested-with.md`](../../tested-with.md).

## Prerequisites

- Lab 01 completed
- `sbx` installed and authenticated
- Default network policy set to **Balanced** (set during `sbx login`)
- Two terminal windows

## Background

Every sandbox routes all outbound HTTP/HTTPS through a host-side proxy. The proxy enforces the active network policy and injects credentials. Raw TCP, UDP, and ICMP are blocked at the network layer — with one exception covered in the results below.

Three policies are available:

| Policy | Behavior |
|---|---|
| Open | All HTTP/HTTPS allowed. Non-HTTP protocols still blocked at network layer. |
| Balanced | Default deny. Curated allowlist of dev-ecosystem domains. |
| Locked Down | All HTTP/HTTPS blocked unless explicitly allowed via `sbx policy allow`. |

This lab probes Balanced, which is the default and the most representative for real usage.

## Steps

### Step 1: Create the sandbox

From the repo root in Terminal 1:

```bash
sbx run claude --name 02-network-policy-probes
```

Expected output (image already cached from Lab 01):

```
Starting sandboxd daemon...
Daemon started (PID: 1863, socket: /Users/opscart/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/sandboxd.sock)
Creating new sandbox '02-network-policy-probes'...
6f873d7e6093: Already exists
9d06a91a963d: Already exists
aa5dce7d6b1e: Already exists
Status: Image is up to date for docker/sandbox-templates:claude-code-docker
✓ Created sandbox '02-network-policy-probes'
  Workspace: /Users/opscart/Source/docker-sandbox-devops (direct mount)
  Agent: claude
INFO: Started Docker daemon in 0.9s
Starting claude agent in sandbox '02-network-policy-probes'...
```

Note the template: `claude-code-docker` — the `-docker` variant includes a Docker Engine inside the sandbox, confirming each sandbox gets its own isolated daemon.

### Step 2: Open a shell inside the sandbox

In Terminal 2 (leave the agent running in Terminal 1):

```bash
sbx exec -it 02-network-policy-probes bash
```

Expected prompt:

```
agent@02-network-policy-probes:~/workspace$
```

Note the username: `agent`. The microVM runs as a non-root user by default.

### Step 3: Confirm available tools

```bash
which curl && curl --version | head -1
which dig && dig -v 2>&1 | head -1
which nc && nc --version 2>&1 | head -1
```

Real output:

```
/usr/bin/curl
curl 8.14.1 (aarch64-unknown-linux-gnu) libcurl/8.14.1 OpenSSL/3.5.3 zlib/1.3.1 brotli/1.1.0 ...
/usr/bin/dig
DiG 9.20.11-1ubuntu2.2-Ubuntu
```

`nc` (netcat) produced no output — not installed in this template. All TCP probes use `curl telnet://` instead.

Important: the curl architecture is `aarch64-unknown-linux-gnu` — ARM Linux inside the microVM, even on an Apple Silicon macOS host. The guest OS is always Linux regardless of host platform.

### Step 4: Run the probe matrix

Define the probe function and run:

```bash
probe() {
    local label=$1; local url=$2
    result=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    echo "$label | exit=$? | http=$result"
}

echo "--- Dev ecosystem ---"
probe "github.com"          "https://github.com"
probe "pypi.org"            "https://pypi.org"
probe "registry.npmjs.org"  "https://registry.npmjs.org"
probe "api.anthropic.com"   "https://api.anthropic.com"
probe "hub.docker.com"      "https://hub.docker.com"
probe "pkg.go.dev"          "https://pkg.go.dev"

echo "--- General internet ---"
probe "example.com"         "https://example.com"
probe "google.com"          "https://google.com"
probe "bbc.com"             "https://bbc.com"

echo "--- Internal / RFC1918 ---"
probe "192.168.1.1"         "http://192.168.1.1"
probe "10.0.0.1"            "http://10.0.0.1"

echo "--- host.docker.internal ---"
probe "host.docker.internal" "http://host.docker.internal"
```

Real output:

```
--- Dev ecosystem ---
github.com | exit=0 | http=200
pypi.org | exit=0 | http=200
registry.npmjs.org | exit=0 | http=200
api.anthropic.com | exit=0 | http=404
hub.docker.com | exit=0 | http=200
pkg.go.dev | exit=0 | http=200

--- General internet ---
example.com | exit=0 | http=403
google.com | exit=0 | http=403
bbc.com | exit=0 | http=403

--- Internal / RFC1918 ---
192.168.1.1 | exit=0 | http=403
10.0.0.1 | exit=0 | http=403

--- host.docker.internal ---
host.docker.internal | exit=0 | http=403
```

### Step 5: Run DNS resolution probes

```bash
echo "--- DNS resolution ---"
dig github.com +short | head -3
dig example.com +short | head -3
```

Real output:

```
--- DNS resolution ---
140.82.112.3
172.66.147.243
104.20.23.154
```

Both an allowed domain (`github.com`) and a blocked domain (`example.com`) resolved successfully.

### Step 6: Run raw TCP probes

```bash
echo "--- Raw TCP: allowed domain, non-HTTP port ---"
curl -s --max-time 3 telnet://github.com:22 2>/dev/null \
  && echo "github:22 | connected" \
  || echo "github:22 | blocked exit=$?"

echo "--- Raw TCP: host.docker.internal ---"
curl -s --max-time 3 telnet://host.docker.internal:80 2>/dev/null \
  && echo "host.docker.internal:80 | connected" \
  || echo "host.docker.internal:80 | blocked exit=$?"
```

Real output:

```
--- Raw TCP: allowed domain, non-HTTP port ---
github:22 | connected

--- Raw TCP: host.docker.internal ---
host.docker.internal:80 | blocked exit=28
```

## Results: Balanced Policy

Full results table from real runs against `sbx` v0.30.0:

| Endpoint | Method | Expected | HTTP status | Exit | Result |
|---|---|---|---|---|---|
| github.com | HTTPS | Allowed | 200 | 0 | ✅ allowed |
| pypi.org | HTTPS | Allowed | 200 | 0 | ✅ allowed |
| registry.npmjs.org | HTTPS | Allowed | 200 | 0 | ✅ allowed |
| api.anthropic.com | HTTPS | Allowed | 404 | 0 | ✅ allowed (root path not found) |
| hub.docker.com | HTTPS | Allowed | 200 | 0 | ✅ allowed |
| pkg.go.dev | HTTPS | Allowed | 200 | 0 | ✅ allowed |
| example.com | HTTPS | Blocked | 403 | 0 | 🚫 proxy block |
| google.com | HTTPS | Blocked | 403 | 0 | 🚫 proxy block |
| bbc.com | HTTPS | Blocked | 403 | 0 | 🚫 proxy block |
| 192.168.1.1 | HTTP | Blocked | 403 | 0 | 🚫 proxy block |
| 10.0.0.1 | HTTP | Blocked | 403 | 0 | 🚫 proxy block |
| host.docker.internal | HTTP | Unknown | 403 | 0 | 🚫 proxy block |
| github.com:22 | TCP CONNECT | Blocked | — | 0 | ⚠️ connected (see Observation 3) |
| host.docker.internal:80 | TCP CONNECT | Unknown | — | 28 | 🚫 timeout |
| github.com DNS | UDP/53 | Unknown | — | — | ✅ resolved (see Observation 4) |
| example.com DNS | UDP/53 | Unknown | — | — | ✅ resolved (see Observation 4) |

## Observations

### 1. Blocking is HTTP 403 from the proxy, not TCP failure

Every blocked endpoint returned `exit=0` with `http=403`. curl exited cleanly because it successfully connected — to the host-side proxy. The proxy returned 403 without forwarding the request. This has a practical implication: an agent cannot distinguish a blocked domain from a 403 response from a real server using exit codes alone. Both look like successful HTTP transactions.

### 2. `api.anthropic.com` returns 404, not 200

The connection was permitted (`exit=0`). HTTP 404 means the proxy forwarded the request to Anthropic's API and the root path `/` returned 404 — which is correct, the API has no root endpoint. This confirms `api.anthropic.com` is in the Balanced allowlist.

### 3. HTTP CONNECT tunneling allows raw TCP to allowed domains on any port

`github.com:22` connected. This is the most significant finding.

When `curl telnet://github.com:22` runs inside the sandbox, it sends an HTTP CONNECT request to the host-side proxy. The proxy sees the target host (`github.com`) in its allowlist and permits the CONNECT tunnel. The tunnel is TCP, not HTTP — once established, the SSH server at github.com:22 sent a banner and curl received it, returning exit 0.

The implication: Balanced policy allows not just HTTPS (port 443) to allowlisted domains, but any port via HTTP CONNECT tunneling. An agent could initiate an SSH connection to github.com, for example. This is not a bypass — the connection still goes through the proxy and is policy-enforced by hostname — but it is a broader surface than "only HTTP/HTTPS on standard ports."

Compare: `host.docker.internal:80` returned `exit=28` (timeout). `host.docker.internal` is not in the Balanced allowlist, so the proxy did not permit the CONNECT tunnel. The request timed out at the proxy level.

### 4. DNS is not policy-filtered

`example.com` (a blocked domain) resolved to `172.66.147.243` and `104.20.23.154`. DNS resolution succeeds for all domains regardless of network policy.

The microVM has an internal DNS resolver that handles name resolution independently from the HTTP proxy policy. An agent can resolve any domain name even if HTTP connections to that domain are blocked. DNS cannot be used as an enforcement layer in this model.

### 5. RFC1918 addresses are blocked at the proxy, not the network layer

`192.168.1.1` and `10.0.0.1` returned `http=403` from the proxy. The proxy explicitly blocks requests to private address ranges. However, this only covers HTTP/HTTPS — a raw TCP CONNECT to a RFC1918 host on a non-HTTP port would time out (exit=28) rather than return 403, because there's no HTTP proxy response for non-proxied protocols.

## What's happening internally

```
Agent (inside microVM)
        │
        │ curl https://github.com
        │
        ▼
Host-side HTTP/HTTPS proxy
        │
        ├── github.com in allowlist? → YES → forward request → 200
        │
        ├── example.com in allowlist? → NO → return HTTP 403
        │
        └── CONNECT github.com:22 in allowlist? → YES (host matches) → tunnel TCP
```

For DNS: `dig github.com` bypasses the HTTP proxy entirely and hits the microVM's internal stub resolver, which forwards the query through a DNS path not governed by the HTTP policy. DNS responses are not filtered.

## Why it matters

The Balanced policy does what it says — development ecosystem domains work, arbitrary internet access is blocked. But three findings matter for engineers using this in practice:

Firstly, the blocking signal (HTTP 403) is indistinguishable from a server-side 403 by exit code. Agents that retry on 403 will retry blocked requests indefinitely. Design agent loops to handle this case.

Secondly, allowed domains are reachable on all ports via HTTP CONNECT, not just 443. If `github.com` is in the policy, an agent has SSH access to github.com. For most workflows this is useful (git over SSH). For threat modelling, know the surface is broader than HTTP/HTTPS.

Thirdly, DNS is a side channel. An agent that can resolve a domain can infer whether the domain exists, even if HTTP access is blocked.

## Testing other policies

To verify Open or Locked Down behavior, change the default policy from the host and create a new sandbox:

```bash
# from host terminal
sbx policy reset   # prompts for policy selection
sbx run claude --name 02-probes-lockeddown
```

Then re-run the probe matrix inside the new sandbox. Key probes to compare:
- Locked Down: `github.com` should return 403 (blocked unless explicitly allowed)
- Open: `example.com` should return 200 (all HTTP/HTTPS permitted)

Note: policy changes apply to new sandboxes. Running sandboxes may require a restart to pick up changes.

## Cleanup

```bash
# exit the shell first (Terminal 2)
exit

# remove the sandbox (Terminal 1 or host)
sbx rm 02-network-policy-probes
```

## Next

- **Lab 03 — Isolation verification:** attempt to reach the host filesystem outside the workspace, the host Docker daemon, other sandboxes, and non-HTTP host services. Document which attempts fail and how.