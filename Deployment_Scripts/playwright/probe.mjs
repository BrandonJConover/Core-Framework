// Probes the mudclient via WebKit (Safari engine) over VPN and reports what
// happens. Usage: node probe.mjs [url]
import { webkit } from 'playwright';
import fs from 'node:fs';

const URL = process.argv[2] || 'http://10.8.0.1:8080/mudclient.html';
const DURATION_MS = 45000;
const SCREENSHOT_AT = [5000, 15000, 30000, 45000];
const OUTDIR = '/tmp/mudclient-playwright/run-' + Date.now();
fs.mkdirSync(OUTDIR, { recursive: true });

const events = [];
const stamp = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
let t0;

function log(kind, detail) {
  const entry = { t: stamp(), kind, ...detail };
  events.push(entry);
  const brief = detail.text || detail.url || detail.message || JSON.stringify(detail).slice(0, 200);
  console.log(`[${entry.t}] ${kind.padEnd(12)} ${brief}`);
}

const browser = await webkit.launch({ headless: true });
const ctx = await browser.newContext({
  viewport: { width: 1024, height: 768 },
  ignoreHTTPSErrors: true,
  // No cache so every run is clean
  storageState: undefined,
});

// Empty cookies/cache for this context
await ctx.clearCookies();

const page = await ctx.newPage();

page.on('console', msg => log('console.' + msg.type(), { text: msg.text() }));
page.on('pageerror', err => log('pageerror', { message: err.message, stack: err.stack?.split('\n').slice(0, 5).join(' | ') }));
page.on('requestfailed', req => log('req.FAIL', { url: req.url(), failure: req.failure()?.errorText }));
page.on('response', res => {
  const u = res.url();
  if (u.endsWith('.wasm') || u.endsWith('.data') || u.endsWith('.js') || u.endsWith('mudclient.html')) {
    log('response', { url: u.replace('http://10.8.0.1:8080', ''), status: res.status() });
  }
});

t0 = Date.now();
log('start', { url: URL });

// Go but don't wait for load — we want to see the whole lifecycle
const nav = page.goto(URL, { waitUntil: 'commit', timeout: 20000 }).catch(e => log('goto.err', { message: e.message }));

// Schedule screenshots
const shots = SCREENSHOT_AT.map(at => (async () => {
  await new Promise(r => setTimeout(r, at));
  try {
    const p = `${OUTDIR}/shot-${at}ms.png`;
    await page.screenshot({ path: p, fullPage: false });
    log('screenshot', { path: p });
  } catch (e) {
    log('screenshot.err', { at, message: e.message });
  }
})());

// Periodically probe Module / arguments_ / canvas state
const probes = [10000, 25000, 40000].map(at => (async () => {
  await new Promise(r => setTimeout(r, at));
  try {
    const state = await page.evaluate(() => ({
      moduleArgs: typeof Module !== 'undefined' ? JSON.stringify(Module.arguments) : 'no Module',
      canvasSize: (() => { const c = document.getElementById('canvas'); return c ? `${c.width}x${c.height}` : 'no canvas'; })(),
      bodyText: document.body.innerText.slice(0, 200),
    }));
    log('state@' + at, state);
  } catch (e) {
    log('probe.err', { at, message: e.message });
  }
})());

await nav;
await new Promise(r => setTimeout(r, DURATION_MS));
await Promise.all([...shots, ...probes]);

// Final dump
fs.writeFileSync(`${OUTDIR}/events.json`, JSON.stringify(events, null, 2));
console.log(`\n\n=== SUMMARY ===`);
console.log(`URL:          ${URL}`);
console.log(`Duration:     ${DURATION_MS/1000}s`);
console.log(`Output dir:   ${OUTDIR}`);
console.log(`Console msgs: ${events.filter(e => e.kind.startsWith('console')).length}`);
console.log(`Errors:       ${events.filter(e => e.kind === 'pageerror' || e.kind.endsWith('.err')).length}`);
console.log(`Req failures: ${events.filter(e => e.kind === 'req.FAIL').length}`);
console.log(`Last state:   ${events.filter(e => e.kind.startsWith('state@')).slice(-1)[0]?.bodyText || 'n/a'}`);

await browser.close();
process.exit(0);
