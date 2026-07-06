# GLMAdapter shell helpers — works in zsh and bash. Source from your rc file:
#   source /path/to/GLMAdapter/shell/glm.sh
#
#   glm         Claude Code running on GLM-5.2 through the local proxy
#   glm-health  one-shot health check of the whole stack
#
# Port defaults to 4000; export GLM_PORT to match a custom run.sh port.

glm() {
  ANTHROPIC_BASE_URL="http://localhost:${GLM_PORT:-4000}" \
  ANTHROPIC_API_KEY="sk-anything" \
  claude --model glm-5.2 "$@"
}

glm-health() {
  local port="${GLM_PORT:-4000}" ok=0 fail=0
  local g=$'\033[32m' r=$'\033[31m' y=$'\033[33m' n=$'\033[0m'
  echo "GLMAdapter / GLM-5.2 health (port ${port}):"

  # 1. service (best-effort; skipped if you run the proxy manually)
  case "$(uname -s)" in
    Darwin)
      if launchctl list 2>/dev/null | grep -q com.glmadapter.litellm; then
        echo "  ${g}v${n} launchd agent com.glmadapter.litellm running"; ok=$((ok+1))
      else echo "  ${y}-${n} launchd agent not loaded (fine if running ./run.sh manually)"; fi ;;
    Linux)
      if systemctl --user is-active --quiet glmadapter-litellm 2>/dev/null; then
        echo "  ${g}v${n} systemd unit glmadapter-litellm active"; ok=$((ok+1))
      else echo "  ${y}-${n} systemd unit not active (fine if running ./run.sh manually)"; fi ;;
  esac

  # 2. proxy answering
  if curl -s --max-time 5 -H "Authorization: Bearer sk-anything" \
       "http://localhost:${port}/v1/models" | grep -q glm-5.2; then
    echo "  ${g}v${n} proxy answering on :${port} and serving glm-5.2"; ok=$((ok+1))
  else
    echo "  ${r}x${n} no proxy on :${port}  (start it: ./run.sh, or ./install-service.sh)"; fail=$((fail+1))
  fi

  # 3. key reachable
  local have_key=""
  [ -n "${TOGETHER_API_KEY:-}" ] && have_key="env"
  if [ -z "$have_key" ]; then
    case "$(uname -s)" in
      Darwin) security find-generic-password -s TOGETHER_API_KEY -w >/dev/null 2>&1 && have_key="Keychain" ;;
      Linux)  command -v secret-tool >/dev/null 2>&1 \
                && [ -n "$(secret-tool lookup service TOGETHER_API_KEY 2>/dev/null)" ] && have_key="libsecret" ;;
    esac
  fi
  if [ -n "$have_key" ]; then
    echo "  ${g}v${n} TOGETHER_API_KEY available (${have_key})"; ok=$((ok+1))
  else
    echo "  ${y}-${n} TOGETHER_API_KEY not visible from this shell (proxy may still hold one)"
  fi

  # 4. live generation — the real end-to-end proof
  local reply
  reply=$(curl -s --max-time 60 "http://localhost:${port}/v1/chat/completions" \
    -H "Authorization: Bearer sk-anything" -H "Content-Type: application/json" \
    -d '{"model":"glm-5.2","messages":[{"role":"user","content":"Reply with exactly: OK"}],"max_tokens":512}' 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("choices",[{}])[0].get("message",{}).get("content",""))' 2>/dev/null)
  if [ -n "$reply" ]; then
    echo "  ${g}v${n} live generation -> ${reply}"; ok=$((ok+1))
  else
    echo "  ${r}x${n} live generation failed (check proxy.log next to run.sh)"; fail=$((fail+1))
  fi

  echo "  -- ${ok} ok, ${fail} fail"
  [ "$fail" -eq 0 ]
}
