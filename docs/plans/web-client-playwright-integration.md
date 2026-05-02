# Plan: 2009scape-web Playwright integration tests

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This plan **pairs** with [docs/plans/ci-smoke-test.md](ci-smoke-test.md) — it adds runtime regression catching on top of compile-only smoke. Land the CI plan first.

## Goal

Stand up a small suite of Playwright scenarios that boot the rev-530 web client against a live (Hetzner-deployed) server, drive a few canonical interactions, and assert on console + WebSocket frame patterns. After this lands, every Tier-5x and Tier-6/7/8 plan that ticks off in `web-client-plan.md` runs through these scenarios as part of its acceptance.

There are already two ad-hoc scripts in `Deployment_Scripts/playwright/`:

- `login-flow.mjs` — drives the title screen → login form → WS connect, captures every WS frame.
- `probe.mjs` — generic 45-second probe that screenshots, captures console, and writes a JSON event log.

Both work but are one-off debug tools. This plan promotes them into a structured scenario set with clear pass/fail criteria.

## Why now

The first run of CI (per the smoke plan) only catches compile breakage. As Tier 5b/c/d and Tier 6 land, the cost of *runtime* regressions creeps up: a misaligned bit-stream in opcode 234 doesn't fail the TS compiler. We need a "log in, walk three tiles, drop an item, see it land" probe that runs on every push.

## Scope (files you may edit)

- `Deployment_Scripts/playwright/scenarios/` — new directory containing one `*.mjs` file per scenario (numbered for sequencing, e.g. `01-login.mjs`, `02-walk.mjs`, `03-drop-item.mjs`).
- `Deployment_Scripts/playwright/lib/harness.mjs` — new file: shared scaffold (browser launch, console capture, WS frame capture, screenshot at events, structured-log writer).
- `Deployment_Scripts/playwright/runner.mjs` — new file: discovers + runs every scenario in numerical order, fails fast on first red.
- `Deployment_Scripts/playwright/package.json` — already exists; add an `npm run scenarios` script entry pointing at `runner.mjs`.
- `.github/workflows/integration.yml` — new file (separate from `smoke.yml` so the matrices fan out cleanly): adds a job that boots the deployed server URL, runs `npm run scenarios`, uploads `/tmp/mudclient-playwright/**/*.png` + JSON logs as artifacts on red.
- `Deployment_Scripts/playwright/README.md` — extend to describe scenario authoring + how to add a new one.

## Out of scope (do NOT touch)

- The existing `login-flow.mjs` / `probe.mjs` debug scripts — keep them around for ad-hoc work; the new scenarios use the shared harness.
- Server bring-up. We assume `10.8.0.1` (over WireGuard) or a public Hetzner host is already running. Don't add docker-compose to CI.
- iOS Playwright work (not really a thing — iOS builds are device-tethered).
- Visual regression diffing. Just functional + log assertions for now; pixel-diff is a separate plan.

## Reference

| Existing artefact | Why useful |
|---|---|
| `Deployment_Scripts/playwright/login-flow.mjs` | Working example of WS frame capture (`page.on('websocket', …)`) — copy that pattern into the harness. |
| `Deployment_Scripts/playwright/probe.mjs` | Working example of timed screenshots + structured event log — same. |
| `2009scape-web/client-patch/README.md` | Local server bring-up instructions (`scripts/check-hetzner-login-path.sh`). |
| `docs/plans/ci-smoke-test.md` | Sister plan; integration runs *after* a green smoke matrix. |

## Implementation

### 1. `lib/harness.mjs`

Lift the duplicated scaffolding from `login-flow.mjs` + `probe.mjs` into one place:

