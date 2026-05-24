# Lab 04: Parallel Coding Agents

## Objective

Run two Claude Code agents simultaneously on the same repository using `--branch` mode. Understand what isolation `--branch` actually provides, where the boundaries are, and how this differs from running agents in separate sandboxes.

## sbx version verified

`v0.30.0` on macOS Apple Silicon. See [`../../tested-with.md`](../../tested-with.md).

## Prerequisites

- Labs 01–03 completed
- `sbx` installed and authenticated
- **The workspace must be a Git repository with at least one commit.** `--branch` creates Git worktrees — it requires a commit to branch from. Run `git log --oneline -1` to confirm.
- Three terminal windows

## The honest framing

The original assumption going into this lab: `--branch` creates two separate microVMs, one per agent, with full hardware-level isolation between them.

**That is not what happens.**

`--branch` creates Git worktrees — separate filesystem trees, separate branches — within a single sandbox. Both agents share one microVM, one Docker daemon, and one network stack. The isolation is Git-level, not VM-level.

This is not a limitation to work around. It is the intended design for parallel work on the same codebase: two agent sessions on different branches, neither overwriting the other's work, with no merge conflicts during active development.

For true VM-level isolation between agents, use separate workspace directories — each gets its own sandbox and its own microVM. That pattern is covered in [`../../scenarios/multi-agent-orchestration/`](../../scenarios/multi-agent-orchestration/).

## Steps

### Step 1: Confirm git prerequisites

```bash
git log --oneline -1
git status
```

Expected:

```
cbee606 (HEAD -> main) initial scaffold: labs 01-03, docs, scripts structure
On branch main
nothing to commit, working tree clean
```

### Step 2: Launch Agent A with a named branch

Terminal 1, from the repo root:

```bash
sbx run claude --name 04-agent-a --branch lab04-agent-a
```

Real output:

```
✓ Git repository detected: /Users/opscart/Source/docker-sandbox-devops
Creating Git worktree with branch: lab04-agent-a
✓ Created worktree: .sbx/04-agent-a-worktrees/lab04-agent-a
✓ Branch created from: main

💡 Your sandbox works on the 'lab04-agent-a' branch at .sbx/04-agent-a-worktrees/lab04-agent-a
   The agent can access both the main repo and the worktree.
   To merge changes back: git merge lab04-agent-a

Creating new sandbox '04-agent-a'...
✓ Created sandbox '04-agent-a'
  Workspace: /Users/opscart/Source/docker-sandbox-devops (git root)
  Worktree: /Users/opscart/Source/docker-sandbox-devops/.sbx/04-agent-a-worktrees/lab04-agent-a
  Branch: lab04-agent-a
  Agent: claude
INFO: Started Docker daemon in 1.2s
Starting claude agent in sandbox '04-agent-a'...
Workspace: /Users/opscart/Source/docker-sandbox-devops/.sbx/04-agent-a-worktrees/lab04-agent-a
```

### Step 3: Launch Agent B on a second branch

Terminal 2, from the same repo root, **without `--name`**:

```bash
sbx run claude --branch lab04-agent-b
```

> **Why no `--name`?** One sandbox exists per workspace directory. Providing `--name 04-agent-b` fails with "sandbox '04-agent-a' already exists; --name can only be used when creating a new sandbox." Without `--name`, `sbx` attaches to the existing sandbox and creates a new worktree inside it.

Real output:

```
Starting claude agent in sandbox '04-agent-a'...
Workspace: /Users/opscart/Source/docker-sandbox-devops
/…/.sbx/04-agent-a-worktrees/lab04-agent-b
```

Both agents are now running inside the **same sandbox** (`04-agent-a`), each working in their own Git worktree.

### Step 4: Inspect the worktree structure

Terminal 3, from the repo root:

```bash
ls -la .sbx/
ls -la .sbx/04-agent-a-worktrees/
```

Expected:

```
.sbx/
└── 04-agent-a-worktrees/
    ├── lab04-agent-a/    ← Agent A's working directory
    └── lab04-agent-b/    ← Agent B's working directory
```

Both worktrees are full checkouts of `main` at the point of creation, now tracking their respective branches independently.

### Step 5: Verify Git isolation between worktrees

Open a shell inside the sandbox:

```bash
sbx exec -it 04-agent-a bash
```

Check branches:

```bash
git branch -a
```

Real output:

```
* lab04-agent-a
+ lab04-agent-b
+ main
```

`*` = current worktree's branch. `+` = other active worktrees. All three branches visible from within the sandbox.

Create a file in Agent A's worktree:

```bash
touch /Users/opscart/Source/docker-sandbox-devops/.sbx/04-agent-a-worktrees/lab04-agent-a/agent-a-marker.txt
```

Verify it is not visible in Agent B's worktree:

