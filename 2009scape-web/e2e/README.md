# 2009scape-web E2E smoke test

Quick Playwright-driven smoke test that verifies the web client can:

1. Reach the title screen
2. Click "Existing User" → reach username/password form
3. Submit credentials (login via WebSocket to `10.8.0.1:43601`)
4. Stay connected past the 20-second server ping timeout
5. Send a `::command` and receive a server chat response
6. Hold the session open for 45+ seconds without page errors

Five screenshots are captured at each stage under `/tmp/playwright-2009scape/` so you can visually confirm the render state (chrome, chat, minimap frame, FPS counter).

## Running

```bash
# One-time setup (from this directory)
mkdir -p /tmp/playwright-2009scape && cp smoke-test.js /tmp/playwright-2009scape/
cd /tmp/playwright-2009scape
npm init -y
npm install playwright
npx playwright install chromium

# Run
node smoke-test.js
```

## Interpreting output

Pass looks like:
- `===== CONSOLE (4) =====` — just the COOP warning + three init logs
- `===== PAGE ERRORS (0) =====`
- Screenshots 03/04/05 show the full 2009scape UI chrome with chat messages from the server

A fail typically shows:
- `PAGE ERRORS (1+)` — the TypeError with a stack trace reveals which render path broke
- Or `FATAL: page.goto: net::ERR_CONNECTION_REFUSED` — web server is down (systemctl restart 2009scape-web on the Hetzner box)

## Coordinates

The canvas is 765×503 native. The script computes scaleX/scaleY relative to the viewport so clicks work at different window sizes. Notable canvas coords:
- Existing User button: `(462, 291)`
- Login button: `(302, 321)`
- Cancel button: `(462, 321)`

All taken from Game.ts login screen handler at [drawLoginScreen state 2](../../2009scape-web/client-patch/Login530.ts) / `loginScreenState === 2`.
