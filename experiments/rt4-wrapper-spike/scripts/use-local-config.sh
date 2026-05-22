#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLIC_DIR="$SPIKE_DIR/public"

cat > "$PUBLIC_DIR/config.json" <<'JSON'
{
    "ip_management": "127.0.0.1",
    "ip_address": "127.0.0.1",
    "world": 1,
    "server_port": 43600,
    "wl_port": 43600,
    "js5_port": 43600,
    "mouseWheelZoom": true,
    "pluginsFolder": "plugins"
}
JSON

cat > "$PUBLIC_DIR/wrapper-config.js" <<'JS'
window.RT4_WRAPPER_CONFIG = {
  debug: false,
  websocketUrl: "ws://127.0.0.1:{port}",
  tailscaleControlUrl: "",
  tailscaleAuthKey: "",
  useTailscaleLogin: false
};
JS

echo "Wrote local RT4 wrapper config to $PUBLIC_DIR/config.json"
echo "Wrote local RT4 wrapper runtime config to $PUBLIC_DIR/wrapper-config.js"