```js
// harness.mjs — shared Playwright scaffold for OpenRSC web-client scenarios.
import { webkit } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

export async function startSession({ url, name, viewport = { width: 1024, height: 768 } }) {
    const outDir = `/tmp/mudclient-playwright/${name}-${Date.now()}`;
    fs.mkdirSync(outDir, { recursive: true });

    const t0 = Date.now();
    const stamp = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';

    const browser = await webkit.launch({ headless: true });
    const ctx = await browser.newContext({ viewport, ignoreHTTPSErrors: true });
    const page = await ctx.newPage();

    const events = [];
    const log = (kind, detail = {}) => {
        events.push({ t: stamp(), kind, ...detail });
        const brief = detail.text || detail.url || detail.message || JSON.stringify(detail).slice(0, 200);
        console.log(`[${stamp()}] ${kind.padEnd(12)} ${brief}`);
    };

    page.on('console', msg => log('console.' + msg.type(), { text: msg.text() }));
    page.on('pageerror', err => log('PAGE_ERR', { message: err.message }));
    page.on('requestfailed', req => log('REQ_FAIL', { url: req.url(), error: req.failure()?.errorText }));

    page.on('websocket', ws => {
        log('WS_OPEN', { url: ws.url() });
        ws.on('framesent', f => log('WS_SEND', { bytes: f.payload?.length || 0 }));
        ws.on('framereceived', f => log('WS_RECV', { bytes: f.payload?.length || 0 }));
        ws.on('close', () => log('WS_CLOSE'));
    });

    return {
        browser, ctx, page, log, events, outDir,
        screenshot: async (label) => {
            const file = path.join(outDir, `${stamp()}-${label}.png`);
            await page.screenshot({ path: file, fullPage: true });
            log('SCREENSHOT', { path: file });
        },
        finish: async () => {
            fs.writeFileSync(path.join(outDir, 'events.json'), JSON.stringify(events, null, 2));
            await browser.close();
            return { outDir, events };
        }
    };
}

/// Helper — wait until at least N WS frames have been received (server has
/// pushed real game state). Times out after `timeoutMs`.
export async function waitForFrames(session, n, timeoutMs = 15000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const recv = session.events.filter(e => e.kind === 'WS_RECV').length;
        if (recv >= n) return true;
        await new Promise(r => setTimeout(r, 200));
    }
    return false;
}

/// Helper — assert that a console substring appeared at least once. Used
/// in scenarios to pin down "REBUILD_NORMAL fired" / "ground item rendered".
export function assertConsole(session, substring, label) {
    const hit = session.events.find(e => e.kind?.startsWith('console.') && e.text?.includes(substring));
    if (!hit) {
        throw new Error(`[${label}] expected console substring "${substring}" — not seen in ${session.events.length} events`);
    }
}
```

### 2. Scenarios

**`scenarios/01-login.mjs`** — mirrors `login-flow.mjs` but as a pass/fail check:

```js
import { startSession, waitForFrames, assertConsole } from '../lib/harness.mjs';

const URL = process.env.SCENARIO_URL || 'http://10.8.0.1:8080/mudclient.html';
const session = await startSession({ url: URL, name: '01-login' });
session.log('NAV', { url: URL });
await session.page.goto(URL, { waitUntil: 'domcontentloaded' });
await session.screenshot('post-nav');

const ok = await waitForFrames(session, 3, 30000);
if (!ok) throw new Error('expected ≥3 WS frames within 30s');

assertConsole(session, 'startUp:46 RETURN', 'login');
await session.screenshot('after-startup');

const { outDir } = await session.finish();
console.log('PASS — login session at', outDir);
```

**`scenarios/02-walk.mjs`** — log in, click somewhere, assert player movement is visible in console (`PLAYER_INFO` log line).

**`scenarios/03-drop-item.mjs`** — log in with a test account that has an item in slot 0, send a drop command via the runner's keyboard helper, assert that opcode 246 fired with 6 body bytes (just landed in `66133fcc2`).

