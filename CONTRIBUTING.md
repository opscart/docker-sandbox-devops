# Contributing

Thanks for your interest. This repo is actively maintained as an independent engineering exploration of Docker Sandboxes — contributions welcome.

## Filing issues

Open an issue if:

- A lab no longer reproduces against the current `sbx` version
- You found a friction point worth adding to the friction log
- You have a kit, template, or scenario you'd like to contribute
- You spotted a factual error in the architecture notes, threat model, or comparison

When filing, please include:

- `sbx version` output (both client and server)
- Host OS and architecture (e.g., macOS 14.5, Apple Silicon)
- The lab, scenario, or doc you're referring to
- Expected vs. actual behavior with real terminal output (no reconstructed stdout)

## Submitting PRs

- Branch from `main`, target `main`
- One topic per PR (one lab, one kit, one doc change)
- Update [`tested-with.md`](./tested-with.md) if your change affects reproducibility
- Add a dated entry to [`CHANGELOG.md`](./CHANGELOG.md) under `Unreleased`
- New labs follow the existing structure: objective, prerequisites, sbx version verified, steps with expected output, observations, what's happening internally, cleanup

## Style

- Markdown only for docs; no embedded HTML except where Mermaid syntax requires
- Prefer Mermaid for diagrams (renders inline on GitHub); Excalidraw SVG for hand-drawn-style architecture
- No invented terminal output. Paste real output from real runs. Redact secrets, never paths or commit hashes
- Vendor-neutral tone. This is an engineering evaluation, not promotional content
- Capture friction in real time, not from memory after the fact

## Scope reminder

This repo focuses on Docker Sandboxes (the `sbx` CLI) for local AI coding agent isolation. Adjacent topics (cloud sandboxes, container runtime internals, agent prompt engineering) are in scope only where they directly inform the evaluation.

## Disclaimer

Not affiliated with Docker, Inc. All trademarks belong to their respective owners.