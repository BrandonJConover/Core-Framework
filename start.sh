#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT_DIR/server"

echo "=== OpenRSC Server Startup ==="
echo

python3 "$ROOT_DIR/status_server.py" &
STATUS_PID=$!
trap 'kill "$STATUS_PID" 2>/dev/null || true' EXIT
echo "Status web server started on port 5000 (PID $STATUS_PID)"

cd "$SERVER_DIR"

if [ ! -f local.conf ]; then
    cp default.conf local.conf
    echo "Created server/local.conf from default.conf"
fi

if [ ! -f core.jar ] || [ ! -f plugins.jar ]; then
    echo "Building server jars..."
    ant compile_core
    ant compile_plugins
    echo "Build complete."
else
    echo "Server jars already built, skipping compile."
fi

echo
echo "Starting OpenRSC preservation server"
echo "TCP port: 43594 | WebSocket port: 43494 | Status port: 5000"
echo

ant runserver -DconfFile=local -DcoloredLogging=false
