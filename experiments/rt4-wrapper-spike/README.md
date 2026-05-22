# RT4 Browser Wrapper Spike

This is a deliberately small CheerpJ spike for running the existing Java RT4
client in a browser. It is not the long-term TypeScript client and should stay
isolated from `2009scape-web/client-patch`.

## What This Tests

- Can the current `reference/rt4-client` jar launch under CheerpJ?
- Does the AWT/Applet display path create a visible client surface?
- Can patched RT4 sockets reach 2009scape through a browser WebSocket bridge?

## Prepare

From the repo root:

```bash
bash experiments/rt4-wrapper-spike/scripts/prepare.sh
```

That builds `reference/rt4-client/client/build/libs/client-1.0.0.jar` and copies
the jar plus `reference/rt4-client/client/config.json` into `public/`. It also
builds a tiny `rt4-spike-launcher.jar` entrypoint that wraps `rt4.client.main`
and prints uncaught startup exceptions.

Edit `public/config.json` after preparation if you want to point the client at a
different 2009scape host or port. In browser mode the Java socket is patched to
use `public/wrapper-config.js` and a WebSocket bridge, so the host/port in
`config.json` are mostly useful for keeping the normal RT4 startup path intact.

For local browser-to-server testing against the Java 2009scape server, run:

```bash
bash experiments/rt4-wrapper-spike/scripts/build-local-server.sh
```

In one terminal:
```bash
bash experiments/rt4-wrapper-spike/scripts/start-local-server.sh
```

In another terminal:
```bash
bash experiments/rt4-wrapper-spike/scripts/start-local-wrapper.sh
```

Then open:

```text
http://127.0.0.1:8787/
```

The local wrapper writes `public/config.json` and `public/wrapper-config.js` for
the working local setup:

- `ws://127.0.0.1:43600 -> 127.0.0.1:43595`
- `ws://127.0.0.1:43601 -> 127.0.0.1:43595`

The browser-mode RT4 client synthesizes a single local world list, then uses the
bridge for JS5 and game login traffic.

To verify the local wrapper from the command line, run this while both terminals
are still up:

```bash
bash experiments/rt4-wrapper-spike/scripts/smoke-local-wrapper.sh
```

For a cold smoke test that starts and stops the local server/wrapper for you:

```bash
bash experiments/rt4-wrapper-spike/scripts/smoke-local-stack.sh
```

The smoke test launches Chromium through Playwright, waits for the RT4 login
screen, logs into a temporary no-auth local account, and waits until the client
reaches the in-game tutorial screen. Screenshots are written under `/tmp`.

## Mobile Controls

The wrapper adds a browser-side touch adapter around the CheerpJ display:

- one-finger tap/drag maps to the RT4 mouse
- long-press maps to right-click/context menu
- quick two-finger tap maps to right-click/context menu
- pinch zoom scales the display and also emits wheel events
- the wrapper creates a fixed RT4 game surface and fits it to the current screen
- portrait phone view rotates the fitted game surface into a landscape layout
- the `-`, `1x`, and `+` controls adjust/reset the wrapper zoom
- the `KB` control blurs the active element when the mobile keyboard gets stuck
- the debug log/menu is hidden by default and can be reopened with `Show log`

These controls live in `public/index.html` and can be tuned from
`public/wrapper-config.js`:

```js
window.RT4_WRAPPER_CONFIG = {
  mobileTouch: true,
  gameWidth: 765,
  gameHeight: 503,
  fitPadding: 1,
  initialScale: 1,
  minScale: 1,
  maxScale: 2.75,
  longPressMs: 550,
  rotatePortrait: true,
  showLogByDefault: false,
};
```

To switch back to the upstream test config:

```bash
bash experiments/rt4-wrapper-spike/scripts/use-test-config.sh
```

## Run Static Only

CheerpJ must be served over HTTP. Opening `index.html` directly from disk will
not work. If you already have a reachable server/bridge and only need the static
page, run:

```bash
cd experiments/rt4-wrapper-spike/public
python3 ../scripts/serve.py --port 8787
```

## Hetzner Deployment

The repo-level deploy script builds the jar, writes the wrapper configs, copies
the static files to `/opt/rt4-wrapper`, and creates an nginx include snippet:

```bash
sudo bash Deployment_Scripts/deploy-rt4-wrapper.sh \
  --domain play.yourdomain.com \
  --rt4-host 127.0.0.1 \
  --server-port 43600 \
  --wl-port 43600 \
  --js5-port 43600 \
  --websocket-url wss://play.yourdomain.com/rt4-ws
```

Then include this line inside the existing HTTPS nginx server block for that
domain and reload nginx:

```nginx
include /etc/nginx/snippets/rt4-wrapper.conf;
```

The page will be available at:

```text
https://play.yourdomain.com/rt4-wrapper/
```

On the current Hetzner deployment, Caddy serves `/rt4-wrapper/` from
`/opt/rt4-wrapper` and proxies `/rt4-ws` to the existing
`2009scape-ws-proxy` container on `127.0.0.1:43601`.

## Expected First Blocker

The spike now patches `SignLink.openSocket` to return a small
`BrowserWebSocketSocket` when launched by `Rt4SpikeLauncher`. CheerpJ calls the
native methods implemented in `public/index.html`, and the browser sends binary
traffic through `/rt4-ws` to a WebSocket-to-TCP bridge.

The next likely blockers are runtime fidelity issues: byte-array marshaling
between CheerpJ and JavaScript, blocking read behavior, mobile input ergonomics,
and any RT4 assumptions about desktop AWT focus/window behavior.
