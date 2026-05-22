#!/usr/bin/env bash
# deploy-rt4-wrapper.sh
#
# Builds and deploys the CheerpJ RT4 wrapper spike as static files on a server.
# This script is intentionally additive: it writes files to /opt/rt4-wrapper and
# writes an nginx snippet you can include from your existing HTTPS server block.
#
# Usage:
#   sudo bash Deployment_Scripts/deploy-rt4-wrapper.sh \
#     --domain play.example.com \
#     --websocket-url wss://play.example.com/rt4-ws

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPIKE_DIR="$REPO_ROOT/experiments/rt4-wrapper-spike"
PUBLIC_DIR="$SPIKE_DIR/public"

DOMAIN="${DOMAIN:-play.yourdomain.com}"
INSTALL_DIR="${INSTALL_DIR:-/opt/rt4-wrapper}"
URL_PREFIX="${URL_PREFIX:-/rt4-wrapper/}"
RT4_HOST="${RT4_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-43600}"
WL_PORT="${WL_PORT:-43600}"
JS5_PORT="${JS5_PORT:-43600}"
TAILSCALE_CONTROL_URL="${TAILSCALE_CONTROL_URL:-}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
USE_TAILSCALE_LOGIN=false
WEBSOCKET_URL="${WEBSOCKET_URL:-}"
WRITE_NGINX_SITE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain=*) DOMAIN="${1#*=}" ;;
    --domain) shift; DOMAIN="$1" ;;
    --install-dir=*) INSTALL_DIR="${1#*=}" ;;
    --install-dir) shift; INSTALL_DIR="$1" ;;
    --url-prefix=*) URL_PREFIX="${1#*=}" ;;
    --url-prefix) shift; URL_PREFIX="$1" ;;
    --rt4-host=*) RT4_HOST="${1#*=}" ;;
    --rt4-host) shift; RT4_HOST="$1" ;;
    --server-port=*) SERVER_PORT="${1#*=}" ;;
    --server-port) shift; SERVER_PORT="$1" ;;
    --wl-port=*) WL_PORT="${1#*=}" ;;
    --wl-port) shift; WL_PORT="$1" ;;
    --js5-port=*) JS5_PORT="${1#*=}" ;;
    --js5-port) shift; JS5_PORT="$1" ;;
    --tailscale-control-url=*) TAILSCALE_CONTROL_URL="${1#*=}" ;;
    --tailscale-control-url) shift; TAILSCALE_CONTROL_URL="$1" ;;
    --tailscale-auth-key=*) TAILSCALE_AUTH_KEY="${1#*=}" ;;
    --tailscale-auth-key) shift; TAILSCALE_AUTH_KEY="$1" ;;
    --use-tailscale-login) USE_TAILSCALE_LOGIN=true ;;
    --websocket-url=*) WEBSOCKET_URL="${1#*=}" ;;
    --websocket-url) shift; WEBSOCKET_URL="$1" ;;
    --write-nginx-site) WRITE_NGINX_SITE=true ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ "$URL_PREFIX" != */ ]]; then
  URL_PREFIX="$URL_PREFIX/"
fi

if [[ -n "$TAILSCALE_AUTH_KEY" && "$USE_TAILSCALE_LOGIN" == "true" ]]; then
  echo "ERROR: --tailscale-auth-key and --use-tailscale-login are mutually exclusive." >&2
  exit 1
fi

echo "==> Building wrapper artifacts ..."
bash "$SPIKE_DIR/scripts/prepare.sh"

echo "==> Writing RT4 wrapper game config ..."
cat > "$PUBLIC_DIR/config.json" <<JSON
{
    "ip_management": "$RT4_HOST",
    "ip_address": "$RT4_HOST",
    "world": 1,
    "server_port": $SERVER_PORT,
    "wl_port": $WL_PORT,
    "js5_port": $JS5_PORT,
    "mouseWheelZoom": true,
    "pluginsFolder": "plugins"
}
JSON

echo "==> Writing CheerpJ wrapper runtime config ..."
cat > "$PUBLIC_DIR/wrapper-config.js" <<JS
window.RT4_WRAPPER_CONFIG = {
  debug: true,
  websocketUrl: "$WEBSOCKET_URL",
  tailscaleControlUrl: "$TAILSCALE_CONTROL_URL",
  tailscaleAuthKey: "$TAILSCALE_AUTH_KEY",
  useTailscaleLogin: $USE_TAILSCALE_LOGIN
};
JS

echo "==> Installing static files to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
rsync -av --delete "$PUBLIC_DIR/" "$INSTALL_DIR/"

echo "==> Writing nginx include snippet ..."
cat > /etc/nginx/snippets/rt4-wrapper.conf <<NGINX
# RT4 CheerpJ wrapper. Include this inside the HTTPS server block for $DOMAIN.
location = ${URL_PREFIX%/} {
    return 301 $URL_PREFIX;
}

location ^~ $URL_PREFIX {
    alias $INSTALL_DIR/;
    index index.html;

    types {
        text/html html;
        application/javascript js;
        application/java-archive jar;
        application/json json;
    }

    add_header Accept-Ranges bytes always;
}
NGINX

if [[ "$WRITE_NGINX_SITE" == "true" ]]; then
  echo "==> Writing standalone nginx site /etc/nginx/sites-available/rt4-wrapper ..."
  cat > /etc/nginx/sites-available/rt4-wrapper <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    include /etc/nginx/snippets/rt4-wrapper.conf;
}
NGINX
  ln -sf /etc/nginx/sites-available/rt4-wrapper /etc/nginx/sites-enabled/rt4-wrapper
fi

if command -v nginx >/dev/null 2>&1; then
  nginx -t
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload nginx || true
  fi
fi

cat <<EOF

==> RT4 wrapper deployed.

Static dir:
  $INSTALL_DIR

URL:
  https://$DOMAIN$URL_PREFIX

Nginx snippet:
  /etc/nginx/snippets/rt4-wrapper.conf

If you did not use --write-nginx-site, include this line inside your existing
HTTPS server block for $DOMAIN, then reload nginx:

  include /etc/nginx/snippets/rt4-wrapper.conf;

Networking note:
  The wrapper patches RT4 socket creation to a browser WebSocket bridge.
  Configure your HTTPS server to proxy that WebSocket URL to the RT4 TCP
  WebSocket proxy. Current wrapper WebSocket URL:
  ${WEBSOCKET_URL:-auto /rt4-ws beside the wrapper page}
EOF
