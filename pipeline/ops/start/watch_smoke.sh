#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

WATCH_DRY_RUN="${WATCH_DRY_RUN:-1}" \
WATCH_ONESHOT="${WATCH_ONESHOT:-1}" \
  "$ROOT/bin/watch_input_frames.sh"