```bash
ls /Users/opscart/Source/docker-sandbox-devops/.sbx/04-agent-a-worktrees/lab04-agent-b/agent-a-marker.txt 2>&1
```

Real output:

```
ls: cannot access '…/lab04-agent-b/agent-a-marker.txt': No such file or directory
```

Git isolation confirmed. Files committed to `lab04-agent-a` do not appear in `lab04-agent-b` until explicitly merged.

## Results

| What's isolated | Between agents using `--branch` |
|---|---|
| Git branch | ✅ Each agent works on its own branch |
| Working directory (worktree) | ✅ Separate filesystem trees under `.sbx/` |
| Uncommitted file changes | ✅ Not visible across worktrees |
| microVM | ❌ Shared — one sandbox per workspace |
| Docker daemon | ❌ Shared — one daemon inside the sandbox |
| Network stack | ❌ Shared — same network policy and proxy |
| Credentials | ❌ Shared — same proxy credential injection |

## Observations

### 1. One sandbox per workspace directory

`sbx` enforces one active sandbox per workspace directory. A second `sbx run --name <new-name>` in the same directory fails. The `--branch` flag adds worktrees to the existing sandbox — it does not create a new one.

This is the intended design: the sandbox is associated with the project, not with individual agent sessions.

### 2. Worktree path convention

All worktrees for a sandbox live under:

```
.sbx/<sandbox-name>-worktrees/<branch-name>/
```

For this lab:

```
.sbx/04-agent-a-worktrees/lab04-agent-a/   ← Agent A
.sbx/04-agent-a-worktrees/lab04-agent-b/   ← Agent B
```

Even though Agent B uses branch `lab04-agent-b`, its worktree lives under `04-agent-a-worktrees/` — named after the sandbox, not the branch. The sandbox name is the organizing unit.

### 3. `--branch` is for parallel work on a codebase, not for agent isolation

Two agents using `--branch` on the same repo can work on different features simultaneously without merge conflicts during development. Agent A builds feature X on `lab04-agent-a`; Agent B builds feature Y on `lab04-agent-b`. Neither sees the other's uncommitted work. Both can commit and push independently. Merging happens explicitly when ready.

This matches how human developers use Git branches — the sandbox enforces it at the tool level.

### 4. Claude Code auto-updates between agent sessions

Agent A launched with Claude Code v2.1.141. Agent B launched minutes later with v2.1.150. The template pulls the latest Claude Code on each agent start. In a multi-agent workflow this means two simultaneous agents may run different Claude Code versions. Note this if debugging agent-specific behavior.

### 5. For VM-level agent isolation, use separate workspace directories

If the requirement is that two agents cannot share memory, network, or process state, they must run in separate sandboxes — which requires separate workspace directories. Pattern:

```bash
# Agent A — its own directory, its own sandbox, its own microVM
cd /path/to/project-a
sbx run claude --name agent-a

# Agent B — separate directory, separate sandbox, separate microVM
cd /path/to/project-b
sbx run claude --name agent-b
```

Each sandbox is a separate microVM with its own Docker daemon, network stack, and credential proxy connection. This is true multi-agent isolation. See [`../../scenarios/multi-agent-orchestration/`](../../scenarios/multi-agent-orchestration/) for the orchestration pattern.

## What's happening internally

```
macOS host
└── Sandbox: 04-agent-a (one microVM)
    ├── Proxy: gateway.docker.internal:3128 (shared)
    ├── Docker daemon: shared between agents
    ├── .sbx/04-agent-a-worktrees/
    │   ├── lab04-agent-a/   ← Agent A working here (branch: lab04-agent-a)
    │   └── lab04-agent-b/   ← Agent B working here (branch: lab04-agent-b)
    └── /Users/opscart/Source/docker-sandbox-devops/  (main worktree, read by both)
```

## Cleanup

Remove the test marker before cleanup:

```bash
rm .sbx/04-agent-a-worktrees/lab04-agent-a/agent-a-marker.txt
```

Exit the exec shell, then remove the sandbox:

```bash
# exits both agent sessions
sbx rm 04-agent-a
```

Removing the sandbox also removes the `.sbx/` worktree directory and all branches inside it — there is no separate cleanup per worktree. Verify:

```bash
ls .sbx/ 2>&1
```

Expected: empty. Both `lab04-agent-a` and `lab04-agent-b` worktrees are gone.

> **Confirmed:** `sbx rm 04-agent-b` returns `Error: sandbox '04-agent-b' not found` — there was never a separate sandbox for Agent B. One `sbx rm` on the parent sandbox cleans up everything.

## Next

- **Lab 05 — DevOps workloads:** run real DevOps tooling (kubectl, helm, terraform) inside a sandbox using a custom template. Verify the toolchain works and the network policy correctly allows cluster API access.