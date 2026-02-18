#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ID> [SOURCE_URL]"
  exit 1
fi

exec "$ROOT/run.sh" "$@"
