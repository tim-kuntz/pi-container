#!/usr/bin/env bash
# Starts pi in an Apple container.
#
# Expects two mounts:
#   - pi-config/    -> /home/pi/.pi/agent  (provider config, AGENTS.md, extensions)
#   - $PROJECT_DIR  -> /workspace          (the project to work on)
#
# Example:
#   PROJECT_DIR=~/projects/small-test-repo ./scripts/run.sh --model mlx-local/qwen3-coder
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-pi-coding-agent:openrouter}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "PROJECT_DIR='$PROJECT_DIR' does not exist." >&2
  exit 1
fi

container run \
  --rm \
  --interactive \
  --tty \
  --volume "~/.pi/agent:/home/pi/.pi/agent" \
  --volume "$PROJECT_DIR:/workspace" \
  --workdir /workspace \
  --entrypoint /bin/bash \
  "$IMAGE_TAG"
# "$@"
