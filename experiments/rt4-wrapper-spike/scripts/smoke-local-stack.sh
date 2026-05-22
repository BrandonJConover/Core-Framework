#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${RT4_SMOKE_LOG_DIR:-/tmp/rt4-wrapper-smoke-stack-$(date +%s)}"
SERVER_WARMUP_MS="${RT4_SMOKE_SERVER_WARMUP_MS:-135000}"

mkdir -p "$LOG_DIR"

server_pid=""
wrapper_pid=""

cleanup() {
  if [ -n "$wrapper_pid" ] && kill -0 "$wrapper_pid" >/dev/null 2>&1; then
    kill "$wrapper_pid" >/dev/null 2>&1 || true
    wait "$wrapper_pid" >/dev/null 2>&1 || true
    kill_listener_on_port 43600
    kill_listener_on_port 43601
  fi
  if [ -n "$server_pid" ] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
}
kill_listener_on_port() {
  local port="$1"
  local pids
  pids="$(lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    echo "Stopping stale listener(s) on port $port: $pids"
    kill $pids >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

wait_for_port() {
  local port="$1"
  local name="$2"
  local timeout="${3:-90}"
  local start
  start="$(date +%s)"
  while true; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
    if [ "$(( $(date +%s) - start ))" -ge "$timeout" ]; then
      echo "Timed out waiting for $name on port $port." >&2
      echo "Logs are in $LOG_DIR" >&2
      return 1
    fi
    sleep 1
  done
}

if ! lsof -nP -iTCP:43595 -sTCP:LISTEN >/dev/null 2>&1; then
  kill_listener_on_port 43600
  kill_listener_on_port 43601
  bash "$SCRIPT_DIR/start-local-server.sh" >"$LOG_DIR/server.log" 2>&1 &
  server_pid="$!"
  wait_for_port 43595 "2009scape server" 120
  if [ "$SERVER_WARMUP_MS" -gt 0 ]; then
    echo "Warming newly started 2009scape server for ${SERVER_WARMUP_MS}ms..."
    sleep "$(awk "BEGIN { printf \"%.3f\", $SERVER_WARMUP_MS / 1000 }")"
  fi
fi

if ! lsof -nP -iTCP:8787 -sTCP:LISTEN >/dev/null 2>&1; then
  kill_listener_on_port 43600
  kill_listener_on_port 43601
  bash "$SCRIPT_DIR/start-local-wrapper.sh" >"$LOG_DIR/wrapper.log" 2>&1 &
  wrapper_pid="$!"
  wait_for_port 8787 "wrapper HTTP server" 30
  wait_for_port 43600 "wrapper base WebSocket bridge" 30
  wait_for_port 43601 "wrapper JS5 WebSocket bridge" 30
fi

bash "$SCRIPT_DIR/smoke-local-wrapper.sh"

echo "Stack smoke logs: $LOG_DIR"
