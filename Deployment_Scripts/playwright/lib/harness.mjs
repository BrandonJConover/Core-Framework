// Shared Playwright scaffold for OpenRSC web-client integration scenarios.
import { chromium, firefox, webkit } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

const browsers = { chromium, firefox, webkit };

function nowDirName(name) {
  const safe = name.replace(/[^a-z0-9._-]+/gi, '-').replace(/^-|-$/g, '');
  return `${safe}-${Date.now()}`;
}

function payloadLength(payload) {
  if (typeof payload === 'string') return payload.length;
  return payload?.byteLength ?? payload?.length ?? 0;
}

export async function startSession({
  url,
  name,
  viewport = { width: 1024, height: 768 },
  browserName = process.env.SCENARIO_BROWSER || 'webkit',
} = {}) {
  if (!url) throw new Error('startSession requires url');
  if (!name) throw new Error('startSession requires name');

  const browserType = browsers[browserName];
  if (!browserType) {
    throw new Error(`Unsupported SCENARIO_BROWSER="${browserName}" (expected chromium, firefox, or webkit)`);
  }

  const outDir = path.join('/tmp/mudclient-playwright', nowDirName(name));
  fs.mkdirSync(outDir, { recursive: true });

  const t0 = Date.now();
  const stamp = () => `${((Date.now() - t0) / 1000).toFixed(1)}s`;
  const events = [];

  const log = (kind, detail = {}) => {
    const event = { t: stamp(), kind, ...detail };
    events.push(event);
    const brief = detail.text || detail.url || detail.message || detail.path || JSON.stringify(detail).slice(0, 200);
    console.log(`[${event.t}] ${kind.padEnd(14)} ${brief ?? ''}`);
    return event;
  };

  const browser = await browserType.launch({ headless: true });
  const ctx = await browser.newContext({ viewport, ignoreHTTPSErrors: true });
  await ctx.clearCookies();
  const page = await ctx.newPage();

  page.on('console', msg => log(`console.${msg.type()}`, { text: msg.text() }));
  page.on('pageerror', err => log('PAGE_ERR', { message: err.message, stack: err.stack?.split('\n').slice(0, 5).join(' | ') }));
  page.on('requestfailed', req => log('REQ_FAIL', { url: req.url(), error: req.failure()?.errorText }));
  page.on('websocket', ws => {
    log('WS_OPEN', { url: ws.url() });
    ws.on('framesent', f => log('WS_SEND', { bytes: payloadLength(f.payload) }));
    ws.on('framereceived', f => log('WS_RECV', { bytes: payloadLength(f.payload) }));
    ws.on('close', () => log('WS_CLOSE'));
    ws.on('socketerror', err => log('WS_ERR', { message: String(err) }));
  });

  return {
    browser,
    ctx,
    page,
    log,
    events,
    outDir,
    url,
    async goto() {
      log('NAV', { url });
      await page.goto(url, { waitUntil: 'commit', timeout: Number(process.env.SCENARIO_NAV_TIMEOUT_MS || 30000) });
    },
    async screenshot(label) {
      const safe = String(label).replace(/[^a-z0-9._-]+/gi, '-');
      const file = path.join(outDir, `${stamp()}-${safe}.png`);
      await page.screenshot({ path: file, fullPage: false });
      log('SCREENSHOT', { path: file });
      return file;
    },
    async finish() {
      fs.writeFileSync(path.join(outDir, 'events.json'), JSON.stringify(events, null, 2));
      await browser.close();
      return { outDir, events };
    },
  };
}

export async function runScenario(name, fn) {
  const url = process.env.SCENARIO_URL || 'http://10.8.0.1:8080/mudclient.html';
  const session = await startSession({ url, name });
  try {
    await fn(session);
    const { outDir } = await session.finish();
    console.log(`PASS - ${name} session at ${outDir}`);
  } catch (err) {
    session.log('SCENARIO_FAIL', { message: err?.message || String(err) });
    try {
      await session.screenshot('failure');
    } catch (shotErr) {
      session.log('SCREENSHOT_ERR', { message: shotErr?.message || String(shotErr) });
    }
    await session.finish().catch(() => {});
    throw err;
  }
}

export async function waitForFrames(session, n, timeoutMs = 15000, kind = 'WS_RECV') {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const count = session.events.filter(e => e.kind === kind).length;
    if (count >= n) return true;
    await session.page.waitForTimeout(200);
  }
  throw new Error(`expected at least ${n} ${kind} events within ${timeoutMs}ms`);
}

export async function waitForConsole(session, substring, timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const hit = session.events.find(e => e.kind?.startsWith('console.') && e.text?.includes(substring));
    if (hit) return hit;
    await session.page.waitForTimeout(200);
  }
  throw new Error(`expected console substring "${substring}" within ${timeoutMs}ms`);
}

export function assertEvent(session, predicate, label) {
  const hit = session.events.find(predicate);
  if (!hit) throw new Error(`expected event: ${label}`);
  return hit;
}

export async function waitForCanvas(session, timeoutMs = 30000) {
  const canvas = session.page.locator('#canvas, canvas').first();
  await canvas.waitFor({ state: 'visible', timeout: timeoutMs });
  const box = await canvas.boundingBox();
  if (!box) throw new Error('canvas is visible but has no bounding box');
  session.log('CANVAS_BOX', { message: JSON.stringify(box) });
  return { canvas, box };
}

export async function clickCanvasAt(session, x, y, baseWidth = 765, baseHeight = 503) {
  const { box } = await waitForCanvas(session, 10000);
  const px = box.x + (x / baseWidth) * box.width;
  const py = box.y + (y / baseHeight) * box.height;
  session.log('CANVAS_CLICK', { message: `${Math.round(px)},${Math.round(py)} from ${x},${y}` });
  await session.page.mouse.click(px, py);
}

export async function loginWithCanvas(session, {
  username = process.env.SCENARIO_USER || 'playtest2',
  password = process.env.SCENARIO_PASSWORD || 'playtest2',
} = {}) {
  await waitForCanvas(session);
  await waitForConsole(session, 'startUp:46 RETURN', 45000);
  await session.screenshot('title-ready');

  // Coordinates are in the legacy fixed game canvas coordinate space used by
  // login-flow.mjs/probe logs. They are scaled to the rendered canvas box.
  await clickCanvasAt(session, 462, 291);
  await session.page.waitForTimeout(750);
  await session.page.keyboard.type(username, { delay: 15 });
  await session.page.keyboard.press('Enter');
  await session.page.keyboard.type(password, { delay: 15 });
  await session.page.keyboard.press('Enter');

  await waitForFrames(session, 3, 45000, 'WS_RECV');
  await session.screenshot('logged-in');
}

export async function waitForOutboundAfter(session, previousCount, timeoutMs = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const current = session.events.filter(e => e.kind === 'WS_SEND').length;
    if (current > previousCount) return current;
    await session.page.waitForTimeout(200);
  }
  throw new Error(`expected outbound WS frame count to exceed ${previousCount} within ${timeoutMs}ms`);
}
