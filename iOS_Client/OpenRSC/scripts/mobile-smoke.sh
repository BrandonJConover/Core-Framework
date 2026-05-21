#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${DEVICE_ID:-00008130-000805D10AF0001C}"
BUNDLE_ID="${BUNDLE_ID:-com.openrsc.client}"
SECONDS_TO_RUN="${SECONDS_TO_RUN:-60}"
LOG_PATH="${LOG_PATH:-/tmp/openrsc-mobile-smoke.log}"

echo "[smoke] device=$DEVICE_ID bundle=$BUNDLE_ID seconds=$SECONDS_TO_RUN"

echo "[smoke] installed OpenRSC apps:"
xcrun devicectl device info apps --device "$DEVICE_ID" \
  | grep -E 'OpenRSC|Bundle Identifier|Name' || true

echo "[smoke] network probe: 10.8.0.1:43594"
if nc -vz -G 5 10.8.0.1 43594 >/tmp/openrsc-mobile-smoke-nc.log 2>&1; then
  cat /tmp/openrsc-mobile-smoke-nc.log
else
  cat /tmp/openrsc-mobile-smoke-nc.log
  echo "[smoke] warning: server not reachable from this Mac; the phone app will likely stop before login."
fi

echo "[smoke] launching app and capturing console to $LOG_PATH"
set +e
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  --console \
  --timeout "$SECONDS_TO_RUN" \
  "$BUNDLE_ID" 2>&1 | tee "$LOG_PATH"
status=${PIPESTATUS[0]}
set -e

echo "[smoke] summary:"
grep -E '\[Engine\] Connected!|\[Engine\] Login result|\[Packet\] Received opcode 191|\[World\] Generated landscape|\[Render\] Scene tick|\[Scene\] [0-9]+ polys|\[NPC\]' "$LOG_PATH" || true

if ! grep -q '\[Engine\] Connected!' "$LOG_PATH"; then
  echo "[smoke] FAIL: app launched but did not reach TCP Connected. Check server/VPN routing before renderer gameplay testing."
  exit 2
fi

if ! grep -q '\[Engine\] Login result: success' "$LOG_PATH"; then
  echo "[smoke] FAIL: TCP connected but login did not succeed."
  exit 3
fi

if ! grep -Eq '\[Render\] Scene tick|\[World\] Generated landscape|\[Scene\] [0-9]+ polys' "$LOG_PATH"; then
  echo "[smoke] FAIL: login succeeded but no 3D scene render evidence was observed."
  exit 4
fi

echo "[smoke] PASS: connected, logged in, and rendered the 3D scene."
exit 0
