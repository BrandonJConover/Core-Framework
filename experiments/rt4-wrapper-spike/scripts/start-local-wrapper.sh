#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLIC_DIR="$SPIKE_DIR/public"

HTTP_HOST="${HTTP_HOST:-127.0.0.1}"
HTTP_PORT="${HTTP_PORT:-8787}"
WS_HOST="${WS_HOST:-127.0.0.1}"
WS_BASE_PORT="${WS_BASE_PORT:-43600}"
WS_JS5_PORT="${WS_JS5_PORT:-43601}"
TCP_HOST="${TCP_HOST:-127.0.0.1}"
TCP_PORT="${TCP_PORT:-43595}"

bash "$SCRIPT_DIR/use-local-config.sh"

require_free_port() {
  local port="$1"
  local name="$2"
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "$name port $port is already in use." >&2
    return 1
  fi
}

require_free_port "$HTTP_PORT" "HTTP"
require_free_port "$WS_BASE_PORT" "Base WebSocket bridge"
require_free_port "$WS_JS5_PORT" "JS5 WebSocket bridge"

child_pids=()

cleanup() {
  if [ "${#child_pids[@]}" -gt 0 ]; then
    kill "${child_pids[@]}" >/dev/null 2>&1 || true
    wait "${child_pids[@]}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

python3 -u "$SCRIPT_DIR/ws_tcp_bridge.py" \
  --listen-host "$WS_HOST" \
  --listen-port "$WS_BASE_PORT" \
  --target-host "$TCP_HOST" \
  --target-port "$TCP_PORT" &
child_pids+=("$!")

python3 -u "$SCRIPT_DIR/ws_tcp_bridge.py" \
  --listen-host "$WS_HOST" \
  --listen-port "$WS_JS5_PORT" \
  --target-host "$TCP_HOST" \
  --target-port "$TCP_PORT" &
child_pids+=("$!")

python3 "$SCRIPT_DIR/serve.py" \
  --host "$HTTP_HOST" \
  --port "$HTTP_PORT" \
  --directory "$PUBLIC_DIR" &
child_pids+=("$!")

cat <<EOF
Local RT4 wrapper is ready:
  http://$HTTP_HOST:$HTTP_PORT/

Expected local game server:
  $TCP_HOST:$TCP_PORT

WebSocket bridge:
  ws://$WS_HOST:$WS_BASE_PORT -> $TCP_HOST:$TCP_PORT
  ws://$WS_HOST:$WS_JS5_PORT -> $TCP_HOST:$TCP_PORT

Press Ctrl-C to stop the wrapper and bridge.
EOF

wait "${child_pids[@]}"
