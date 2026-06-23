#!/usr/bin/env bash
# Starts pi in an Apple container.
#
# Expects two mounts:
#   - pi-config/    -> /home/pi/.pi/agent  (provider config, AGENTS.md, extensions)
#   - $PROJECT_DIR  -> /workspace          (the project to work on)
#
# Also ensures the host-side Caddy proxy (Caddyfile) is running so pi can reach
# OpenRouter without the API key ever entering the container. The proxy is a
# shared daemon: it is started once and left running, so multiple concurrent
# containers reuse the same instance. It is NOT stopped on exit (`caddy stop`).
#
# Example:
#   OPENROUTER_KEY=sk-or-v1-... PROJECT_DIR=~/projects/small-test-repo ./scripts/run.sh
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-pi-coding-agent:openrouter}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
# Must match the listen address in Caddyfile and the baseUrl in models.json.
PROXY_PORT=8080

if [ ! -d "$PROJECT_DIR" ]; then
  echo "PROJECT_DIR='$PROJECT_DIR' does not exist." >&2
  exit 1
fi

# --- host proxy ------------------------------------------------------------
# Start Caddy only if nothing is already listening on the proxy port. This
# keeps a single shared proxy across multiple containers instead of trying
# (and failing) to bind the port again.
if lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Proxy already listening on :$PROXY_PORT — reusing it." >&2
else
  if [ -z "${OPENROUTER_KEY:-}" ]; then
    echo "OPENROUTER_KEY is not set; cannot start the proxy on :$PROXY_PORT." >&2
    echo "Export it first:  OPENROUTER_KEY=sk-or-v1-... $0" >&2
    exit 1
  fi
  if ! command -v caddy >/dev/null 2>&1; then
    echo "caddy not found on PATH (brew install caddy)." >&2
    exit 1
  fi
  echo "Starting Caddy proxy on :$PROXY_PORT ..." >&2
  # `caddy start` daemonizes and returns, so the proxy outlives this script
  # and is shared by later containers. Stop it manually with `caddy stop`.
  OPENROUTER_KEY="$OPENROUTER_KEY" caddy start --config "$REPO_ROOT/Caddyfile"
fi
# ---------------------------------------------------------------------------
# Add the following container option if you don't want to start `pi`
# immediately and would rather get a shell for debugging:
#   --entrypoint /bin/bash \

container run \
  --rm \
  --interactive \
  --tty \
  --volume "$REPO_ROOT/pi-config:/home/pi/.pi/agent" \
  --volume "$PROJECT_DIR:/workspace" \
  --workdir /workspace \
  "$IMAGE_TAG" \
  "$@"
