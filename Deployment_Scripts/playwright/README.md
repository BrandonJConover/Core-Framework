# OpenRSC Playwright Scenarios

This folder contains two kinds of Playwright automation:

- `login-flow.mjs` and `probe.mjs` are ad-hoc debug probes. Keep using them for raw screenshots and event dumps.
- `runner.mjs`, `lib/harness.mjs`, and `scenarios/*.mjs` are pass/fail integration checks intended for CI.

## Running Scenarios

```bash
cd Deployment_Scripts/playwright
npm ci
npx playwright install webkit
SCENARIO_URL=http://10.8.0.1:8080/mudclient.html npm run scenarios
```

Useful environment variables:

- `SCENARIO_URL`: deployed web-client URL. Defaults to `http://10.8.0.1:8080/mudclient.html`.
- `SCENARIO_USER`: test account username. Defaults to `playtest2`.
- `SCENARIO_PASSWORD`: test account password. Defaults to `playtest2`.
- `SCENARIO_BROWSER`: `webkit`, `chromium`, or `firefox`. Defaults to `webkit`.

Each run writes screenshots and `events.json` to `/tmp/mudclient-playwright/<scenario>-<timestamp>/`.

## Scenario List

- `01-login.mjs`: boots the client, reaches the title screen, logs in, and requires inbound WebSocket game-state frames.
- `02-walk.mjs`: logs in, clicks the game canvas, and requires a new outbound WebSocket frame.
- `03-drop-item.mjs`: logs in, opens inventory, attempts to drop the first inventory item, and requires a new outbound WebSocket frame.

The drop-item scenario assumes the configured test account has at least one disposable item in slot 0.

## Adding A Scenario

1. Copy the closest existing scenario to a new numbered file in `scenarios/`.
2. Keep it focused on one player-visible behavior.
3. Use helpers from `lib/harness.mjs` for login, canvas clicks, screenshots, console waits, and WebSocket assertions.
4. Run it locally with `SCENARIO_URL=http://10.8.0.1:8080/mudclient.html node scenarios/0X-name.mjs`.
5. Run the full suite with `npm run scenarios`.

Use `npm run scenarios -- --list` to verify scenario discovery without launching a browser.
