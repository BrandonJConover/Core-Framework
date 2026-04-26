# Web Client Plan (rsc-c + Hetzner)

## Goal

Deploy a browser-playable OpenRSC web client on the Hetzner VPS so players can connect without installing anything. The client uses `rsc-c` compiled to WebAssembly via Emscripten, served over HTTPS/WSS.

## Architecture

```
Browser
  │  HTTPS (port 443) — serves mudclient.html/.js/.wasm/.data
  ▼
Nginx (Hetzner VPS)
  │  WSS (port 43494) — proxied or direct WebSocket
  ▼
OpenRSC Java Server (port 43494 WebSocket)
```

The OpenRSC server already has native WebSocket support on port 43494 (`want_feature_websockets: true` in `default.conf`). No websockify proxy is needed.

## Requirements

### Hetzner Server
- Nginx
- Let's Encrypt SSL cert (certbot)
- Emscripten SDK 3.1.22 (exact version — newer causes SDL2 audio issues)
- git
- ~500MB free disk space for rsc-c build + cache

### Domain
- A subdomain pointing at the Hetzner VPS (e.g., `play.yourdomain.com`)
- DNS A record pointing to the server IP

### OpenRSC Server Config
These must be set in `connections.conf` before running:
```
ssl_server_cert_path: /etc/letsencrypt/live/play.yourdomain.com/fullchain.pem
ssl_server_key_path: /etc/letsencrypt/live/play.yourdomain.com/privkey.pem
```

And in the world's `.conf` file:
```
ws_server_port: 43494
want_feature_websockets: true
```

## Critical HTTP Headers

Emscripten's WebAssembly requires `SharedArrayBuffer` for memory threading. Chrome and Firefox require these headers on every response:

```nginx
add_header Cross-Origin-Opener-Policy "same-origin";
add_header Cross-Origin-Embedder-Policy "require-corp";
```

Without these, the WASM client will fail with a `SharedArrayBuffer is not defined` error.

## Build Steps

### 1. Install Emscripten (exact version 3.1.22)

```bash
cd /opt
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install 3.1.22
./emsdk activate 3.1.22
source /opt/emsdk/emsdk_env.sh
echo 'source /opt/emsdk/emsdk_env.sh' >> /etc/profile.d/emsdk.sh
```

### 2. Clone and Configure rsc-c

```bash
cd /opt
git clone https://github.com/2003scape/rsc-c.git
cd rsc-c
```

Edit `src/ui/worldlist.c` — change `worldlist_set_defaults()` to point at your server:

```c
// In worldlist_set_defaults():
strcpy(list[0].name, "OpenRSC");
strcpy(list[0].host, "YOUR_SERVER_HOSTNAME");
list[0].port = USE_WEBSOCKS ? 43494 : 43594;
strcpy(list[0].rsa_exponent, "00010001");
strcpy(list[0].rsa_modulus, "87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25");
```

### 3. Download Cache

The game cache must be present before building (Emscripten preloads it into the WASM data file):

```bash
cd /opt/rsc-c
mkdir -p cache
# Copy cache from your existing OpenRSC client cache directory
# or download from your server's cache distribution endpoint
rsync -avz /opt/openrsc/Client_Base/Cache/ /opt/rsc-c/cache/
```

### 4. Build

```bash
cd /opt/rsc-c
source /opt/emsdk/emsdk_env.sh
make -f Makefile.emscripten
```

Output files (4 files, all required):
```
mudclient.html
mudclient.js
mudclient.wasm
mudclient.data
```

### 5. Configure Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name play.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/play.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/play.yourdomain.com/privkey.pem;

    # Required for WebAssembly SharedArrayBuffer
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    root /opt/rsc-c;
    index mudclient.html;

    location / {
        try_files $uri $uri/ =404;
        # Correct MIME types for WASM
        types {
            application/wasm wasm;
        }
    }

    location /mudclient.html {
        default_type text/html;
    }
}

server {
    listen 80;
    server_name play.yourdomain.com;
    return 301 https://$host$request_uri;
}
```

### 6. SSL Certificate

```bash
certbot --nginx -d play.yourdomain.com
```

Auto-renewal is configured by certbot automatically.

### 7. Test

```bash
# Check nginx config
nginx -t

# Reload nginx
systemctl reload nginx

# Test WebSocket connectivity
curl -I https://play.yourdomain.com/mudclient.html
```

Open `https://play.yourdomain.com/mudclient.html` in a browser. The game should load, connect via WSS to port 43494, and show the login screen.

## Deployment Script

See `Deployment_Scripts/deploy-web-client.sh` for the automated deployment script.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `SharedArrayBuffer is not defined` | Missing COOP/COEP headers | Add `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers in nginx |
| WebSocket connection refused | SSL cert not configured on OpenRSC server | Set `ssl_server_cert_path` in `connections.conf`, restart server |
| Black screen, no login | Cache not preloaded | Rebuild with correct `cache/` directory present |
| Audio distorted | Wrong Emscripten version | Must use exactly 3.1.22 |
| `wasm streaming compile failed` | Wrong MIME type | Add `application/wasm wasm` to nginx `types` block |

## Updating the Client

When the server cache changes:
```bash
cd /opt/rsc-c
rsync -avz /opt/openrsc/Client_Base/Cache/ ./cache/
source /opt/emsdk/emsdk_env.sh
make -f Makefile.emscripten
systemctl reload nginx
```

## Future: iOS rsc-c Port

The same `rsc-c` C codebase that builds for WASM could be compiled for iOS via SDL2. This would give a native iOS RSC client with authentic rendering without needing to port the Java mudclient. This is tracked in `ios-mobile-finish-plan.md` as an alternative rendering path.

What's needed:
1. An Xcode project or CMakeLists.txt with iOS deployment target
2. SDL2 iOS framework (via SDL2 releases)
3. Compile flags: `-DSDL2 -DRENDER_SW` (software renderer) or `-DRENDER_GL` (OpenGL ES 3.0)
4. `#ifdef TARGET_OS_IPHONE` guards in `get_config_path()` and audio initialization
