#!/bin/bash
# ─── 2009scape Web Client Setup Script ───
# Clones the 2009scape server and 377 web client, then patches the client
# for rev 530 protocol compatibility.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== 2009scape Web Client Setup ==="
echo ""

# ── Step 1: Clone 2009scape server ──
if [ ! -d "$SCRIPT_DIR/2009scape" ]; then
    echo "[1/4] Cloning 2009scape server..."
    git clone --depth 1 https://gitlab.com/2009scape/2009scape.git "$SCRIPT_DIR/2009scape"
else
    echo "[1/4] 2009scape server already cloned, skipping."
fi

# ── Step 2: Clone the 377 web client as our base ──
if [ ! -d "$SCRIPT_DIR/client" ]; then
    echo "[2/4] Cloning runescape-web-client-377 as base client..."
    git clone --depth 1 https://github.com/reinismu/runescape-web-client-377.git "$SCRIPT_DIR/client"
else
    echo "[2/4] Web client already cloned, skipping."
fi

# ── Step 3: Apply rev 530 protocol patches ──
echo "[3/4] Applying rev 530 protocol patches..."

# Path-mirroring overlay: copy every file under client-patch/osrs/* to the same
# relative path under client/osrs/*. New files (Js5Cache.ts, PacketHandler530.ts, etc.)
# are dropped into place; modified files overwrite the upstream copy. This avoids
# the previous basename-based find which broke when two files shared a name (e.g.
# net/PacketConstants.ts vs util/PacketConstants.ts).
if [ -d "$SCRIPT_DIR/client-patch/osrs" ]; then
    echo "  Overlaying client-patch/osrs/ onto client/osrs/ (path-mirror)..."
    cp -R "$SCRIPT_DIR/client-patch/osrs/." "$SCRIPT_DIR/client/osrs/"
    find "$SCRIPT_DIR/client-patch/osrs" -name '*.ts' -type f | wc -l | xargs -I{} echo "    {} TypeScript files overlaid"
fi

# Legacy flat-layout support (old top-level Configuration.ts / Login530.ts /
# PacketConstants.ts at client-patch/ root). Skipped if osrs/ subtree exists,
# since those files are now in client-patch/osrs/.
if [ -d "$SCRIPT_DIR/client-patch" ] && [ ! -d "$SCRIPT_DIR/client-patch/osrs" ]; then
    for patch_file in "$SCRIPT_DIR"/client-patch/*.ts; do
        [ -f "$patch_file" ] || continue
        filename=$(basename "$patch_file")
        target=$(find "$SCRIPT_DIR/client" -name "$filename" -not -path "*/node_modules/*" | head -1)
        if [ -n "$target" ]; then cp "$patch_file" "$target"; fi
    done
fi

# ── Step 4: Build the web client ──
echo "[4/4] Building web client..."
cd "$SCRIPT_DIR/client"

if command -v npm &>/dev/null; then
    npm install
    npm run build
    echo ""
    echo "=== Build complete ==="
    echo "Client dist: $SCRIPT_DIR/client/dist/"
else
    echo "[!] npm not found. Install Node.js, then run:"
    echo "    cd $SCRIPT_DIR/client && npm install && npm run build"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start all services:"
echo "  cd $SCRIPT_DIR && docker compose up -d"
echo ""
echo "Then open http://localhost:8500 in your browser."
echo ""
echo "Ports:"
echo "  8500  - Web client (nginx)"
echo "  43595 - WebSocket proxy (browsers connect here)"
echo "  43594 - Game server TCP (direct)"
echo "  3307  - MySQL (localhost only)"
