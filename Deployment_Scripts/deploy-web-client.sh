#!/bin/bash
# deploy-web-client.sh
#
# Deploys the rsc-c WebAssembly web client to the Hetzner VPS.
# Run this on the Hetzner server (not locally).
#
# Prerequisites:
#   - Nginx installed (apt install nginx)
#   - certbot installed (apt install certbot python3-certbot-nginx)
#   - DNS A record for DOMAIN pointing at this server
#   - OpenRSC server running with want_feature_websockets: true
#   - ssl_server_cert_path / ssl_server_key_path set in connections.conf
#
# Usage:
#   sudo bash deploy-web-client.sh [--domain play.yourdomain.com] [--rebuild]

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="${DOMAIN:-play.yourdomain.com}"
RSC_C_DIR="/opt/rsc-c"
EMSDK_DIR="/opt/emsdk"
EMSDK_VERSION="3.1.22"
OPENRSC_CACHE_DIR="/opt/openrsc/Client_Base/Cache"
OPENRSC_HOST="localhost"          # WSS hostname the browser will connect to
OPENRSC_WS_PORT="43494"
OPENRSC_TCP_PORT="43594"
OPENRSC_RSA_EXP="00010001"
OPENRSC_RSA_MOD="87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25"
WORLDLIST_PATCHER="$REPO_ROOT/web-client/worldlist-patch.py"
WEBCLIENT_PATCHER="$REPO_ROOT/web-client/apply-mobile-patches.py"
MOBILE_WEBCLIENT_DIR="$REPO_ROOT/iOS_Client/OpenRSC/OpenRSC/Sources/WebClient"

REBUILD=false
for arg in "$@"; do
  case $arg in
    --domain=*) DOMAIN="${arg#*=}" ;;
    --domain)   shift; DOMAIN="$1" ;;
    --rebuild)  REBUILD=true ;;
  esac
done

echo "==> Domain: $DOMAIN"
echo "==> rsc-c dir: $RSC_C_DIR"

# ── 1. Install Emscripten ─────────────────────────────────────────────────────
if [ ! -f "$EMSDK_DIR/emsdk" ]; then
  echo "==> Installing Emscripten SDK $EMSDK_VERSION ..."
  git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
  cd "$EMSDK_DIR"
  ./emsdk install "$EMSDK_VERSION"
  ./emsdk activate "$EMSDK_VERSION"
  echo "source $EMSDK_DIR/emsdk_env.sh" > /etc/profile.d/emsdk.sh
  echo "==> Emscripten installed."
else
  echo "==> Emscripten already installed at $EMSDK_DIR"
fi

source "$EMSDK_DIR/emsdk_env.sh"

# ── 2. Clone or update rsc-c ──────────────────────────────────────────────────
if [ ! -d "$RSC_C_DIR/.git" ]; then
  echo "==> Cloning rsc-c ..."
  git clone https://github.com/2003scape/rsc-c.git "$RSC_C_DIR"
else
  echo "==> Updating rsc-c ..."
  git -C "$RSC_C_DIR" pull --ff-only
fi

# ── 3. Configure worldlist ───────────────────────────────────────────────────
echo "==> Patching worldlist for $DOMAIN ..."
WORLDLIST_FILE="$RSC_C_DIR/src/ui/worldlist.c"

python3 "$WORLDLIST_PATCHER" \
  --file "$WORLDLIST_FILE" \
  --host "$DOMAIN" \
  --ws-port "$OPENRSC_WS_PORT" \
  --tcp-port "$OPENRSC_TCP_PORT" \
  --rsa-exp "$OPENRSC_RSA_EXP" \
  --rsa-mod "$OPENRSC_RSA_MOD"

# ── 4. Sync cache ─────────────────────────────────────────────────────────────
echo "==> Syncing game cache ..."
mkdir -p "$RSC_C_DIR/cache"

if [ -d "$OPENRSC_CACHE_DIR" ]; then
  rsync -av --delete "$OPENRSC_CACHE_DIR/" "$RSC_C_DIR/cache/"
  echo "==> Cache synced from $OPENRSC_CACHE_DIR"
else
  echo "WARNING: OpenRSC cache not found at $OPENRSC_CACHE_DIR"
  echo "         You must manually populate $RSC_C_DIR/cache/ before building."
  echo "         Copy Client_Base/Cache/ contents there."
fi

