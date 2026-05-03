#!/bin/bash
set -e

echo "=== OpenRSC Server Startup ==="
echo ""

# Start the status web server in background (port 5000)
python3 status_server.py &
STATUS_PID=$!
echo "Status web server started (PID $STATUS_PID)"

# Build the server if jars are missing
cd server
if [ ! -f core.jar ] || [ ! -f plugins.jar ]; then
    echo "Building server..."
    ant compile_core
    ant compile_plugins
    echo "Build complete."
else
    echo "Jars already built, skipping compile."
fi

echo ""
echo "Starting OpenRSC game server with PostgreSQL-compatible JDBC config (preservation world)..."
echo "TCP port: 43594 | WebSocket port: 43494"
echo ""

ant runserver -DconfFile=local -DcoloredLogging=false
