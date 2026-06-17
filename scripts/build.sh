#!/usr/bin/env bash
# Builds the pi-coding-agent image for the Apple container.
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-pi-coding-agent:openrouter}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

container build \
  --tag "$IMAGE_TAG" \
  --file "$REPO_ROOT/Containerfile" \
  "$REPO_ROOT"
