#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-10.8.0.1}"
KEY="${HETZNER_SSH_KEY:-$HOME/.ssh/hetzner_phantom}"

echo "== Local raw TCP handshake probe (${HOST}:43600) =="
python3 - "$HOST" <<'PY'
import socket
import sys

host = sys.argv[1]
s = socket.socket()
s.settimeout(4)
try:
    s.connect((host, 43600))
    s.sendall(bytes([14, 0]))
    data = s.recv(16)
    print(f"recv {data.hex()} ({len(data)} bytes)")
    if len(data) != 9 or data[0] != 0:
        raise SystemExit("unexpected handshake response")
finally:
    s.close()
PY

echo
echo "== Hetzner containers and recent relevant logs =="
ssh -i "$KEY" -o ConnectTimeout=10 "root@$HOST" \
  "cd /opt/2009scape-web && \
   docker ps --format '{{.Names}} {{.Status}} {{.Ports}}' && \
   echo --- && \
   docker logs --since 10m 2009scape-server 2>&1 | \
     grep -v PulseRunner | grep -v OutOfMemory | \
     grep -iE 'configuring|disconnect|playtest|wildy|cheat|invalid|exception|n i o|NioReactor' | tail -40 || true"
