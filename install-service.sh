#!/usr/bin/env bash
# Install GMLAdapter as an always-on user service:
#   macOS -> launchd LaunchAgent (starts at login, self-heals)
#   Linux -> systemd user unit  (starts at login, Restart=always)
# Re-run any time; it re-renders the template and restarts the service.
set -euo pipefail
cd "$(dirname "$0")"
REPO_DIR="$(pwd)"

LITELLM_BIN="$(command -v litellm || true)"
[ -n "$LITELLM_BIN" ] || { echo "litellm not found — pip install 'litellm[proxy]' first" >&2; exit 1; }
LITELLM_DIR="$(dirname "$LITELLM_BIN")"

case "$(uname -s)" in
  Darwin)
    PLIST="$HOME/Library/LaunchAgents/com.gmladapter.litellm.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    sed -e "s|__REPO_DIR__|$REPO_DIR|g" -e "s|__LITELLM_DIR__|$LITELLM_DIR|g" \
      service/com.gmladapter.litellm.plist > "$PLIST"
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "Loaded launchd agent com.gmladapter.litellm"
    echo "  logs   : $REPO_DIR/proxy.log"
    echo "  stop   : launchctl unload $PLIST"
    echo "  restart: launchctl kickstart -k gui/\$(id -u)/com.gmladapter.litellm"
    ;;
  Linux)
    UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
    sed -e "s|__REPO_DIR__|$REPO_DIR|g" -e "s|__LITELLM_DIR__|$LITELLM_DIR|g" \
      service/gmladapter-litellm.service > "$UNIT_DIR/gmladapter-litellm.service"
    systemctl --user daemon-reload
    systemctl --user enable --now gmladapter-litellm.service
    echo "Enabled systemd user unit gmladapter-litellm"
    echo "  logs   : journalctl --user -u gmladapter-litellm -f"
    echo "  stop   : systemctl --user stop gmladapter-litellm"
    echo "  restart: systemctl --user restart gmladapter-litellm"
    ;;
  *) echo "Unsupported OS: $(uname -s) — run ./run.sh manually" >&2; exit 1 ;;
esac
