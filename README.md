# pi-container

> Originally forked from `michaelhannecke/pi-container`. This variant swaps host-local MLX inference for OpenRouter behind a credential-injecting host proxy.

## Overview

A modern coding agent reads your files, runs shell commands, and installs whatever it decides it needs. On a work machine in a regulated context that is an unacceptable blast radius. This repository contains a **runnable setup** that closes it:

* **The agent runtime is sandboxed in its own VM** — Apple `container` gives each container a lightweight VM, not shared-kernel namespaces.
* **The host stays clean** — no Node, no npm, no `pi` binary; the agent lives only inside an image and is discarded on exit.

## Architecture

```txt
┌─────────────────────────────┐        ┌──────────────────────────────┐
│ Host (macOS, Apple Silicon) │        │ Apple Container (Linux VM)   │
│                             │        │                              │
│  Caddy proxy :8080          │◄──────►│  pi-coding-agent             │
│  injects Authorization      │ Bridge │  (Node, ripgrep, git)        │
│  OPENROUTER_KEY in env       │        │  Workspace: /workspace       │
│         │                   │        │  apiKey: "not-required"      │
│         ▼                   │        │  (no key in auth.json)       │
│  openrouter.ai              │        └──────────────────────────────┘
└─────────────────────────────┘
```

* **Inference** runs on OpenRouter. The agent reaches it only through a host-side proxy that injects the `Authorization` header — the API key lives in the proxy's environment on the host and never enters the container.
* **Tool-calling sandbox** runs in the container — a clean split between credential holder and agent runtime.
* **pi** reaches the host only over the container bridge; the gateway IP is environment-dependent and discovered at runtime, never hardcoded.

## Table of contents

