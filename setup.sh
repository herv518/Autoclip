#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${AI_TEXT_MODEL:-gemma3:2b}"
EXTRA_MODELS="${EXTRA_OLLAMA_MODELS:-}"

log() {
  echo "[+] $*"
}

warn() {
  echo "[!] $*" >&2
}

die() {
  warn "$*"
  exit 1
}

check_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "Missing command: $cmd"
    return 1
  fi
  return 0
}

pull_model_if_missing() {
  local model="$1"
  [[ -n "$model" ]] || return 0

  if ollama show "$model" >/dev/null 2>&1; then
    log "Ollama model already available: $model"
    return 0
  fi

  log "Pulling Ollama model: $model"
  ollama pull "$model"
}

log "Autoclip setup started"

missing=0
for base_cmd in bash ffmpeg curl sftp python3; do
  if ! check_cmd "$base_cmd"; then
    missing=1
  fi
done
if [[ "$missing" -eq 1 ]]; then
  warn "Install missing tools first (macOS hint: brew install ffmpeg python && install OpenSSH if needed)."
fi

if ! command -v ollama >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    die "Ollama is missing. Install with: brew install --cask ollama"
  fi
  die "Ollama is missing. Install Ollama Desktop and retry."
fi

if ! ollama list >/dev/null 2>&1; then
  die "Ollama daemon not reachable. Start the Ollama app (or 'ollama serve') and rerun setup.sh"
fi

pull_model_if_missing "$MODEL"

if [[ -n "$EXTRA_MODELS" ]]; then
  IFS=',' read -r -a models <<< "$EXTRA_MODELS"
  for model in "${models[@]}"; do
    model="$(printf '%s' "$model" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "$model" ]] || continue
    pull_model_if_missing "$model"
  done
fi

chmod +x \
  "$ROOT_DIR/autoclip.sh" \
  "$ROOT_DIR/fetch_data.sh" \
  "$ROOT_DIR/generate_sales_text.sh" \
  "$ROOT_DIR/pipeline/run.sh" \
  "$ROOT_DIR/pipeline/bin/generate_sales_text.sh" \
  "$ROOT_DIR/pipeline/bin/build_vehicle_facts.sh"

log "Setup complete"
log "Quick test:"
log "  ./generate_sales_text.sh \"Kilometerstand: 45.000 km\nErstzulassung: 2023\nUnfallfrei\""