**`scenarios/04-rebuild-region.mjs`** — log in, walk far enough to cross a region boundary, assert the `[Probe] renderer state` group appears once after `REBUILD_NORMAL` (when Tier 6a's renderer probe lands, gate this scenario behind it).

Keep each scenario under 100 lines and exit non-zero on any thrown error. The runner takes care of aggregation.

### 3. `runner.mjs`

```js
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'scenarios');
const files = fs.readdirSync(dir).filter(f => /^\d+.*\.mjs$/.test(f)).sort();

const failures = [];
for (const file of files) {
    console.log('\n=== running', file, '===');
    const result = spawnSync('node', [path.join(dir, file)], { stdio: 'inherit', env: process.env });
    if (result.status !== 0) {
        failures.push(file);
        // Fail fast — don't run remaining if one scenario has already broken.
        break;
    }
}

if (failures.length > 0) {
    console.error('\nFAIL:', failures.join(', '));
    process.exit(1);
}
console.log('\nALL', files.length, 'SCENARIOS PASS');
```

### 4. `.github/workflows/integration.yml`

```yaml
name: integration

on:
  workflow_run:
    workflows: [smoke]
    branches: [develop]
    types: [completed]

# Only run if smoke went green
jobs:
  scenarios:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      # Set this in the repo's secrets — the deployed Hetzner URL.
      SCENARIO_URL: ${{ secrets.WEB_CLIENT_URL }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm', cache-dependency-path: 'Deployment_Scripts/playwright/package-lock.json' }
      - name: Install Playwright + browser binary
        run: |
          cd Deployment_Scripts/playwright
          npm ci
          npx playwright install webkit --with-deps
      - name: Run scenarios
        run: |
          cd Deployment_Scripts/playwright
          npm run scenarios
      - name: Upload screenshots + event logs on red
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-${{ github.run_id }}
          path: /tmp/mudclient-playwright
          retention-days: 7
```

The `workflow_run` trigger ensures integration only fires when smoke is green — saves runner minutes.

### 5. Adding a scenario

The README's "Adding a scenario" section should be 10 lines:

1. Copy the latest existing scenario to a new numbered file.
2. Run it locally: `SCENARIO_URL=http://10.8.0.1:8080/mudclient.html node scenarios/0X-yourname.mjs`.
3. Iterate until pass.
4. Open PR; the integration job will run it on green-smoke pushes.

## Self-test

Locally:

```bash
cd Deployment_Scripts/playwright
SCENARIO_URL=http://10.8.0.1:8080/mudclient.html npm run scenarios
```

Output: each scenario logs a final `PASS — <name> session at <outDir>` line. Any `Error:` thrown inside `assertConsole` / `waitForFrames` aborts the runner and exits non-zero.

For the GitHub Actions side, push to a branch, open a PR, observe the integration job runs *after* smoke completes. Confirm artifact upload by deliberately breaking one assertion in `01-login.mjs` and verifying the failed run uploads the screenshot tarball.

## Acceptance criteria

1. `lib/harness.mjs` extracts the shared Playwright scaffolding; existing `login-flow.mjs` + `probe.mjs` continue working unchanged.
2. ≥3 scenarios in `scenarios/` (login + walk + drop-item at minimum).
3. `npm run scenarios` exits zero locally against the staging URL.
4. `.github/workflows/integration.yml` chains off `smoke.yml`'s success.
5. A deliberate red run uploads the artifact tarball on failure.
6. Add this plan to `docs/plans/README.md` "Cross-cutting" section.
7. Wall-clock budget: 4 scenarios × ~30s = ~2 min; runner adds ~30s overhead. Total ≤ 4 min.

## Out of scope clarifications

- **Don't add visual diff testing.** Pixel-perfect diffs are flaky against shifting ad banners / login-screen tip-of-day text. Functional + log-string assertions are the bar.
- **Don't fake the server.** Hitting the real Hetzner instance catches integration regressions a mock would hide.
- **Don't gate iOS work on this** — the iOS port has its own (non-existent) integration tests and a different surface area.
- **Don't widen scenarios into combat / quest end-to-end.** Those need test accounts with prepared inventories; they're a Tier-N follow-up.

## Commit guidance

Three commits is fine:

1. `playwright: extract shared harness from probe + login-flow`
2. `playwright: scenarios — login, walk, drop-item`
3. `ci: integration workflow chained off smoke`

Push nothing.