* [Repository structure](#repository-structure)
* [Prerequisites](#prerequisites)
* [Quickstart](#quickstart)
* [Configuration](#configuration)
* [Troubleshooting](#troubleshooting)
* [Notes & caveats](#notes--caveats)
* [License](#license)

## Repository structure

```txt
.
├── Containerfile                                 # node-current-slim + pi installed globally
├── Caddyfile                                     # host proxy that injects the OpenRouter auth header
├── pi-config/
│   ├── AGENTS.md                                 # global agent rules (container variant)
│   ├── settings.json                             # default provider / model / thinking level
│   ├── models.json                               # provider + model definition (points at the proxy)
│   ├── auth.json                                 # empty — no credential crosses the mount
│   └── extensions/
│       └── protected-paths/
│           └── index.ts                          # tool-call guardrail for sensitive paths
└── scripts/
    ├── build.sh                                  # container build
    └── run.sh                                    # container run with the right mounts
```

`pi-config/` is mounted into the container at runtime as the agent's config directory. Its `sessions/`, `cache/`, and `logs/` subdirectories are produced by pi during a session and are git-ignored — runtime artifacts, not configuration.

## Prerequisites

* **macOS 26 (Tahoe) on Apple Silicon, recommended.** `container` technically runs on macOS 15, but its networking is significantly limited there and this whole setup lives or dies on container-to-host networking. Treat macOS 15 as unsupported here.
* Apple `container` CLI installed (`container --version` must answer).
* **macOS Local Network permission grantable** — recent macOS gates local traffic behind a privacy prompt; it must be allowed for the container runtime.
* **Caddy on the host** (`brew install caddy`) — a single static binary, so the host stays Node-free. It runs the credential-injecting proxy.
* **An OpenRouter API key**, ideally scoped with a spend cap and a model allowlist as blast-radius control. It is supplied to Caddy via the `OPENROUTER_KEY` environment variable and never written into the image or the mounted config.
* **No Node and no npm on the host** — that is the point; the agent lives only in the image.

## Quickstart

### 1. Build the image

```bash
./scripts/build.sh
```

Produces `pi-coding-agent:openrouter` (override the tag with `IMAGE_TAG=...`).

### 2. Run the agent

```bash
PROJECT_DIR=~/projects/your-repo ./scripts/run.sh
```

If `PROJECT_DIR` is not provided, it will default to the current directory via `pwd`.`

The default provider and model come from `pi-config/settings.json`; pass `--model openrouter-proxy/qwen3-coder` to override.

`run.sh` mounts exactly two things, and nothing else crosses the boundary:

* `~/.pi/agent` → `/home/pi/.pi/agent` (provider config, `AGENTS.md`, extensions)
* `$PROJECT_DIR` → `/workspace` (the project being worked on)

`--rm` discards the VM and its writable layer on exit. The host is byte-for-byte unchanged.

## Configuration

### Host proxy

Started in the run script but can be run separately for testing/debugging. It is a Caddy instance with this `Caddyfile`:

```bash
OPENROUTER_KEY=sk-or-v1-... caddy run --config ./Caddyfile
```

Caddy listens on `0.0.0.0:8080` and forwards to `openrouter.ai`, adding the `Authorization` header from `OPENROUTER_KEY`. Bind to `0.0.0.0` (the [Caddyfile](Caddyfile) already does): the container is a separate VM and cannot reach host `127.0.0.1`.

### Host bridge IP

From inside the container, the host is reachable via the bridge's default gateway. The address is environment-dependent, so discover it instead of assuming a subnet. The image's entrypoint is `pi`, so override it with `--entrypoint sh` for a one-off command:

```bash
container run --rm --entrypoint sh pi-coding-agent:openrouter -c "ip route | awk '/default/ {print \$3}'"
```

If the printed gateway differs from the default in `pi-config/models.json`, update `providers.openrouter-proxy.baseUrl` accordingly (keep the `:8080/api/v1` suffix — OpenRouter's API path includes `/api`).

### Credential proxy — `Caddyfile`

The OpenRouter key never enters the container. Caddy runs on the host, holds the key in its `OPENROUTER_KEY` environment variable, and injects `Authorization: Bearer ...` on every request it forwards to `openrouter.ai`. pi inside the container points at this proxy and carries no secret. Removing the key from the agent's reach is the real win over file/env tricks — the agent can't exfiltrate a credential it never receives.

### Models & provider — `pi-config/models.json`

Defines the `openrouter-proxy` provider with `api: "openai-completions"` and a nested `models` array. `apiKey` is `"not-required"`: the proxy supplies the real credential, so none lives in the mounted config. `baseUrl` points at the host bridge (`http://<gateway>:8080/api/v1`) — the same bridge slot the original MLX server used. The `/api/v1` path matches OpenRouter's real API path, which the proxy passes through unchanged. Each model's `id` is what gets forwarded to OpenRouter (e.g. `qwen/qwen3-coder-next`); `name` (`openrouter-proxy/qwen3-coder`) is the handle `--model` and `settings.json` match against.

### Defaults — `pi-config/settings.json`

`defaultProvider` (`openrouter-proxy`), `defaultModel` (`openrouter-proxy/qwen3-coder`), and `defaultThinkingLevel` so `run.sh` needs no `--model` flag. `pi-config/auth.json` is intentionally empty (`{}`) — there is no key to mount.

### Global agent rules — `pi-config/AGENTS.md`

Loaded into every session as the operating contract: runs in an Apple container, host not directly reachable, file operations only affect `/workspace`, model reached only over the bridge, no external calls or telemetry without explicit instruction, and tool discipline (`read` before `edit`, `write` only for new files, no `npm install` without confirmation).

### Extension — `protected-paths`

A defense-in-depth backstop at `pi-config/extensions/protected-paths/index.ts`. It hooks pi's `tool_call` event and forces a confirmation (or hard-denies) for sensitive directories (`~/.ssh`, `~/.aws`, `~/.config/gcloud`, `/run/secrets`, `/etc`) and patterns (`.env`, `credentials.json`, `id_rsa`, `id_ed25519`, `*.pem`, `*.p12`) — inspecting both file-tool paths and `bash` commands. The container is the strong boundary; this is the seatbelt for the day someone widens a mount.

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| Requests hang/fail with no error, empty reply | **Local Network permission not granted.** *System Settings → Privacy & Security → Local Network* — enable the container runtime, then fully quit and reopen the requesting app. Most common first-run failure on recent macOS. |
| "Can't reach the model" | **Proxy bound to loopback.** The container is a separate VM and cannot reach host `127.0.0.1`. The `Caddyfile` binds `0.0.0.0:8080` — confirm Caddy is actually running. |
| Connection refused / wrong address | **Wrong bridge IP.** `192.168.64.1` is only a default — re-run the `ip route` discovery and use the actual gateway. |
| `401`/`403` from the model | **Key not in Caddy's environment.** Confirm `OPENROUTER_KEY` is set in the shell running `caddy`. OpenRouter may also want `HTTP-Referer`/`X-Title` — add them as `header_up` lines in the `Caddyfile`. |
| Files not owned by your macOS user | **Expected.** The container writes as UID 1000; your host user is typically UID 501. In the pi workflow (edits go through the `edit` tool) this is acceptable. |
| `models.json` loads but chat fails on role/params | If a model rejects the `developer` role or `reasoning_effort`, add provider-level `"compat": { "supportsDeveloperRole": false, "supportsReasoningEffort": false }` (see pi's `models.md`). |

## Notes & caveats

* **The key never enters the container** — it lives only in Caddy's environment on the host, and `auth.json` is empty. That removes the credential from the agent's reach, which is stronger than any in-container file/env trick.
* **The proxy is not *enforced*.** Apple `container` has no clean per-container egress filter, so the design relies on the agent having no key rather than on blocking direct routes to `openrouter.ai`. Scope the OpenRouter key (spend cap + model allowlist) as the real blast-radius control; for hard egress lockdown, use a host `pf` rule keyed to the container subnet.
* **Bridge IP is environment-dependent.** The address in `models.json` is an example default, discovered at runtime; it can vary by `container` version.
* **macOS version matters.** Container-to-host networking is the linchpin; older macOS limits it severely.

## License

No license specified. The contents and code in this repository are **draft material**.
