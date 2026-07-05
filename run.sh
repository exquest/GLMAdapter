#!/usr/bin/env bash
# GMLAdapter — start the LiteLLM proxy serving GLM-5.2.
#
# The Together key is resolved into the process env at launch, in order:
#   1. TOGETHER_API_KEY already exported in the environment
#   2. macOS Keychain   : security find-generic-password -s TOGETHER_API_KEY
#   3. Linux libsecret  : secret-tool lookup service TOGETHER_API_KEY
#   4. .env file next to this script (gitignored — never commit it)
# Prefer 2/3: the key never touches disk. Stop with Ctrl-C.
#
# Port: 4000 by default; override with GML_PORT=4123 ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

command -v litellm >/dev/null 2>&1 || {
  echo "litellm not found — install with:  pip install 'litellm[proxy]'" >&2
  exit 1
}

PORT="${GML_PORT:-4000}"

if [ -z "${TOGETHER_API_KEY:-}" ]; then
  case "$(uname -s)" in
    Darwin) TOGETHER_API_KEY="$(security find-generic-password -s TOGETHER_API_KEY -w 2>/dev/null || true)" ;;
    Linux)  command -v secret-tool >/dev/null 2>&1 \
              && TOGETHER_API_KEY="$(secret-tool lookup service TOGETHER_API_KEY 2>/dev/null || true)" || true ;;
  esac
fi
if [ -z "${TOGETHER_API_KEY:-}" ] && [ -f .env ]; then
  set -a; . ./.env; set +a
fi
if [ -z "${TOGETHER_API_KEY:-}" ]; then
  echo "TOGETHER_API_KEY not found. Provide it one of these ways:" >&2
  echo "  macOS : security add-generic-password -U -s TOGETHER_API_KEY -a \"\$USER\" -w 'YOUR_KEY'" >&2
  echo "  Linux : echo -n 'YOUR_KEY' | secret-tool store --label='Together AI' service TOGETHER_API_KEY" >&2
  echo "  any   : cp .env.example .env   # then edit .env (gitignored)" >&2
  exit 1
fi
export TOGETHER_API_KEY

exec litellm --config ./litellm.config.yaml --port "$PORT" "$@"
