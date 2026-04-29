#!/bin/bash
# server-java-modern network smoke test
#
# Boots the server and verifies:
#   1. TCP port 43594 (game protocol) accepts connections
#   2. WS port 43494 (web client) completes HTTP upgrade to WebSocket
#   3. Server doesn't crash on malformed input
#
# Catches silent breakages like the Netty 4.1.33 -> 4.1.119 upgrade where
# OptionalSslHandler started rejecting null SslContext (commit 5ad9b3f14).
#
# Usage: ./smoke_test.sh
# Exits 0 on success, non-zero on any failure.

set -uo pipefail

cd "$(dirname "$0")"
SERVER_LOG=$(mktemp -t orsc-smoke.XXXXXX.log)
trap 'pkill -9 -f "com.openrsc.server.Server" 2>/dev/null; rm -f "$SERVER_LOG"' EXIT

echo "==> Starting server (ZGC)"
ant -q runserverzgc -DconfFile=local > "$SERVER_LOG" 2>&1 &

for i in $(seq 1 90); do
    if lsof -iTCP:43594 -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN &&
       lsof -iTCP:43494 -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN; then
        echo "    ports ready after ${i}s"
        break
    fi
    [ "$i" = 90 ] && { echo "FAIL: server never bound ports"; tail -20 "$SERVER_LOG"; exit 1; }
    sleep 1
done

pass=0
fail=0

echo "==> Test 1: TCP port 43594 accepts connection"
if python3 -c "
import socket
s = socket.create_connection(('127.0.0.1', 43594), timeout=3)
s.sendall(b'\\x00\\x01\\x20')  # minimal packet header
s.close()
" 2>/dev/null; then
    echo "    PASS"
    pass=$((pass+1))
else
    echo "    FAIL: TCP connect rejected"
    fail=$((fail+1))
fi

echo "==> Test 2: WS port 43494 completes HTTP upgrade"
response=$(python3 -c "
import socket
s = socket.create_connection(('127.0.0.1', 43494), timeout=3)
s.sendall(b'GET / HTTP/1.1\r\nHost: localhost:43494\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: binary\r\n\r\n')
s.settimeout(3)
print(s.recv(4096).decode(errors='replace'))
s.close()
" 2>/dev/null)
if echo "$response" | grep -q "101 Switching Protocols" && echo "$response" | grep -qi "sec-websocket-accept"; then
    echo "    PASS (101 Switching Protocols + accept hash)"
    pass=$((pass+1))
else
    echo "    FAIL: WS handshake did not complete"
    echo "    response: $(echo "$response" | head -3)"
    fail=$((fail+1))
fi

echo "==> Test 3: server does not crash on malformed TCP input"
python3 -c "
import socket
s = socket.create_connection(('127.0.0.1', 43594), timeout=2)
s.sendall(b'\\xff' * 512)
s.close()
" 2>/dev/null
sleep 1
if lsof -iTCP:43594 -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN; then
    echo "    PASS (still listening after garbage input)"
    pass=$((pass+1))
else
    echo "    FAIL: TCP port no longer listening"
    fail=$((fail+1))
fi

echo "==> Test 4: no uncaught exceptions on IO worker threads"
if grep -iE "NullPointerException|DecoderException.*Exception caught" "$SERVER_LOG" >/dev/null 2>&1; then
    echo "    FAIL: found exceptions in server log:"
    grep -iE "NullPointerException|DecoderException" "$SERVER_LOG" | head -3
    fail=$((fail+1))
else
    echo "    PASS"
    pass=$((pass+1))
fi

echo ""
echo "==> Results: $pass passed, $fail failed"
[ "$fail" = 0 ]