# ── 5. Build ──────────────────────────────────────────────────────────────────
if [ "$REBUILD" = true ] || [ ! -f "$RSC_C_DIR/mudclient.html" ]; then
  echo "==> Building WebAssembly client (this takes ~5 minutes) ..."
  cd "$RSC_C_DIR"
  if grep -q -- "-s MAX_WEBGL_VERSION=2" Makefile.emscripten && ! grep -q -- "-s MIN_WEBGL_VERSION=2" Makefile.emscripten; then
    echo "==> Pinning Emscripten to WebGL 2 for iOS/Safari shader compatibility ..."
    sed -i 's/-s MAX_WEBGL_VERSION=2/-s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2/' Makefile.emscripten
  fi
  if grep -q -- "-s INITIAL_MEMORY=30MB" Makefile.emscripten; then
    echo "==> Raising initial WASM memory to avoid Safari heap growth stalls ..."
    sed -i 's/-s INITIAL_MEMORY=30MB/-s INITIAL_MEMORY=64MB/' Makefile.emscripten
  fi
  source "$EMSDK_DIR/emsdk_env.sh"
  make -f Makefile.emscripten clean
  make -f Makefile.emscripten
  echo "==> Build complete."
else
  echo "==> Skipping build (mudclient.html exists). Use --rebuild to force."
fi

# Verify outputs
for f in mudclient.html mudclient.js mudclient.wasm mudclient.data; do
  if [ ! -f "$RSC_C_DIR/$f" ]; then
    echo "ERROR: Build output $f is missing!"
    exit 1
  fi
done
echo "==> All build artifacts present."

# ── 6. Apply mobile web-client shell ──────────────────────────────────────────
echo "==> Applying mobile web-client HTML and JavaScript patches ..."
python3 "$WEBCLIENT_PATCHER" \
  --rsc-c-dir "$RSC_C_DIR" \
  --source-web-client "$MOBILE_WEBCLIENT_DIR"

# ── 7. Nginx config ───────────────────────────────────────────────────────────
echo "==> Writing nginx config ..."
cat > /etc/nginx/sites-available/openrsc-web <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Required for WebAssembly SharedArrayBuffer (threading support)
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    root $RSC_C_DIR;
    index mudclient.html;

    # Correct MIME type for .wasm files
    location ~* \\.wasm$ {
        default_type application/wasm;
        add_header Cross-Origin-Opener-Policy "same-origin" always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
    }

	    location / {
	        try_files \$uri \$uri/ =404;
	    }
	
	    # Keep hosted browsers on the same TLS origin for Safari/iOS.
	    # Preserve the trailing slash on proxy_pass: the Java websocket endpoint
	    # expects / after the /rsc-ws prefix is stripped.
	    location /rsc-ws {
	        proxy_pass http://127.0.0.1:$OPENRSC_WS_PORT/;
	        proxy_http_version 1.1;
	        proxy_set_header Upgrade \$http_upgrade;
	        proxy_set_header Connection "Upgrade";
	        proxy_set_header Host \$host;
	        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	        proxy_read_timeout 86400;
	        proxy_send_timeout 86400;
	        proxy_buffering off;
	    }
	
	    # Cache large data file aggressively (only changes on rebuild)
	    location ~* \\.data$ {
	        expires 7d;
        add_header Cache-Control "public, immutable";
        add_header Cross-Origin-Opener-Policy "same-origin" always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/openrsc-web /etc/nginx/sites-enabled/openrsc-web

# ── 8. SSL certificate ────────────────────────────────────────────────────────
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "==> Obtaining Let's Encrypt certificate for $DOMAIN ..."
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "WARNING: certbot failed. You may need to run it manually:"
    echo "  certbot --nginx -d $DOMAIN"
  }
else
  echo "==> SSL certificate already exists for $DOMAIN"
fi

# ── 9. Enable and reload nginx ────────────────────────────────────────────────
nginx -t
systemctl enable nginx
systemctl reload nginx

echo ""
echo "=========================================="
echo " Web client deployed!"
echo " URL: https://$DOMAIN/mudclient.html"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Verify OpenRSC server has SSL cert paths set in connections.conf"
echo "  2. Verify ws_server_port=43494 and want_feature_websockets=true in world conf"
echo "  3. Restart the OpenRSC server"
echo "  4. Open https://$DOMAIN/mudclient.html in a browser"
echo ""
echo "To rebuild after a cache update:"
echo "  sudo bash $0 --rebuild"
